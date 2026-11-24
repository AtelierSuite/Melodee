//
//  SubtitleEditorWindowController.swift
//  Melodee
//

import AppKit
import SwiftUI

/// Dedicated macOS window for editing timed subtitles and synced lyrics on a video file.
@MainActor
final class SubtitleEditorWindowController: NSWindowController, NSWindowDelegate {

    let filePath: String
    private let model: SubtitleEditorModel
    private let onClose: (String) -> Void

    init(file: FSFile, onSaved: @escaping (Bool) -> Void, onClose: @escaping (String) -> Void) {
        self.filePath = FilesystemManager.normalizedPath(file.path)
        let model = SubtitleEditorModel(videoURL: URL(filePath: file.path))
        self.model = model
        self.onClose = onClose

        let rootView = SubtitleEditorMacView(file: file, model: model, onSaved: onSaved)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "\(file.name) — \(MacText.shared("SubtitleEditor.Title"))"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 640))
        window.minSize = NSSize(width: 760, height: 500)
        window.setFrameAutosaveName("SubtitleEditorWindow")
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("SubtitleEditorWindow") {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        model.tearDown()
        onClose(filePath)
    }
}
