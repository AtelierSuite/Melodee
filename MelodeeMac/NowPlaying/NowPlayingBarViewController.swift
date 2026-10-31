//
//  NowPlayingBarViewController.swift
//  Melodee
//

import AppKit

/// The bar below the browser that shows what's playing and controls playback.
final class NowPlayingBarViewController: NSViewController {

    private let player = MacServices.shared.player
    private let artworkView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let previousButton = NowPlayingBarViewController.button("backward.fill", "NowPlaying.Previous")
    private let playPauseButton = NowPlayingBarViewController.button("play.fill", "NowPlaying.Play")
    private let nextButton = NowPlayingBarViewController.button("forward.fill", "NowPlaying.Next")
    private let elapsedLabel = NSTextField(labelWithString: "")
    private let remainingLabel = NSTextField(labelWithString: "")
    private let progressBar = FlatProgressBar()
    private let repeatButton = NowPlayingBarViewController.button("repeat", "NowPlaying.Repeat")
    private let queueButton = NowPlayingBarViewController.button("list.bullet", "NowPlaying.Queue")
    private var playerObserver: NSObjectProtocol?
    private var progressTimer: Timer?
    private var queuePopover: NSPopover?

    private static let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    override func loadView() {
        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 6
        artworkView.layer?.masksToBounds = true
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabelColor
        for label in [titleLabel, subtitleLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        for label in [elapsedLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            label.textColor = .secondaryLabelColor
        }
        remainingLabel.alignment = .right
        playPauseButton.symbolConfiguration = .init(pointSize: 20, weight: .regular)
        progressBar.onScrub = { [weak self] time in
            self?.showTimes(currentTime: time)
        }
        progressBar.onSeek = { [weak self] time in
            self?.player.seek(to: time)
        }
        let targets: [(NSControl, Selector)] = [
            (previousButton, #selector(previousTrack(_:))),
            (playPauseButton, #selector(togglePlayPause(_:))),
            (nextButton, #selector(nextTrack(_:))),
            (repeatButton, #selector(cycleRepeatMode(_:))),
            (queueButton, #selector(toggleQueue(_:)))
        ]
        for (control, action) in targets {
            control.target = self
            control.action = action
        }

        // Title and artist on one line above the seek bar, as in Music's playback area
        let titleRow = NSStackView(views: [titleLabel, subtitleLabel])
        titleRow.spacing = 6
        titleRow.alignment = .firstBaseline
        let progressStack = NSStackView(views: [elapsedLabel, progressBar, remainingLabel])
        progressStack.spacing = 8
        progressStack.alignment = .centerY
        let infoStack = NSStackView(views: [titleRow, progressStack])
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 4
        infoStack.setHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let transportStack = NSStackView(views: [previousButton, playPauseButton, nextButton])
        transportStack.spacing = 10
        let barStack = NSStackView(views: [transportStack, artworkView, infoStack, repeatButton, queueButton])
        barStack.spacing = 14
        barStack.alignment = .centerY
        barStack.distribution = .fill
        barStack.setCustomSpacing(10, after: artworkView)
        barStack.setCustomSpacing(10, after: repeatButton)
        // Only the title and seek bar stretch, so the controls stay packed at the edges
        for fixedView in [transportStack, artworkView, repeatButton, queueButton] {
            fixedView.setContentHuggingPriority(.required, for: .horizontal)
        }
        progressBar.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let contentView = NSView()
        barStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(barStack)
        let container = DropGlassView()
        container.contentView = contentView
        // Dropping audio files and folders on the bar adds them to the end of the queue
        container.canDrop = { urls in
            !FilesystemManager.playableFiles(for: urls, types: [.audio]).isEmpty
        }
        container.onDrop = { [weak self] urls in
            let files = FilesystemManager.playableFiles(for: urls, types: [.audio])
            guard !files.isEmpty else { return false }
            self?.player.playLast(files)
            return true
        }
        NSLayoutConstraint.activate([
            barStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            barStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            barStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            barStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            artworkView.widthAnchor.constraint(equalToConstant: 40),
            artworkView.heightAnchor.constraint(equalToConstant: 40),
            progressStack.widthAnchor.constraint(equalTo: infoStack.widthAnchor),
            infoStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            progressBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            elapsedLabel.widthAnchor.constraint(equalToConstant: 40),
            remainingLabel.widthAnchor.constraint(equalToConstant: 44)
        ])
        view = container
        playerObserver = NotificationCenter.default.addObserver(
            forName: MacPlayer.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePlayerState()
            }
        }
        updatePlayerState()
    }

    /// Keeps the glass a capsule at whatever height the bar ends up.
    override func viewDidLayout() {
        super.viewDidLayout()
        (view as? NSGlassEffectView)?.cornerRadius = view.bounds.height / 2
    }

    private static func button(_ symbolName: String, _ labelKey: String) -> NSButton {
        let label = MacText.string(labelKey)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.toolTip = label
        button.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        return button
    }

    private func updatePlayerState() {
        let metadata = player.metadata
        titleLabel.stringValue = metadata?.title ?? MacText.string("NowPlaying.NotPlaying")
        subtitleLabel.stringValue = metadata?.subtitle ?? ""
        subtitleLabel.isHidden = metadata == nil
        artworkView.image = metadata?.artwork ?? NSImage(named: "Album.Generic")
        let isPlaying = player.isPlaying
        let playPauseKey = isPlaying ? "NowPlaying.Pause" : "NowPlaying.Play"
        playPauseButton.image = NSImage(
            systemSymbolName: isPlaying ? "pause.fill" : "play.fill",
            accessibilityDescription: MacText.string(playPauseKey)
        )
        playPauseButton.toolTip = MacText.string(playPauseKey)
        playPauseButton.isEnabled = player.canPlay
        previousButton.isEnabled = player.canGoToPreviousTrack
        nextButton.isEnabled = player.canGoToNextTrack
        updateRepeatButton()
        updateProgress()
        if isPlaying {
            startProgressTimer()
        } else {
            progressTimer?.invalidate()
            progressTimer = nil
        }
        (queuePopover?.contentViewController as? QueueViewController)?.reload()
    }

    private func updateRepeatButton() {
        let symbolName = player.repeatMode == .single ? "repeat.1" : "repeat"
        repeatButton.image = NSImage(systemSymbolName: symbolName,
                                     accessibilityDescription: MacText.string("NowPlaying.Repeat"))
        repeatButton.contentTintColor = player.repeatMode == .none ? .secondaryLabelColor : .controlAccentColor
    }

    private func updateProgress() {
        guard let time = player.playbackTime else {
            progressBar.doubleValue = 0
            progressBar.isEnabled = false
            elapsedLabel.stringValue = "--:--"
            remainingLabel.stringValue = "--:--"
            return
        }
        progressBar.isEnabled = player.supportsSeeking
        progressBar.maxValue = time.totalTime
        // Leave the bar and times alone while they're being dragged
        guard !progressBar.isDragging else { return }
        progressBar.doubleValue = time.currentTime
        showTimes(currentTime: time.currentTime)
    }

    private func showTimes(currentTime: TimeInterval) {
        let totalTime = progressBar.maxValue
        elapsedLabel.stringValue = Self.timeFormatter.string(from: currentTime) ?? ""
        remainingLabel.stringValue = "-" + (Self.timeFormatter.string(from: max(totalTime - currentTime, 0)) ?? "")
    }

    private func startProgressTimer() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateProgress()
            }
        }
    }

    @objc private func previousTrack(_ sender: Any?) {
        player.backToPreviousTrack()
    }

    @objc private func togglePlayPause(_ sender: Any?) {
        player.togglePlayPause()
    }

    @objc private func nextTrack(_ sender: Any?) {
        player.skipToNextTrack()
    }

    @objc private func cycleRepeatMode(_ sender: Any?) {
        player.cycleRepeatMode()
    }

    @objc func toggleQueue(_ sender: Any?) {
        if let queuePopover, queuePopover.isShown {
            queuePopover.close()
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = QueueViewController()
        popover.show(relativeTo: queueButton.bounds, of: queueButton, preferredEdge: .maxY)
        queuePopover = popover
    }
}
