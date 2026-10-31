//
//  SidebarItem.swift
//  Melodee
//

import Foundation

/// A row in the sidebar: a section heading or a location within it.
final class SidebarItem: NSObject {

    enum Kind {
        case section(String)
        case location(LibraryLocation)
    }

    let kind: Kind
    var children: [SidebarItem]

    init(kind: Kind, children: [SidebarItem] = []) {
        self.kind = kind
        self.children = children
    }

    var location: LibraryLocation? {
        if case .location(let location) = kind { location } else { nil }
    }

    var isSection: Bool {
        if case .section = kind { true } else { false }
    }
}
