//
//  Preferences.swift
//  Melodee
//

import Foundation

enum Preferences {

    static let browserViewModeKey = "BrowserViewMode"
    static let repeatModeKey = "RepeatMode"
    static let selectedLocationKey = "SelectedLibraryLocation"
    static let gridIconSizeKey = "GridIconSize"

    static var browserViewMode: BrowserViewMode {
        get { BrowserViewMode(rawValue: UserDefaults.standard.string(forKey: browserViewModeKey) ?? "") ?? .list }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: browserViewModeKey) }
    }

    static var repeatMode: RepeatMode {
        get { RepeatMode(rawValue: UserDefaults.standard.string(forKey: repeatModeKey) ?? "") ?? .none }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: repeatModeKey) }
    }

    static var gridIconSize: CGFloat {
        get {
            let size = UserDefaults.standard.double(forKey: gridIconSizeKey)
            return size > 0 ? size : BrowserGridItem.defaultIconSize
        }
        set { UserDefaults.standard.set(newValue, forKey: gridIconSizeKey) }
    }

    /// The sidebar location shown when the window opens, stored by its identifier.
    static var selectedLocation: String? {
        get { UserDefaults.standard.string(forKey: selectedLocationKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectedLocationKey) }
    }
}
