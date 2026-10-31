//
//  QueueViewController.swift
//  Melodee
//

import AppKit

/// Lists the play queue. Double-clicking a track plays it, dragging reorders it, and Delete removes it.
final class QueueViewController: NSViewController {

    private let player = MacServices.shared.player
    private let tableView = QueueTableView()

    override func loadView() {
        let titleLabel = NSTextField(labelWithString: MacText.string("Queue.Title"))
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let clearButton = NSButton(title: MacText.string("Queue.Clear"), target: self, action: #selector(clearQueue(_:)))
        clearButton.controlSize = .small
        clearButton.bezelStyle = .push
        let header = NSStackView(views: [titleLabel, NSView(), clearButton])
        header.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 6, right: 12)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("QueueColumn"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(playClickedRow(_:))
        tableView.registerForDraggedTypes([.queueRows])
        // An insertion line, rather than a gap, shows exactly where the tracks will land
        tableView.draggingDestinationFeedbackStyle = .regular
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.onDelete = { [weak self] in
            self?.removeSelectedTracks()
        }
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let stack = NSStackView(views: [header, scrollView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.widthAnchor.constraint(equalToConstant: 320),
            stack.heightAnchor.constraint(equalToConstant: 380)
        ])
        view = stack
        reload()
    }

    func reload() {
        tableView.reloadData()
        if let currentIndex = player.currentIndex {
            tableView.scrollRowToVisible(currentIndex)
        }
    }

    @objc private func playClickedRow(_ sender: Any?) {
        guard tableView.clickedRow >= 0 else { return }
        player.play(at: tableView.clickedRow)
    }

    @objc private func clearQueue(_ sender: Any?) {
        player.clearQueue()
    }

    private func removeSelectedTracks() {
        player.removeFromQueue(at: tableView.selectedRowIndexes)
    }
}

extension QueueViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        player.queue.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("QueueCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? SidebarCellView ?? SidebarCellView()
        cell.identifier = identifier
        let file = player.queue[row]
        cell.textField?.stringValue = file.name
        let isCurrent = row == player.currentIndex
        cell.textField?.font = isCurrent
            ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            : .systemFont(ofSize: NSFont.systemFontSize)
        cell.imageView?.image = NSImage(
            systemSymbolName: isCurrent ? "speaker.wave.2.fill" : "music.note",
            accessibilityDescription: nil
        )
        cell.imageView?.contentTintColor = isCurrent ? .controlAccentColor : .secondaryLabelColor
        return cell
    }

    // MARK: - Reordering

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .queueRows)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === tableView else { return [] }
        if dropOperation == .on {
            tableView.setDropRow(row, dropOperation: .above)
        }
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let rows = info.draggingPasteboard.pasteboardItems?
            .compactMap { $0.string(forType: .queueRows).flatMap(Int.init) } ?? []
        guard !rows.isEmpty else { return false }
        player.moveQueueItems(at: IndexSet(rows), to: row)
        return true
    }
}

extension NSPasteboard.PasteboardType {
    static let queueRows = NSPasteboard.PasteboardType("com.tsubuzaki.Melodee.queue-rows")
}

final class QueueTableView: NSTableView {

    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == String(UnicodeScalar(NSDeleteCharacter)!) ||
            event.specialKey == .deleteForward {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}
