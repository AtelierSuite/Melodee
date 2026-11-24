import Foundation

/// Remembers subtitle and lyrics track choices per file and globally across videos.
enum SubtitlePreferences {

    private static let perFileKey = "VideoSubtitles.PerFileSelection"
    private static let globalEnabledKey = "VideoSubtitles.GlobalEnabled"
    private static let preferredLanguageKey = "VideoSubtitles.PreferredLanguage"
    private static let prefersLyricsKey = "VideoSubtitles.PrefersLyrics"
    private static let maxStoredFiles = 500
    private static let offValue = "__off__"

    static var isEnabledGlobally: Bool {
        get { UserDefaults.standard.bool(forKey: globalEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: globalEnabledKey) }
    }

    static var preferredLanguageCode: String? {
        get { UserDefaults.standard.string(forKey: preferredLanguageKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferredLanguageKey) }
    }

    static var prefersLyrics: Bool {
        get { UserDefaults.standard.bool(forKey: prefersLyricsKey) }
        set { UserDefaults.standard.set(newValue, forKey: prefersLyricsKey) }
    }

    /// Saves the user's explicit track choice for `filePath` (or `nil` for Off) and updates global preferences.
    static func saveSelection(_ track: VideoSubtitleTrack?, for filePath: String) {
        let key = fileKey(for: filePath)
        var map = perFileSelections()
        map[key] = track?.id ?? offValue
        if map.count > maxStoredFiles {
            let overflow = map.count - maxStoredFiles
            for staleKey in map.keys.prefix(overflow) where staleKey != key {
                map.removeValue(forKey: staleKey)
            }
        }
        UserDefaults.standard.set(map, forKey: perFileKey)

        if let track {
            isEnabledGlobally = true
            prefersLyrics = track.isLyrics
            if let lang = track.languageCode, !lang.isEmpty {
                preferredLanguageCode = lang
            }
        } else {
            isEnabledGlobally = false
        }
    }

    /// Chooses the initial track for a newly opened video based on per-file history, then global preference.
    static func resolveInitialTrack(
        for filePath: String,
        availableTracks: [VideoSubtitleTrack]
    ) -> VideoSubtitleTrack? {
        guard !availableTracks.isEmpty else { return nil }
        let key = fileKey(for: filePath)
        if let saved = perFileSelections()[key] {
            if saved == offValue {
                return nil
            }
            if let exact = availableTracks.first(where: { $0.id == saved }) {
                return exact
            }
        }

        guard isEnabledGlobally else { return nil }

        let candidates: [VideoSubtitleTrack] = {
            let matchingKind = availableTracks.filter { $0.isLyrics == prefersLyrics }
            return matchingKind.isEmpty ? availableTracks : matchingKind
        }()

        if let preferred = preferredLanguageCode,
           let matched = matchTrack(in: candidates, languageCode: preferred)
            ?? matchTrack(in: availableTracks, languageCode: preferred) {
            return matched
        }

        if let systemLang = Locale.preferredLanguages.first,
           let matched = matchTrack(in: candidates, languageCode: systemLang)
            ?? matchTrack(in: availableTracks, languageCode: systemLang) {
            return matched
        }

        return candidates.first
    }

    // The app container's path changes between installs, so files in Documents are keyed relative to it
    private static func fileKey(for filePath: String) -> String {
        let path = FilesystemManager.normalizedPath(filePath)
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let documentsPath = FilesystemManager.normalizedPath(documentsURL.path(percentEncoded: false))
            if path.hasPrefix(documentsPath + "/") {
                return "documents:" + path.dropFirst(documentsPath.count)
            }
        }
        return path
    }

    private static func perFileSelections() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: perFileKey) as? [String: String] ?? [:]
    }

    private static func matchTrack(
        in tracks: [VideoSubtitleTrack],
        languageCode: String
    ) -> VideoSubtitleTrack? {
        let targetLang = Locale.Language(identifier: languageCode)
        let targetPrimary = targetLang.languageCode?.identifier.lowercased()
        if let exact = tracks.first(where: {
            $0.languageCode?.caseInsensitiveCompare(languageCode) == .orderedSame
        }) {
            return exact
        }
        guard let targetPrimary else { return nil }
        return tracks.first { track in
            guard let code = track.languageCode else { return false }
            return Locale.Language(identifier: code).languageCode?.identifier.lowercased() == targetPrimary
        }
    }
}
