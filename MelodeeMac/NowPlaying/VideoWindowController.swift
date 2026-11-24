//
//  VideoWindowController.swift
//  Melodee
//

import AppKit
import AVKit
import SwiftUI

/// Shows the playing video in its own window, which opens when a video starts and closes when the queue moves on.
/// Closing the window pauses the video. Videos played with the Extended engine show VLCKit's video
/// in place of AVKit's player view. Subtitles and synced lyrics render over either engine, and hovering
/// reveals a captions menu button in the corner.
@MainActor
final class VideoWindowController: NSWindowController, NSWindowDelegate {

    private let player = MacServices.shared.player
    private let rootContainer = VideoWindowContentView()
    private let playerView = AVPlayerView()
    /// Holds the view VLCKit draws into.
    private let extendedVideoContainer: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }()
    private let subtitleOverlayHost: NSHostingView<MacVideoSubtitleOverlay>
    private let subtitlesButton = NSButton()
    private var playerObserver: NSObjectProtocol?
    /// The video the window was last sized for, so it's only resized when a new video starts.
    private var sizedVideoPath: String?
    private var shownVideoPath: String?

    private static let defaultContentSize = CGSize(width: 800, height: 450)

    init() {
        subtitleOverlayHost = NSHostingView(rootView: MacVideoSubtitleOverlay(controller: player.subtitleController))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titlebarAppearsTransparent = true
        window.isRestorable = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.backgroundColor = .black
        window.minSize = CGSize(width: 320, height: 180)
        window.setFrameAutosaveName("VideoWindow")
        super.init(window: window)
        window.delegate = self

        playerView.player = player.videoPlayer
        // Playback is controlled from the Now Playing bar and Controls menu
        playerView.controlsStyle = .none

        let extendedVideoView = player.extendedVideoPlayer.videoView
        extendedVideoView.frame = extendedVideoContainer.bounds
        extendedVideoView.autoresizingMask = [.width, .height]
        extendedVideoContainer.addSubview(extendedVideoView)

        rootContainer.wantsLayer = true
        rootContainer.layer?.backgroundColor = NSColor.black.cgColor

        for subview in [playerView, extendedVideoContainer, subtitleOverlayHost] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            rootContainer.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: rootContainer.topAnchor),
                subview.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor),
                subview.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor)
            ])
        }
        extendedVideoContainer.isHidden = true

        configureSubtitlesButton()
        rootContainer.addSubview(subtitlesButton)
        NSLayoutConstraint.activate([
            subtitlesButton.topAnchor.constraint(equalTo: rootContainer.topAnchor, constant: 12),
            subtitlesButton.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor, constant: -12),
            subtitlesButton.widthAnchor.constraint(equalToConstant: 32),
            subtitlesButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        rootContainer.onHoverChanged = { [weak self] isHovering in
            self?.setOverlayControlsVisible(isHovering)
        }

        window.contentView = rootContainer
        if !window.setFrameUsingName("VideoWindow") {
            window.center()
        }
        playerObserver = NotificationCenter.default.addObserver(
            forName: MacPlayer.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateWindow()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubtitlesButton() {
        subtitlesButton.translatesAutoresizingMaskIntoConstraints = false
        subtitlesButton.isBordered = false
        subtitlesButton.wantsLayer = true
        subtitlesButton.layer?.cornerRadius = 16
        subtitlesButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        subtitlesButton.contentTintColor = .white
        subtitlesButton.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        subtitlesButton.toolTip = MacText.shared("Subtitles.MenuTitle")
        subtitlesButton.target = self
        subtitlesButton.action = #selector(showSubtitlesMenu(_:))
        subtitlesButton.alphaValue = 0
        updateSubtitlesButtonAppearance()
    }

    private func updateSubtitlesButtonAppearance() {
        let isActive = player.subtitleController.selectedTrackID != nil
        let symbolName = isActive ? "captions.bubble.fill" : "captions.bubble"
        subtitlesButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: MacText.shared("Subtitles.MenuTitle")
        )
    }

    private func setOverlayControlsVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            subtitlesButton.animator().alphaValue = visible ? 1.0 : 0.0
        }
    }

    @objc private func showSubtitlesMenu(_ sender: NSButton) {
        let menu = NSMenu()
        SubtitleMenuBuilder.populate(menu, player: player, target: NSApp.delegate as? AppDelegate)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    private func updateWindow() {
        guard let window else { return }
        guard player.isPlayingVideo, let file = player.currentFile else {
            sizedVideoPath = nil
            shownVideoPath = nil
            if window.isVisible {
                window.orderOut(nil)
            }
            return
        }
        window.title = player.metadata?.title ?? file.name
        playerView.isHidden = player.isPlayingExtendedVideo
        extendedVideoContainer.isHidden = !player.isPlayingExtendedVideo
        updateSubtitlesButtonAppearance()
        if let videoSize = player.videoSize, sizedVideoPath != file.path {
            sizedVideoPath = file.path
            fit(window, to: videoSize)
        }
        // Bring the window up for each new video, and again when a video closed mid-way is played
        if shownVideoPath != file.path || (!window.isVisible && player.isPlaying) {
            shownVideoPath = file.path
            showWindow(nil)
        }
    }

    /// Matches the window's shape to the video, keeping it on screen and no wider than it was.
    private func fit(_ window: NSWindow, to videoSize: CGSize) {
        window.contentAspectRatio = videoSize
        guard !window.styleMask.contains(.fullScreen) else { return }
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame.size
            ?? CGSize(width: 1280, height: 800)
        let currentWidth = window.contentLayoutRect.width
        let maxWidth = min(max(currentWidth, Self.defaultContentSize.width), videoSize.width, visibleFrame.width * 0.9)
        let maxHeight = visibleFrame.height * 0.9
        let scale = min(maxWidth / videoSize.width, maxHeight / videoSize.height, 1)
        let contentSize = CGSize(width: (videoSize.width * scale).rounded(), height: (videoSize.height * scale).rounded())
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        // Keep the window's top edge where it was
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(window.constrainFrameRect(frame, to: window.screen), display: true, animate: window.isVisible)
    }

    /// Closing the window pauses the video rather than leaving it playing out of sight.
    func windowWillClose(_ notification: Notification) {
        if player.isPlayingVideo {
            player.pause()
        }
    }
}

/// Observes `VideoSubtitleController` and renders captions/lyrics over the Mac video window.
private struct MacVideoSubtitleOverlay: View {
    var controller: VideoSubtitleController

    var body: some View {
        SubtitleOverlayView(
            text: controller.activeText,
            isLyrics: controller.isShowingLyrics,
            unsyncedLyrics: controller.unsyncedLyrics,
            isCompact: false,
            bottomPadding: 24.0
        )
    }
}

/// Tracks pointer hover in the video window so overlay controls fade in and out cleanly.
private final class VideoWindowContentView: NSView {

    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}
