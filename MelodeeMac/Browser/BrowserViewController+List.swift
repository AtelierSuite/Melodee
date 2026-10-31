//
//  BrowserViewController+List.swift
//  Melodee
//

import AppKit

extension NSUserInterfaceItemIdentifier {
    static let nameColumn = NSUserInterfaceItemIdentifier("name")
    static let kindColumn = NSUserInterfaceItemIdentifier("kind")
    static let sizeColumn = NSUserInterfaceItemIdentifier("size")
}

extension BrowserViewController: NSTableViewDataSource, NSTableViewDelegate {

    func configureList() {
        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.menu = makeContextMenu()
        tableView.target = self
        tableView.doubleAction = #selector(openClickedRow(_:))
        tableView.onOpen = { [weak self] indexes in
            self?.openItems(at: indexes)
        }
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        let columns: [(NSUserInterfaceItemIdentifier, String, CGFloat)] = [
            (.nameColumn, "Column.Name", 320),
            (.kindColumn, "Column.Kind", 160),
            (.sizeColumn, "Column.Size", 90)
        ]
        for (identifier, titleKey, width) in columns {
            let column = NSTableColumn(identifier: identifier)
            column.title = MacText.string(titleKey)
            column.width = width
            column.minWidth = 60
            column.sortDescriptorPrototype = NSSortDescriptor(key: identifier.rawValue, ascending: true)
            if identifier == .sizeColumn {
                column.headerCell.alignment = .right
            }
            tableView.addTableColumn(column)
        }
        tableView.sortDescriptors = [NSSortDescriptor(key: NSUserInterfaceItemIdentifier.nameColumn.rawValue,
                                                      ascending: true)]
    }

    /// Sorts by the list's sort column. Folders stay above files when sorting by name, as in the iPhone app.
    func sortItems() {
        guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
        let ascending = descriptor.ascending
        items.sort { lhs, rhs in
            let result: ComparisonResult
            switch key {
            case NSUserInterfaceItemIdentifier.kindColumn.rawValue:
                result = lhs.kindDescription.localizedStandardCompare(rhs.kindDescription)
            case NSUserInterfaceItemIdentifier.sizeColumn.rawValue:
                let lhsSize = lhs.size ?? -1
                let rhsSize = rhs.size ?? -1
                result = lhsSize == rhsSize ? .orderedSame : (lhsSize < rhsSize ? .orderedAscending : .orderedDescending)
            default:
                if lhs.isFolder != rhs.isFolder {
                    return lhs.isFolder
                }
                result = lhs.name.localizedStandardCompare(rhs.name)
            }
            if result == .orderedSame {
                return BrowserItem.isOrderedBefore(lhs, rhs)
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let item = items[row]
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: tableColumn.identifier)
        switch tableColumn.identifier {
        case .nameColumn:
            cell.textField?.stringValue = item.name
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
        case .kindColumn:
            cell.textField?.stringValue = item.kindDescription
        default:
            cell.textField?.stringValue = item.sizeDescription
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectionDidChange(to: tableView.selectedRowIndexes)
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        let selectedURLs = Set(selectedItems.map(\.url))
        sortItems()
        tableView.reloadData()
        collectionView.reloadData()
        select(IndexSet(items.indices.filter { selectedURLs.contains(items[$0].url) }))
    }

    @objc func openClickedRow(_ sender: Any?) {
        guard tableView.clickedRow >= 0 else { return }
        openItems(at: IndexSet(integer: tableView.clickedRow))
    }

    func openItems(at indexes: IndexSet) {
        open(indexes.filter { items.indices.contains($0) }.map { items[$0] })
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = identifier == .nameColumn ? .byTruncatingMiddle : .byTruncatingTail
        label.alignment = identifier == .sizeColumn ? .right : .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        var constraints = [
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ]
        if identifier == .nameColumn {
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            cell.imageView = icon
            constraints += [
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6)
            ]
        } else {
            constraints.append(label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
        }
        NSLayoutConstraint.activate(constraints)
        return cell
    }

    // MARK: - Drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        items[row].url as NSURL
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        // Files are always added to the folder being shown, so highlight the whole list
        tableView.setDropRow(-1, dropOperation: .on)
        return validateFileDrop(info)
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        acceptFileDrop(info)
    }
}
