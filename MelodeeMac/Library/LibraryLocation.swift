//
//  LibraryLocation.swift
//  Melodee
//

import Foundation

/// A place in the sidebar that the browser can show.
enum LibraryLocation: Hashable {
    case local
    case cloud
    case folder(ExternalFolderBookmark)

    var identifier: String {
        switch self {
        case .local: "local"
        case .cloud: "cloud"
        case .folder(let bookmark): "folder:\(bookmark.id.uuidString)"
        }
    }

    /// Folders use the name Finder shows, such as a localized name for the Music folder.
    @MainActor
    var title: String {
        switch self {
        case .local: MacText.string("Sidebar.OnMyMac")
        case .cloud: MacText.string("Sidebar.iCloudDrive")
        case .folder(let bookmark):
            MacServices.shared.externalFolders.resolvedURLs[bookmark.id]
                .map { FileManager.default.displayName(atPath: $0.path(percentEncoded: false)) } ?? bookmark.name
        }
    }

    var symbolName: String {
        switch self {
        case .local: "desktopcomputer"
        case .cloud: "icloud"
        case .folder: "folder"
        }
    }

    @MainActor
    var rootURL: URL? {
        let services = MacServices.shared
        switch self {
        case .local:
            return services.fileManager.documentsDirectoryURL
        case .cloud:
            guard let url = services.fileManager.cloudDocumentsDirectoryURL else { return nil }
            // The Documents folder only exists in iCloud once something creates it
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        case .folder(let bookmark):
            return services.externalFolders.resolvedURLs[bookmark.id]
                ?? services.externalFolders.resolveBookmark(bookmark)
        }
    }

    /// The library locations, then the folders added to the sidebar.
    @MainActor
    static var libraryLocations: [LibraryLocation] {
        MacServices.shared.fileManager.cloudDocumentsDirectoryURL == nil ? [.local] : [.local, .cloud]
    }

    @MainActor
    static var folderLocations: [LibraryLocation] {
        MacServices.shared.externalFolders.bookmarks.map { .folder($0) }
    }
}
