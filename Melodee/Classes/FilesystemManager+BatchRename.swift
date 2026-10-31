import Foundation

extension FilesystemManager {

    /// Renames the files in a batch rename preview, skipping files that are unchanged or have problems.
    /// Renames are ordered so that files can take over names freed up by other files in the batch,
    /// and files that swap names are moved through a temporary name.
    func batchRename(_ items: [BatchRenameItem]) -> BatchRenameResult {
        struct PendingRename {
            let originalPath: String
            var currentURL: URL
            let targetURL: URL
            let fileName: String
            var isAtTemporaryName = false
            var folderPath: String { targetURL.deletingLastPathComponent().path(percentEncoded: false) }
        }

        var result = BatchRenameResult()
        var pending: [PendingRename] = items.filter { $0.status == .willRename }.map { item in
            let url = URL(filePath: item.file.path)
            return PendingRename(originalPath: item.file.path,
                                 currentURL: url,
                                 targetURL: url.deletingLastPathComponent().appending(path: item.newFileName),
                                 fileName: url.lastPathComponent)
        }
        var occupiedNames: [String: Set<String>] = [:]
        for folderPath in Set(pending.map(\.folderPath)) {
            occupiedNames[folderPath] = Set(BatchRenamePlanner.existingFileNames(in: folderPath)
                .map(BatchRenamePlanner.comparisonKey))
        }

        func move(_ rename: PendingRename, to url: URL) throws {
            try manager.moveItem(at: rename.currentURL, to: url)
            let folderPath = rename.folderPath
            let currentKey = BatchRenamePlanner.comparisonKey(rename.currentURL.lastPathComponent)
            occupiedNames[folderPath]?.remove(currentKey)
            occupiedNames[folderPath]?.insert(BatchRenamePlanner.comparisonKey(url.lastPathComponent))
        }

        func fail(_ rename: PendingRename, with error: Error) {
            debugPrint("Error occurred while renaming file: \(error.localizedDescription)")
            // Restore the original name if the file was moved to a temporary name
            if rename.isAtTemporaryName {
                try? manager.moveItem(at: rename.currentURL, to: URL(filePath: rename.originalPath))
            }
            result.failures.append(BatchRenameFailure(fileName: rename.fileName,
                                                      reason: error.localizedDescription))
        }

        while !pending.isEmpty {
            var hasRenamedFile = false
            var index = 0
            while index < pending.count {
                let rename = pending[index]
                let currentKey = BatchRenamePlanner.comparisonKey(rename.currentURL.lastPathComponent)
                let targetKey = BatchRenamePlanner.comparisonKey(rename.targetURL.lastPathComponent)
                let isTargetFree = targetKey == currentKey ||
                    !(occupiedNames[rename.folderPath]?.contains(targetKey) ?? false)
                guard isTargetFree else {
                    index += 1
                    continue
                }
                do {
                    try move(rename, to: rename.targetURL)
                    result.renamedPaths[BatchRenamePlanner.normalizedPath(rename.originalPath)] =
                        rename.targetURL.path(percentEncoded: false)
                } catch {
                    fail(rename, with: error)
                }
                pending.remove(at: index)
                hasRenamedFile = true
            }

            guard !hasRenamedFile, !pending.isEmpty else { continue }
            // Every remaining file is waiting on a name held by another file, so break the cycle
            // by moving one of them out of the way
            if let index = pending.firstIndex(where: { !$0.isAtTemporaryName }) {
                var rename = pending[index]
                let temporaryURL = rename.currentURL.deletingLastPathComponent()
                    .appending(path: ".melodee-rename-\(UUID().uuidString)")
                do {
                    try move(rename, to: temporaryURL)
                    rename.currentURL = temporaryURL
                    rename.isAtTemporaryName = true
                    pending[index] = rename
                } catch {
                    fail(rename, with: error)
                    pending.remove(at: index)
                }
            } else {
                // The remaining names are held by files outside of the batch
                for rename in pending {
                    fail(rename, with: CocoaError(.fileWriteFileExists))
                }
                pending.removeAll()
            }
        }

        return result
    }

    /// Rewrites playlists under `rootURL` that refer to files which have been renamed.
    func updatePlaylists(in rootURL: URL, renamedPaths: [String: String]) {
        guard !renamedPaths.isEmpty,
              let enumerator = manager.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
            return
        }
        for case let playlistURL as URL in enumerator where PlaylistManager.isPlaylistFile(playlistURL) {
            guard var playlist = PlaylistManager.load(from: playlistURL) else { continue }
            let directoryURL = PlaylistManager.directoryURL(for: playlistURL)
            let normalizedDirectoryURL = URL(
                filePath: BatchRenamePlanner.normalizedPath(directoryURL.path(percentEncoded: false))
            )
            var isModified = false
            for index in playlist.files.indices {
                let fileURL = directoryURL.appendingPathComponent(playlist.files[index].relativePath)
                let key = BatchRenamePlanner.normalizedPath(fileURL.path(percentEncoded: false))
                if let newPath = renamedPaths[key],
                   let relativePath = PlaylistManager.relativePath(
                    from: normalizedDirectoryURL,
                    to: URL(filePath: BatchRenamePlanner.normalizedPath(newPath))
                   ) {
                    playlist.files[index].relativePath = relativePath
                    isModified = true
                }
            }
            if isModified {
                PlaylistManager.save(playlist, to: playlistURL)
            }
        }
    }
}
