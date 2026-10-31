//
//  SidebarViewController.swift
//  Melodee
//

import AppKit

final class SidebarViewController: NSViewController {

    let outlineView = NSOutlineView()
    private(set) var sections: [SidebarItem] = []
    var onSelect: ((LibraryLocation) -> Void)?
    private var locationsObserver: NSObjectProtocol?

    override func loadView() {
        let column = NSTableColumn(identifier: .sidebarColumn)
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .default
        outlineView.floatsGroupRows = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.menu = makeContextMenu()
        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        let addLabel = MacText.string("Menu.AddFolder")
        let addButton = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: addLabel) ?? NSImage(),
            target: nil,
            action: #selector(AppDelegate.addFolder(_:))
        )
        addButton.isBordered = false
        addButton.toolTip = addLabel
        addButton.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        addButton.contentTintColor = .secondaryLabelColor
        let container = NSView()
        for subview in [scrollView, addButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),
            addButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            addButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            addButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        view = container
        locationsObserver = NotificationCenter.default.addObserver(
            forName: .libraryLocationsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadLocations()
            }
        }
        reloadLocations()
    }

    var selectedLocation: LibraryLocation? {
        (outlineView.item(atRow: outlineView.selectedRow) as? SidebarItem)?.location
    }

    /// Rebuilds the sidebar, keeping the selected location if it's still there.
    func reloadLocations() {
        let selectedIdentifier = selectedLocation?.identifier ?? Preferences.selectedLocation
        var newSections = [SidebarItem(
            kind: .section(MacText.string("Sidebar.Library")),
            children: LibraryLocation.libraryLocations.map { SidebarItem(kind: .location($0)) }
        )]
        let folders = LibraryLocation.folderLocations
        if !folders.isEmpty {
            newSections.append(SidebarItem(
                kind: .section(MacText.string("Sidebar.Folders")),
                children: folders.map { SidebarItem(kind: .location($0)) }
            ))
        }
        sections = newSections
        outlineView.reloadData()
        sections.forEach { outlineView.expandItem($0) }
        select(identifier: selectedIdentifier)
    }

    func select(_ location: LibraryLocation) {
        select(identifier: location.identifier)
    }

    private func select(identifier: String?) {
        let items = sections.flatMap(\.children)
        let item = items.first { $0.location?.identifier == identifier } ?? items.first
        guard let item else { return }
        let row = outlineView.row(forItem: item)
        if row != outlineView.selectedRow {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    // MARK: - Context menu

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    private var clickedLocation: LibraryLocation? {
        (outlineView.item(atRow: outlineView.clickedRow) as? SidebarItem)?.location
    }

    @objc func showInFinder(_ sender: Any?) {
        guard let url = clickedLocation?.rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func removeFromSidebar(_ sender: Any?) {
        guard case .folder(let bookmark) = clickedLocation else { return }
        MacServices.shared.externalFolders.unlink(bookmark)
        NotificationCenter.default.post(name: .libraryLocationsDidChange, object: nil)
    }
}

extension SidebarViewController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let location = clickedLocation else { return }
        let showItem = MainMenuBuilder.item("Browser.ShowInFinder", action: #selector(showInFinder(_:)))
        showItem.target = self
        menu.addItem(showItem)
        if case .folder = location {
            menu.addItem(.separator())
            let removeItem = MainMenuBuilder.item("Sidebar.Remove", action: #selector(removeFromSidebar(_:)))
            removeItem.target = self
            menu.addItem(removeItem)
        }
    }
}

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? SidebarItem else { return sections.count }
        return item.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item = item as? SidebarItem else { return sections[index] }
        return item.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarItem)?.isSection ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarItem)?.isSection ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !((item as? SidebarItem)?.isSection ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? SidebarItem else { return nil }
        switch item.kind {
        case .section(let title):
            let cell = outlineView.makeView(withIdentifier: .sidebarHeader, owner: self) as? NSTableCellView
                ?? makeHeaderCell()
            cell.textField?.stringValue = title
            return cell
        case .location(let location):
            let cell = outlineView.makeView(withIdentifier: .sidebarCell, owner: self) as? SidebarCellView
                ?? SidebarCellView()
            cell.identifier = .sidebarCell
            cell.textField?.stringValue = location.title
            cell.imageView?.image = NSImage(systemSymbolName: location.symbolName, accessibilityDescription: nil)
            return cell
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let location = selectedLocation else { return }
        Preferences.selectedLocation = location.identifier
        onSelect?(location)
    }

    private func makeHeaderCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = .sidebarHeader
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}

extension NSUserInterfaceItemIdentifier {
    static let sidebarColumn = NSUserInterfaceItemIdentifier("SidebarColumn")
    static let sidebarCell = NSUserInterfaceItemIdentifier("SidebarCell")
    static let sidebarHeader = NSUserInterfaceItemIdentifier("SidebarHeader")
}
