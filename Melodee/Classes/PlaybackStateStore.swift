import Foundation

/// A playback queue entry saved across launches.
/// Files are stored relative to the library they belong to rather than by absolute path,
/// because the app container and external folder locations can move between launches.
struct PersistedQueueItem: Codable {

    enum Root: Codable, Equatable {
        case documents
        case cloud
        case external(UUID)
        /// The file lives outside every known library; `path` is absolute.
        case absolute
    }

    var root: Root
    var path: String
    /// Fallback for files outside every known library, so access can be regained after a relaunch.
    var bookmarkData: Data?
    var type: FileType
    var playbackQueueID: String
}

/// The currently playing item and how far into it playback had progressed.
struct PersistedPlaybackPosition: Codable {
    var currentlyPlayingID: String
    var currentTime: TimeInterval
    var totalTime: TimeInterval?
}

/// The playback state restored at launch, with files that are no longer available removed.
struct RestoredPlaybackState {
    var queue: [FSFile]
    var currentlyPlayingID: String
    var currentTime: TimeInterval?
    var totalTime: TimeInterval?
}

class PlaybackStateStore {

    private let positionKey = "PlaybackPosition"
    private let repeatModeKey = "PlaybackRepeatMode"

    private let documentsDirectoryURL: URL?
    private let cloudDocumentsDirectoryURL: URL?
    private let externalFolders: ExternalFoldersManager?
    private let queueFileURL: URL?

    init(documentsDirectoryURL: URL?,
         cloudDocumentsDirectoryURL: URL?,
         externalFolders: ExternalFoldersManager?) {
        self.documentsDirectoryURL = documentsDirectoryURL
        self.cloudDocumentsDirectoryURL = cloudDocumentsDirectoryURL
        self.externalFolders = externalFolders
        // Kept out of Documents so it doesn't show up in the file browser or the Files app
        queueFileURL = try? FileManager.default
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
            .appending(path: "PlaybackQueue.json")
    }

    // MARK: - Saving

    func saveQueue(_ queue: [FSFile]) {
        guard let queueFileURL else { return }
        if queue.isEmpty {
            try? FileManager.default.removeItem(at: queueFileURL)
            return
        }
        let items = queue.map(persistedItem(for:))
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            debugPrint("Failed to save playback queue: \(error.localizedDescription)")
        }
    }

    func savePosition(_ position: PersistedPlaybackPosition?) {
        guard let position, let data = try? JSONEncoder().encode(position) else {
            UserDefaults.standard.removeObject(forKey: positionKey)
            return
        }
        UserDefaults.standard.set(data, forKey: positionKey)
    }

    func saveRepeatMode(_ repeatMode: RepeatMode) {
        UserDefaults.standard.set(repeatMode.rawValue, forKey: repeatModeKey)
    }

    // MARK: - Restoring

    func restoreRepeatMode() -> RepeatMode {
        UserDefaults.standard.string(forKey: repeatModeKey).flatMap(RepeatMode.init(rawValue:)) ?? .none
    }

    func restore() -> RestoredPlaybackState? {
        guard let queueFileURL,
              let data = try? Data(contentsOf: queueFileURL),
              let items = try? JSONDecoder().decode([PersistedQueueItem].self, from: data),
              !items.isEmpty else {
            return nil
        }
        let position = UserDefaults.standard.data(forKey: positionKey)
            .flatMap { try? JSONDecoder().decode(PersistedPlaybackPosition.self, from: $0) }

        var externalRootURLs: [UUID: URL?] = [:]
        var resolved: [(originalIndex: Int, file: FSFile)] = []
        for (index, item) in items.enumerated() {
            if let file = resolve(item, externalRootURLs: &externalRootURLs) {
                resolved.append((index, file))
            }
        }
        guard !resolved.isEmpty else { return nil }

        let queue = resolved.map(\.file)
        let savedIndex = items.firstIndex(where: { $0.playbackQueueID == position?.currentlyPlayingID })
        if let position, let savedIndex,
           resolved.contains(where: { $0.originalIndex == savedIndex }) {
            return RestoredPlaybackState(queue: queue,
                                         currentlyPlayingID: position.currentlyPlayingID,
                                         currentTime: position.currentTime,
                                         totalTime: position.totalTime)
        }
        // The last played file is gone, so continue from the next file that is still available
        let fallback = resolved.first(where: { $0.originalIndex >= (savedIndex ?? 0) }) ?? resolved[resolved.count - 1]
        return RestoredPlaybackState(queue: queue,
                                     currentlyPlayingID: fallback.file.playbackQueueID,
                                     currentTime: nil,
                                     totalTime: nil)
    }

    // MARK: - Locating files

    private func persistedItem(for file: FSFile) -> PersistedQueueItem {
        let filePath = Self.normalizedPath(URL(filePath: file.path).standardizedFileURL.path(percentEncoded: false))
        var roots: [(PersistedQueueItem.Root, URL)] = []
        if let documentsDirectoryURL { roots.append((.documents, documentsDirectoryURL)) }
        if let cloudDocumentsDirectoryURL { roots.append((.cloud, cloudDocumentsDirectoryURL)) }
        for (id, url) in externalFolders?.resolvedURLs ?? [:] {
            roots.append((.external(id), url))
        }
        // Prefer the most specific library in case one is nested inside another
        let match = roots
            .map { ($0.0, Self.normalizedPath($0.1.standardizedFileURL.path(percentEncoded: false))) }
            .filter { filePath.hasPrefix($0.1.hasSuffix("/") ? $0.1 : $0.1 + "/") }
            .max(by: { $0.1.count < $1.1.count })
        if let match {
            let (root, rootPath) = match
            let prefixLength = rootPath.hasSuffix("/") ? rootPath.count : rootPath.count + 1
            return PersistedQueueItem(root: root,
                                      path: String(filePath.dropFirst(prefixLength)),
                                      bookmarkData: nil,
                                      type: file.type,
                                      playbackQueueID: file.playbackQueueID)
        }
        let bookmarkData = try? URL(filePath: file.path).bookmarkData(options: .minimalBookmark,
                                                                      includingResourceValuesForKeys: nil,
                                                                      relativeTo: nil)
        return PersistedQueueItem(root: .absolute,
                                  path: file.path,
                                  bookmarkData: bookmarkData,
                                  type: file.type,
                                  playbackQueueID: file.playbackQueueID)
    }

    private func resolve(_ item: PersistedQueueItem, externalRootURLs: inout [UUID: URL?]) -> FSFile? {
        var url: URL?
        switch item.root {
        case .documents:
            url = documentsDirectoryURL?.appending(path: item.path)
        case .cloud:
            url = cloudDocumentsDirectoryURL?.appending(path: item.path)
        case .external(let id):
            if !externalRootURLs.keys.contains(id) {
                externalRootURLs[id] = externalFolders?.resolvedURLs[id] ?? externalFolders?.resolveURL(for: id)
            }
            url = externalRootURLs[id]??.appending(path: item.path)
        case .absolute:
            url = URL(filePath: item.path)
        }
        if !(url.map(Self.isAvailable) ?? false), let bookmarkData = item.bookmarkData {
            var isStale = false
            if let bookmarkedURL = try? URL(resolvingBookmarkData: bookmarkData,
                                            options: .withoutUI,
                                            relativeTo: nil,
                                            bookmarkDataIsStale: &isStale) {
                _ = bookmarkedURL.startAccessingSecurityScopedResource()
                url = bookmarkedURL
            }
        }
        guard let url, Self.isAvailable(url) else {
            debugPrint("Dropping unavailable file from restored queue: \(item.path)")
            return nil
        }
        return FSFile(name: url.deletingPathExtension().lastPathComponent,
                      extension: url.pathExtension.lowercased(),
                      path: url.path(percentEncoded: false),
                      type: item.type,
                      playbackQueueID: item.playbackQueueID)
    }

    /// A file counts as available if it is on disk or is an iCloud file that can be downloaded on demand.
    private static func isAvailable(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path) || FSFile.isEvicted(atPath: path)
    }

    /// Paths under /var are sometimes reported through the /private/var symlink, so compare without it.
    private static func normalizedPath(_ path: String) -> String {
        if path.hasPrefix("/private/var/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}
