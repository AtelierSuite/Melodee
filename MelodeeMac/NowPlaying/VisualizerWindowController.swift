//
//  VisualizerWindowController.swift
//  Melodee
//

import AppKit
import SwiftUI

/// Shows the playing track's album art over the whole screen in a frameless window, which fades to the
/// visualizer when the art is clicked. Opened by clicking the artwork in the Now Playing bar, and closed
/// with its close button or the Escape key.
@MainActor
final class VisualizerWindowController: NSWindowController, NSWindowDelegate {

    static let shared = VisualizerWindowController()

    private let player = MacServices.shared.player
    private let model = VisualizerModel()
    private var playerObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    /// Keeps the display awake while the window is open.
    private var displayActivity: NSObjectProtocol?

    private static let fadeDuration: TimeInterval = 0.3

    private init() {
        let window = VisualizerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.hasShadow = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        super.init(window: window)
        window.delegate = self
        window.onCancel = { [weak self] in
            self?.cancel()
        }
        window.onMouseMoved = { [weak self] in
            self?.model.mouseMoveCount += 1
        }
        model.onClose = { [weak self] in
            self?.close()
        }
        let hostingView = NSHostingView(rootView: VisualizerView(model: model))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        playerObserver = NotificationCenter.default.addObserver(
            forName: MacPlayer.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateFromPlayer()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fitToScreen(self?.window?.screen)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isShown: Bool {
        model.isShown
    }

    /// Fades the window in over the screen that `sourceWindow` is on, starting with the album art.
    func show(over sourceWindow: NSWindow?) {
        guard let window else { return }
        if model.isShown {
            window.makeKeyAndOrderFront(nil)
            return
        }
        model.showsVisualizer = false
        model.isChoosingStyle = false
        updateFromPlayer()
        fitToScreen(sourceWindow?.screen ?? NSScreen.main)
        window.alphaValue = 0
        model.isShown = true
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            window.animator().alphaValue = 1
        }
        displayActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: "Showing the visualizer"
        )
    }

    /// Fades the window out.
    override func close() {
        guard let window, model.isShown else { return }
        model.isShown = false
        if let displayActivity {
            ProcessInfo.processInfo.endActivity(displayActivity)
            self.displayActivity = nil
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                // The window may have been opened again while it faded out
                guard !self.model.isShown else { return }
                window.orderOut(nil)
                NSApp.presentationOptions = []
            }
        }
    }

    /// Escape backs out of choosing a style first, then closes the window.
    private func cancel() {
        if model.isChoosingStyle {
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                model.isChoosingStyle = false
            }
        } else {
            close()
        }
    }

    private func fitToScreen(_ screen: NSScreen?) {
        guard let window, let screen else { return }
        window.setFrame(screen.frame, display: true)
    }

    private func updateFromPlayer() {
        let metadata = player.metadata
        model.title = metadata?.title ?? MacText.string("NowPlaying.NotPlaying")
        model.subtitle = metadata?.subtitle ?? ""
        if model.artwork !== metadata?.artwork {
            model.artwork = metadata?.artwork
        }
        model.isPlaying = player.isPlaying
        model.isPlayingVideo = player.isPlayingVideo
    }

    // MARK: - NSWindowDelegate

    /// Hides the menu bar and Dock while the window is in front, so it covers the whole screen.
    func windowDidBecomeKey(_ notification: Notification) {
        guard model.isShown else { return }
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
    }

    func windowDidResignKey(_ notification: Notification) {
        NSApp.presentationOptions = []
    }
}

/// A frameless window that can still become key, so it takes clicks and the Escape key.
private final class VisualizerWindow: NSWindow {

    var onCancel: (() -> Void)?
    var onMouseMoved: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .mouseMoved || event.type == .leftMouseDragged {
            onMouseMoved?()
        }
        super.sendEvent(event)
    }
}
