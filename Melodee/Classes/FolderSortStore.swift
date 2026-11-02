import Foundation

/// Remembers the sort option and order chosen for each folder across launches.
/// Folders are keyed by the library they belong to and their path relative to it, rather than
/// by absolute path, because the app container and external folder locations can move between launches.
enum FolderSortStore {

    private static let storageKey = "FolderSortPreferences"

    struct Preference: Codable, Equatable {
        var option: String
        var order: String
    }

    static func preference(for key: String) -> (option: SortOption, order: SortOrder)? {
        guard let preference = preferences()[key],
              let option = SortOption(rawValue: preference.option),
              let order = SortOrder(rawValue: preference.order) else {
            return nil
        }
        return (option, order)
    }

    static func save(option: SortOption, order: SortOrder, for key: String) {
        var preferences = preferences()
        if option == .fileName && order == .ascending {
            // Default sort, so there is nothing worth remembering
            preferences.removeValue(forKey: key)
        } else {
            preferences[key] = Preference(option: option.rawValue, order: order.rawValue)
        }
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Builds a stable key for a folder.
    /// - Parameters:
    ///   - folderURL: The folder being displayed.
    ///   - roots: Known library roots, each paired with a stable identifier (e.g. `local`, `cloud`, `external:<UUID>`).
    static func key(for folderURL: URL, roots: [(id: String, url: URL)]) -> String {
        let folderPath = normalizedPath(folderURL)
        // Prefer the most specific library in case one is nested inside another
        let match = roots
            .map { (id: $0.id, path: normalizedPath($0.url)) }
            .filter { folderPath == $0.path || folderPath.hasPrefix($0.path + "/") }
            .max(by: { $0.path.count < $1.path.count })
        if let match {
            let relativePath = String(folderPath.dropFirst(match.path.count))
            return "\(match.id):\(relativePath.isEmpty ? "/" : relativePath)"
        }
        return "absolute:\(folderPath)"
    }

    private static func preferences() -> [String: Preference] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let preferences = try? JSONDecoder().decode([String: Preference].self, from: data) else {
            return [:]
        }
        return preferences
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        if path.hasPrefix("/private/var/") {
            path = String(path.dropFirst("/private".count))
        }
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
