import Foundation

extension MediaPlayerManager {

    /// Whether there are tracks before the current one to clear.
    func canClearPlayedTracks() -> Bool {
        guard isPlaybackActive, !queue.isEmpty else { return false }
        return currentlyPlayingIndex() > 0
    }

    /// Whether there are tracks after the current one to clear.
    func canClearUpcomingTracks() -> Bool {
        guard isPlaybackActive, !queue.isEmpty else { return false }
        return currentlyPlayingIndex() < queue.count - 1
    }

    /// Removes the tracks before the current one, leaving the current track and those after it.
    func clearPlayedTracks() {
        guard canClearPlayedTracks() else { return }
        queue.removeSubrange(..<currentlyPlayingIndex())
        setNowPlaying()
    }

    /// Removes the tracks after the current one, leaving the current track and those before it.
    func clearUpcomingTracks() {
        guard canClearUpcomingTracks() else { return }
        queue.removeSubrange((currentlyPlayingIndex() + 1)...)
        setNowPlaying()
    }

    /// Saves the queue as a playlist named `name`, in the deepest folder that holds every queued file.
    /// That folder must be inside one of `rootDirectoryURLs`, otherwise it's saved in the first of them.
    /// Returns where it was saved.
    @discardableResult
    func saveQueueAsPlaylist(named name: String, rootDirectoryURLs: [URL]) -> URL? {
        let files = queue.filter { $0.isPlayableMedia() }
        guard !files.isEmpty else { return nil }
        let commonURL = Self.commonDirectory(of: files.map { URL(fileURLWithPath: $0.containingFolderPath()) })
        let saveDirectoryURL: URL
        if let commonURL, rootDirectoryURLs.contains(where: { Self.isURL(commonURL, inside: $0) }) {
            saveDirectoryURL = commonURL
        } else if let rootURL = rootDirectoryURLs.first {
            saveDirectoryURL = rootURL
        } else {
            return nil
        }
        return PlaylistManager.create(name: Self.availablePlaylistName(name, in: saveDirectoryURL),
                                      in: saveDirectoryURL, audioFiles: files)
    }

    /// The deepest folder that contains every one of the given folders.
    private static func commonDirectory(of directoryURLs: [URL]) -> URL? {
        let componentLists = directoryURLs.map { $0.standardizedFileURL.pathComponents }
        guard var common = componentLists.first else { return nil }
        for components in componentLists.dropFirst() {
            let length = zip(common, components).prefix { $0 == $1 }.count
            common = Array(common.prefix(length))
        }
        guard common.count > 1 else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true)
    }

    private static func isURL(_ url: URL, inside directoryURL: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let directory = directoryURL.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return path.starts(with: directory)
    }

    /// The name with a number added if a playlist by that name is already in the folder,
    /// so saving never replaces an existing playlist.
    private static func availablePlaylistName(_ name: String, in directoryURL: URL) -> String {
        func exists(_ candidate: String) -> Bool {
            let url = directoryURL
                .appendingPathComponent(candidate.replacingOccurrences(of: "/", with: "-"))
                .appendingPathExtension(PlaylistManager.playlistExtension)
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }
        guard exists(name) else { return name }
        var number = 2
        while exists("\(name) \(number)") {
            number += 1
        }
        return "\(name) \(number)"
    }
}
