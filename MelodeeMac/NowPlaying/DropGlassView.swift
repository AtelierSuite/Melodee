//
//  DropGlassView.swift
//  Melodee
//

import AppKit

/// The Now Playing bar's glass, which takes audio files and folders dropped on it and tints while they're over it.
final class DropGlassView: NSGlassEffectView {

    /// Called with the dropped URLs. Returns whether anything was added.
    var onDrop: (([URL]) -> Bool)?
    /// Whether the dragged URLs hold anything that can be dropped.
    var canDrop: (([URL]) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard canDrop?(urls(from: sender)) ?? false else { return [] }
        tintColor = .controlAccentColor.withAlphaComponent(0.3)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        tintColor = nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        tintColor = nil
        return onDrop?(urls(from: sender)) ?? false
    }

    private func urls(from info: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
