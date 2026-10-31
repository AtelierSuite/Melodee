//
//  MacServices.swift
//  Melodee
//

import Foundation

/// The managers shared by every window.
@MainActor
final class MacServices {

    static let shared = MacServices()

    let fileManager = FilesystemManager()
    let externalFolders = ExternalFoldersManager()
    let player = MacPlayer()

    private init() { }
}

extension Notification.Name {
    /// Posted when folders are added to or removed from the sidebar.
    static let libraryLocationsDidChange = Notification.Name("LibraryLocationsDidChange")
}
