//
//  VideoWindowController.swift
//  Melodee
//

import AppKit
import AVKit

/// Shows the playing video in its own window, which opens when a video starts and closes when the queue moves on.
/// Closing the window pauses the video. Videos played with the Extended engine show VLCKit's video
/// in place of AVKit's player view. Neither shows its own controls: videos are controlled from the
/// Now Playing bar and Controls menu.
@MainActor
final class VideoWindowController: NSWindowController, NSWindowDelegate {

    private let player = MacServices.shared.player
    private let playerView = AVPlayerView()
    /// Holds the view VLCKit draws into.
    private let extendedVideoContainer: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }()
    private var playerObserver: NSObjectProtocol?
    /// The video the window was last sized for, so it's only resized when a new video starts.
    private var sizedVideoPath: String?
    private var shownVideoPath: String?

    private static let defaultContentSize = CGSize(width: 800, height: 450)

    init() {
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
        // Playback is controlled only from the Now Playing bar and Controls menu
        playerView.controlsStyle = .none
        let extendedVideoView = player.extendedVideoPlayer.videoView
        extendedVideoView.frame = extendedVideoContainer.bounds
        extendedVideoView.autoresizingMask = [.width, .height]
        extendedVideoContainer.addSubview(extendedVideoView)
        window.contentView = playerView
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
        let contentView: NSView = player.isPlayingExtendedVideo ? extendedVideoContainer : playerView
        if window.contentView !== contentView {
            window.contentView = contentView
        }
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
