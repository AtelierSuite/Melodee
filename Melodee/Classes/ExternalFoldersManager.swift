import Foundation
import SwiftUI

struct ExternalFolderBookmark: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var bookmarkData: Data

    init(id: UUID = UUID(), name: String, bookmarkData: Data) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
    }
}

@Observable
class ExternalFoldersManager {

    @ObservationIgnored private let storageKey = "ExternalFolderBookmarks"
    @ObservationIgnored private let legacyStorageKey = "ExternalFolderBookmark"

    var bookmarks: [ExternalFolderBookmark] = []
    /// URLs of bookmarks that have been resolved and are being accessed, keyed by bookmark ID
    @ObservationIgnored private(set) var resolvedURLs: [UUID: URL] = [:]

    init() {
        loadBookmarks()
    }

    func bookmark(with id: UUID) -> ExternalFolderBookmark? {
        bookmarks.first(where: { $0.id == id })
    }

    // MARK: - Bookmark persistence

    func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ExternalFolderBookmark].self, from: data) else {
            // Migrate from old single bookmark if present
            migrateOldBookmark()
            return
        }
        bookmarks = decoded

        // Start accessing all bookmarked resources
        for bookmark in bookmarks {
            _ = resolveBookmark(bookmark)
        }
    }

    func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    @discardableResult
    func addBookmark(for url: URL) -> ExternalFolderBookmark? {
        let accessing = url.startAccessingSecurityScopedResource()
        guard accessing else { return nil }

        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            // Don't add duplicates
            if let existing = bookmarks.first(where: { $0.name == url.lastPathComponent }) {
                return existing
            }
            let bookmark = ExternalFolderBookmark(
                name: url.lastPathComponent,
                bookmarkData: bookmarkData
            )
            bookmarks.append(bookmark)
            saveBookmarks()
            return bookmark
        } catch {
            debugPrint("Failed to create bookmark: \(error)")
            url.stopAccessingSecurityScopedResource()
            return nil
        }
    }

    func unlink(_ bookmark: ExternalFolderBookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        deleteBookmarks(at: IndexSet(integer: index))
    }

    func deleteBookmarks(at offsets: IndexSet) {
        for offset in offsets {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarks[offset].bookmarkData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                url.stopAccessingSecurityScopedResource()
            }
            resolvedURLs.removeValue(forKey: bookmarks[offset].id)
        }
        bookmarks.remove(atOffsets: offsets)
        saveBookmarks()
    }

    func resolveBookmark(_ bookmark: ExternalFolderBookmark) -> URL? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark.bookmarkData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // Refresh bookmark data
                if let newData = try? url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ), let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                    bookmarks[index] = ExternalFolderBookmark(
                        id: bookmark.id,
                        name: bookmark.name,
                        bookmarkData: newData
                    )
                    saveBookmarks()
                }
            }
            guard url.startAccessingSecurityScopedResource() else {
                debugPrint("Failed to access security-scoped resource for: \(url)")
                return nil
            }
            resolvedURLs[bookmark.id] = url
            return url
        } catch {
            debugPrint("Failed to resolve bookmark: \(error)")
            return nil
        }
    }

    func resolveURL(for id: UUID) -> URL? {
        guard let bookmark = bookmark(with: id) else { return nil }
        return resolveBookmark(bookmark)
    }

    // MARK: - Migration

    func migrateOldBookmark() {
        guard let oldData = UserDefaults.standard.data(forKey: legacyStorageKey) else {
            return
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: oldData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let bookmarkData = isStale
                ? try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                : oldData
            let bookmark = ExternalFolderBookmark(name: url.lastPathComponent, bookmarkData: bookmarkData)
            bookmarks = [bookmark]
            saveBookmarks()
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
            _ = url.startAccessingSecurityScopedResource()
        } catch {
            debugPrint("Failed to migrate old bookmark: \(error)")
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        }
    }
}
