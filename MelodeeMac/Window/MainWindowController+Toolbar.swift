//
//  MainWindowController+Toolbar.swift
//  Melodee
//

import AppKit

extension NSToolbarItem.Identifier {
    static let addFolder = NSToolbarItem.Identifier("AddFolder")
    static let navigation = NSToolbarItem.Identifier("Navigation")
    static let playAll = NSToolbarItem.Identifier("PlayAll")
    static let shuffle = NSToolbarItem.Identifier("Shuffle")
    static let viewMode = NSToolbarItem.Identifier("ViewMode")
    static let search = NSToolbarItem.Identifier("Search")
}

extension MainWindowController: NSToolbarDelegate {

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .flexibleSpace,
            .addFolder,
            .sidebarTrackingSeparator,
            .navigation,
            .flexibleSpace,
            .playAll,
            .shuffle,
            .viewMode,
            .search
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .addFolder: addFolderItem()
        case .navigation: navigationItem()
        case .playAll: buttonItem(.playAll, "Toolbar.PlayAll", "play.fill", #selector(playAll(_:)))
        case .shuffle: buttonItem(.shuffle, "Toolbar.Shuffle", "shuffle", #selector(shuffleAll(_:)))
        case .viewMode: viewModeItem()
        case .search: makeSearchItem()
        default: nil
        }
    }

    private func navigationItem() -> NSToolbarItem {
        let labels = [MacText.string("Toolbar.Back"), MacText.string("Toolbar.Forward")]
        let images = ["chevron.left", "chevron.right"].enumerated().map { index, symbolName in
            NSImage(systemSymbolName: symbolName, accessibilityDescription: labels[index]) ?? NSImage()
        }
        let group = NSToolbarItemGroup(
            itemIdentifier: .navigation,
            images: images,
            selectionMode: .momentary,
            labels: labels,
            target: self,
            action: #selector(changeNavigation(_:))
        )
        group.label = MacText.string("Toolbar.Navigation")
        group.isNavigational = true
        group.subitems.forEach { $0.isEnabled = false }
        return group
    }

    private func buttonItem(
        _ identifier: NSToolbarItem.Identifier,
        _ labelKey: String,
        _ symbolName: String,
        _ action: Selector
    ) -> NSToolbarItem {
        let label = MacText.string(labelKey)
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.target = self
        item.action = action
        return item
    }

    /// Sits above the sidebar. It hosts its own button, because a plain item there never sent its action.
    private func addFolderItem() -> NSToolbarItem {
        let label = MacText.string("Menu.AddFolder")
        let button = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: label) ?? NSImage(),
            target: self,
            action: #selector(addFolder(_:))
        )
        button.bezelStyle = .toolbar
        button.setAccessibilityLabel(label)
        let item = NSToolbarItem(itemIdentifier: .addFolder)
        item.view = button
        item.label = label
        item.toolTip = label
        return item
    }

    private func viewModeItem() -> NSToolbarItem {
        let labels = [MacText.string("ViewMode.Grid"), MacText.string("ViewMode.List")]
        let images = ["square.grid.2x2", "list.bullet"].enumerated().map { index, symbolName in
            NSImage(systemSymbolName: symbolName, accessibilityDescription: labels[index]) ?? NSImage()
        }
        let group = NSToolbarItemGroup(
            itemIdentifier: .viewMode,
            images: images,
            selectionMode: .selectOne,
            labels: labels,
            target: self,
            action: #selector(changeViewMode(_:))
        )
        group.label = MacText.string("Toolbar.ViewMode")
        group.selectedIndex = browser.viewMode == .grid ? 0 : 1
        return group
    }

    private func makeSearchItem() -> NSToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: .search)
        item.searchField.placeholderString = MacText.string("Toolbar.Search")
        item.searchField.target = self
        item.searchField.action = #selector(search(_:))
        return item
    }
}
