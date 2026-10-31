//
//  BrowserViewController+DragDrop.swift
//  Melodee
//

import AppKit

extension BrowserViewController {

    /// Files dragged in from Finder are copied into the folder being shown.
    func validateFileDrop(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard folderURL != nil, !isSearching, info.draggingSource as? NSView == nil else { return [] }
        return droppedURLs(from: info).isEmpty ? [] : .copy
    }

    func acceptFileDrop(_ info: any NSDraggingInfo) -> Bool {
        guard let folderURL else { return false }
        let urls = droppedURLs(from: info)
        guard !urls.isEmpty else { return false }
        Task { [weak self] in
            let failures = await Task.detached(priority: .userInitiated) {
                Self.copy(urls, into: folderURL)
            }.value
            guard let self else { return }
            reload()
            if let failure = failures.first {
                presentError(failure)
            }
        }
        return true
    }

    private func droppedURLs(from info: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    /// Copies each file, adding a number to its name when the folder already has one with the same name.
    nonisolated private static func copy(_ urls: [URL], into folderURL: URL) -> [Error] {
        var failures: [Error] = []
        let fileManager = FileManager.default
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            var destination = folderURL.appending(path: url.lastPathComponent)
            var copyNumber = 2
            while fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                let baseName = url.deletingPathExtension().lastPathComponent
                let name = url.pathExtension.isEmpty
                    ? "\(baseName) \(copyNumber)"
                    : "\(baseName) \(copyNumber).\(url.pathExtension)"
                destination = folderURL.appending(path: name)
                copyNumber += 1
            }
            do {
                try fileManager.copyItem(at: url, to: destination)
            } catch {
                failures.append(error)
            }
        }
        return failures
    }
}
