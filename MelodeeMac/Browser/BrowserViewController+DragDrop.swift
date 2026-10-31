//
//  BrowserViewController+DragDrop.swift
//  Melodee
//

import AppKit

extension BrowserViewController {

    /// Dropping on a folder moves items dragged from Melodee into it, and copies items dragged in from Finder.
    /// Dropping anywhere else copies Finder items into the folder being shown.
    func validateFileDrop(_ info: any NSDraggingInfo, onto targetFolder: BrowserItem?) -> NSDragOperation {
        let urls = droppedURLs(from: info)
        guard !urls.isEmpty else { return [] }
        if let targetFolder {
            let targetPath = FilesystemManager.normalizedPath(targetFolder.url.path(percentEncoded: false))
            let isDroppingIntoItself = urls.contains {
                FilesystemManager.normalizedPath($0.path(percentEncoded: false)) == targetPath
            }
            guard !isDroppingIntoItself else { return [] }
            return isFromBrowser(info) ? .move : .copy
        }
        guard folderURL != nil, !isSearching, !isFromBrowser(info) else { return [] }
        return .copy
    }

    func acceptFileDrop(_ info: any NSDraggingInfo, onto targetFolder: BrowserItem?) -> Bool {
        guard let destinationURL = targetFolder?.url ?? folderURL else { return false }
        let urls = droppedURLs(from: info)
        guard !urls.isEmpty else { return false }
        let isMove = isFromBrowser(info)
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                isMove
                    ? FilesystemManager.move(urls, into: destinationURL)
                    : (movedPaths: [:], failures: Self.copy(urls, into: destinationURL))
            }.value
            guard let self else { return }
            MacServices.shared.player.updateQueuedPaths(afterMoving: result.movedPaths)
            reload()
            if let failure = result.failures.first {
                presentError(failure)
            }
        }
        return true
    }

    private func isFromBrowser(_ info: any NSDraggingInfo) -> Bool {
        let source = info.draggingSource as? NSView
        return source === tableView || source === collectionView
    }

    private func droppedURLs(from info: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    /// Copies each item, adding a number to its name when the folder already has one with the same name.
    nonisolated private static func copy(_ urls: [URL], into folderURL: URL) -> [Error] {
        var failures: [Error] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            do {
                try FileManager.default.copyItem(at: url, to: FilesystemManager.uniqueDestination(for: url, in: folderURL))
            } catch {
                failures.append(error)
            }
        }
        return failures
    }
}
