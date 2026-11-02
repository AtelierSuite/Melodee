import Foundation

/// A playback queue entry saved across launches.
/// Files are stored relative to the library they belong to rather than by absolute path,
/// because the app container and external folder locations can move between launches.
struct PersistedQueueItem: Codable {

    enum Root: Codable, Hashable {
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

/// Identifies a file for play time tracking, relative to the library it belongs to.
struct PlayTimeKey: Codable, Hashable {
    var root: PersistedQueueItem.Root
    var path: String
}

/// How far into a file playback last got, so it can be continued later.
struct PersistedPlayTime: Codable {
    var key: PlayTimeKey
    var time: TimeInterval
    var totalTime: TimeInterval?
    var lastPlayedDate: Date
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
    private let playTimesFileURL: URL?
    private lazy var playTimes: [PlayTimeKey: PersistedPlayTime] = loadPlayTimes()
    /// Called whenever a saved play time is added, changed or removed.
    var onPlayTimesChange: (() -> Void)?

    /// Positions this close to the start or end aren't worth continuing from.
    static let minimumPlayTime: TimeInterval = 5.0
    static let endPlayTimeMargin: TimeInterval = 5.0
    /// Older entries are dropped beyond this many files.
    private static let maximumPlayTimeCount = 1000

    init(documentsDirectoryURL: URL?,
         cloudDocumentsDirectoryURL: URL?,
         externalFolders: ExternalFoldersManager?) {
        self.documentsDirectoryURL = documentsDirectoryURL
        self.cloudDocumentsDirectoryURL = cloudDocumentsDirectoryURL
        self.externalFolders = externalFolders
        // Kept out of Documents so it doesn't show up in the file browser or the Files app
        let supportDirectoryURL = try? FileManager.default
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
        queueFileURL = supportDirectoryURL?.appending(path: "PlaybackQueue.json")
        playTimesFileURL = supportDirectoryURL?.appending(path: "PlayTimes.json")
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

    // MARK: - Play times

    /// The position the file was last played to, if it is worth continuing from.
    func playTime(for file: FSFile) -> TimeInterval? {
        guard let entry = playTimes[playTimeKey(for: file.path)] else { return nil }
        if let totalTime = entry.totalTime, entry.time >= totalTime - Self.endPlayTimeMargin {
            return nil
        }
        return entry.time >= Self.minimumPlayTime ? entry.time : nil
    }

    /// How far through the file playback last got, from 0 to 1, if it can be continued.
    func playProgress(for file: FSFile) -> Double? {
        guard let time = playTime(for: file),
              let totalTime = playTimes[playTimeKey(for: file.path)]?.totalTime else { return nil }
        return min(max(time / totalTime, 0.0), 1.0)
    }

    /// Remembers how far into the file playback got. Positions near the start or end clear it instead.
    func savePlayTime(_ time: TimeInterval, totalTime: TimeInterval?, for file: FSFile) {
        let key = playTimeKey(for: file.path)
        let totalTime = totalTime.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        guard time.isFinite, time >= Self.minimumPlayTime,
              totalTime.map({ time < $0 - Self.endPlayTimeMargin }) ?? true else {
            removePlayTime(for: key)
            return
        }
        playTimes[key] = PersistedPlayTime(key: key, time: time, totalTime: totalTime, lastPlayedDate: .now)
        writePlayTimes()
    }

    func removePlayTime(for file: FSFile) {
        removePlayTime(for: playTimeKey(for: file.path))
    }

    /// Carries play times over to files that were renamed or moved.
    /// `newPath` returns the new location for a normalized absolute path, or nil if it didn't move.
    func movePlayTimes(_ newPath: (String) -> String?) {
        var isModified = false
        for (key, entry) in playTimes {
            guard let oldPath = absolutePath(for: key),
                  let movedPath = newPath(FilesystemManager.normalizedPath(oldPath)) else { continue }
            let newKey = playTimeKey(for: movedPath)
            guard newKey != key else { continue }
            playTimes[key] = nil
            var movedEntry = entry
            movedEntry.key = newKey
            playTimes[newKey] = movedEntry
            isModified = true
        }
        if isModified {
            writePlayTimes()
        }
    }

    private func removePlayTime(for key: PlayTimeKey) {
        guard playTimes.removeValue(forKey: key) != nil else { return }
        writePlayTimes()
    }

    private func playTimeKey(for path: String) -> PlayTimeKey {
        if let location = libraryLocation(for: path) {
            return PlayTimeKey(root: location.root, path: location.path)
        }
        return PlayTimeKey(root: .absolute, path: Self.normalizedPath(URL(filePath: path)
            .standardizedFileURL.path(percentEncoded: false)))
    }

    private func absolutePath(for key: PlayTimeKey) -> String? {
        switch key.root {
        case .documents:
            return documentsDirectoryURL?.appending(path: key.path).path(percentEncoded: false)
        case .cloud:
            return cloudDocumentsDirectoryURL?.appending(path: key.path).path(percentEncoded: false)
        case .external(let id):
            return externalFolders?.resolvedURLs[id]?.appending(path: key.path).path(percentEncoded: false)
        case .absolute:
            return key.path
        }
    }

    private func loadPlayTimes() -> [PlayTimeKey: PersistedPlayTime] {
        guard let playTimesFileURL,
              let data = try? Data(contentsOf: playTimesFileURL),
              let entries = try? JSONDecoder().decode([PersistedPlayTime].self, from: data) else {
            return [:]
        }
        return Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { $0.lastPlayedDate > $1.lastPlayedDate ? $0 : $1 })
    }

    private func writePlayTimes() {
        onPlayTimesChange?()
        guard let playTimesFileURL else { return }
        var entries = playTimes.values.sorted { $0.lastPlayedDate > $1.lastPlayedDate }
        if entries.count > Self.maximumPlayTimeCount {
            entries.removeLast(entries.count - Self.maximumPlayTimeCount)
            playTimes = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: playTimesFileURL, options: .atomic)
        } catch {
            debugPrint("Failed to save play times: \(error.localizedDescription)")
        }
    }

    // MARK: - Locating files

    /// The library a file belongs to, and its path relative to that library.
    private func libraryLocation(for path: String) -> (root: PersistedQueueItem.Root, path: String)? {
        let filePath = Self.normalizedPath(URL(filePath: path).standardizedFileURL.path(percentEncoded: false))
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
        guard let match else { return nil }
        let (root, rootPath) = match
        let prefixLength = rootPath.hasSuffix("/") ? rootPath.count : rootPath.count + 1
        return (root, String(filePath.dropFirst(prefixLength)))
    }

    private func persistedItem(for file: FSFile) -> PersistedQueueItem {
        if let location = libraryLocation(for: file.path) {
            return PersistedQueueItem(root: location.root,
                                      path: location.path,
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
