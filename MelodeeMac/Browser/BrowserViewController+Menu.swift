//
//  BrowserViewController+Menu.swift
//  Melodee
//

import AppKit

extension BrowserViewController: NSMenuDelegate {

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    /// Right-clicking outside the selection acts on the clicked item alone, as Finder does.
    var targetItems: [BrowserItem] {
        let clickedIndex = viewMode == .list ? tableView.clickedRow : clickedGridIndex()
        if clickedIndex >= 0, items.indices.contains(clickedIndex), !selectedIndexes.contains(clickedIndex) {
            return [items[clickedIndex]]
        }
        return selectedItems
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let targets = targetItems
        contextMenuTargets = targets
        guard !targets.isEmpty else { return }
        let playableTargets = targets.filter(\.isPlayable)
        func add(_ key: String, _ action: Selector) {
            let item = MainMenuBuilder.item(key, action: action)
            item.target = self
            menu.addItem(item)
        }
        if !playableTargets.isEmpty {
            add("Browser.Play", #selector(playTargets(_:)))
            add("Browser.PlayNext", #selector(playTargetsNext(_:)))
            add("Browser.PlayLast", #selector(playTargetsLast(_:)))
            menu.addItem(.separator())
        }
        // Track information can be edited when every file has tags Melodee can write
        if targets.allSatisfy({ $0.file?.isTaggableAudio() ?? false }) {
            let editItem = NSMenuItem(
                title: MacText.shared(targets.count == 1 ? "Shared.EditTag.Single" : "Shared.EditTag.All"),
                action: #selector(editTargetTags(_:)),
                keyEquivalent: ""
            )
            editItem.target = self
            menu.addItem(editItem)
            menu.addItem(.separator())
        }
        if targets.contains(where: { !$0.isPlayable }) {
            add("Browser.Open", #selector(openTargets(_:)))
            menu.addItem(.separator())
        }
        add("Browser.ShowInFinder", #selector(showInFinder(_:)))
        menu.addItem(.separator())
        add("Browser.MoveToTrash", #selector(moveToTrash(_:)))
    }

    @objc func playTargets(_ sender: Any?) {
        play(contextMenuTargets)
    }

    @objc func playTargetsNext(_ sender: Any?) {
        MacServices.shared.player.playNext(contextMenuTargets.filter(\.isPlayable).compactMap(\.file))
    }

    @objc func playTargetsLast(_ sender: Any?) {
        MacServices.shared.player.playLast(contextMenuTargets.filter(\.isPlayable).compactMap(\.file))
    }

    @objc func editTargetTags(_ sender: Any?) {
        onEditTags?(contextMenuTargets.compactMap(\.file))
    }

    @objc func openTargets(_ sender: Any?) {
        open(contextMenuTargets.filter { !$0.isPlayable })
    }

    @objc func showInFinder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting(contextMenuTargets.map(\.url))
    }

    @objc func moveToTrash(_ sender: Any?) {
        trash(contextMenuTargets)
    }

    /// Plays one file from its place in the folder, or several files on their own.
    func play(_ playedItems: [BrowserItem]) {
        if playedItems.count == 1 {
            open(playedItems)
        } else {
            MacServices.shared.player.play(playedItems.filter(\.isPlayable).compactMap(\.file))
        }
    }

    func trash(_ trashedItems: [BrowserItem]) {
        let urls = trashedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { [weak self] _, error in
            MainActor.assumeIsolated {
                if let error {
                    self?.presentError(error)
                }
                self?.reload()
            }
        }
    }

    private func clickedGridIndex() -> Int {
        guard let event = NSApp.currentEvent else { return -1 }
        let point = collectionView.convert(event.locationInWindow, from: nil)
        return collectionView.indexPathForItem(at: point)?.item ?? -1
    }
}
