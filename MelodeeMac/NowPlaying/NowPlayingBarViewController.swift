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
    private let progressSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
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
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            label.textColor = .secondaryLabelColor
        }
        playPauseButton.symbolConfiguration = .init(pointSize: 20, weight: .regular)
        progressSlider.controlSize = .small
        progressSlider.isContinuous = true
        let targets: [(NSControl, Selector)] = [
            (previousButton, #selector(previousTrack(_:))),
            (playPauseButton, #selector(togglePlayPause(_:))),
            (nextButton, #selector(nextTrack(_:))),
            (progressSlider, #selector(seek(_:))),
            (repeatButton, #selector(cycleRepeatMode(_:))),
            (queueButton, #selector(toggleQueue(_:)))
        ]
        for (control, action) in targets {
            control.target = self
            control.action = action
        }

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2
        let transportStack = NSStackView(views: [previousButton, playPauseButton, nextButton])
        transportStack.spacing = 12
        let progressStack = NSStackView(views: [elapsedLabel, progressSlider, remainingLabel])
        progressStack.spacing = 6
        let barStack = NSStackView(views: [
            artworkView, titleStack, transportStack, progressStack, repeatButton, queueButton
        ])
        barStack.spacing = 14
        barStack.alignment = .centerY
        barStack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        barStack.setCustomSpacing(10, after: artworkView)
        barStack.setCustomSpacing(8, after: repeatButton)
        barStack.setHuggingPriority(.defaultLow, for: .horizontal)

        let separator = NSBox()
        separator.boxType = .separator
        let container = NSVisualEffectView()
        container.material = .titlebar
        container.blendingMode = .withinWindow
        for subview in [separator, barStack] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            barStack.topAnchor.constraint(equalTo: separator.bottomAnchor),
            barStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            barStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            barStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 44),
            artworkView.heightAnchor.constraint(equalToConstant: 44),
            titleStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            progressSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            progressSlider.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            elapsedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            remainingLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40)
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
            progressSlider.doubleValue = 0
            progressSlider.isEnabled = false
            elapsedLabel.stringValue = ""
            remainingLabel.stringValue = ""
            return
        }
        progressSlider.isEnabled = player.supportsSeeking
        progressSlider.maxValue = time.totalTime
        if NSEvent.pressedMouseButtons == 0 {
            progressSlider.doubleValue = time.currentTime
        }
        elapsedLabel.stringValue = Self.timeFormatter.string(from: time.currentTime) ?? ""
        remainingLabel.stringValue = "-" + (Self.timeFormatter.string(from: time.totalTime - time.currentTime) ?? "")
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

    @objc private func seek(_ sender: NSSlider) {
        player.seek(to: sender.doubleValue)
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
