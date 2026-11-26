import Foundation

extension PlaybackStateStore {

    func recordRecentlyPlayed(_ file: FSFile) {
        let key = playTimeKey(for: file.path)
        recentlyPlayed.removeAll { $0.key == key }
        recentlyPlayed.insert(PersistedRecentlyPlayed(key: key, type: file.type), at: 0)
        if recentlyPlayed.count > Self.maximumRecentlyPlayedCount {
            recentlyPlayed.removeLast(recentlyPlayed.count - Self.maximumRecentlyPlayedCount)
        }
        writeRecentlyPlayed()
    }

    /// Recently played files that still exist, most recent first. They may still need downloading.
    func recentlyPlayedFiles() -> [FSFile] {
        recentlyPlayed.compactMap { entry in
            guard let path = absolutePath(for: entry.key) else { return nil }
            return Self.file(atPath: path, type: entry.type)
        }
    }

    /// A stable identifier for the file that survives the app container moving between launches.
    func identifier(for file: FSFile) -> String? {
        guard let data = try? JSONEncoder().encode(playTimeKey(for: file.path)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func file(forIdentifier identifier: String, type: FileType) -> FSFile? {
        guard let data = identifier.data(using: .utf8),
              let key = try? JSONDecoder().decode(PlayTimeKey.self, from: data),
              let path = absolutePath(for: key) else { return nil }
        return Self.file(atPath: path, type: type)
    }

    static func file(atPath path: String, type: FileType) -> FSFile? {
        let url = URL(filePath: path)
        guard isAvailable(url) else { return nil }
        return FSFile(name: url.deletingPathExtension().lastPathComponent,
                      extension: url.pathExtension.lowercased(),
                      path: url.path(percentEncoded: false),
                      type: type)
    }
}
