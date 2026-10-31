//
//  MainWindowController.swift
//  Melodee
//

import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {

    let splitViewController = MainSplitViewController()

    var browser: BrowserViewController {
        splitViewController.browserViewController
    }

    init() {
        let window = NSWindow(contentViewController: splitViewController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 1080, height: 680))
        window.minSize = NSSize(width: 780, height: 420)
        window.setFrameAutosaveName("MainWindow")
        super.init(window: window)
        window.delegate = self
        window.toolbar = makeToolbar()
        browser.onNavigate = { [weak self] in
            self?.browserDidNavigate()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func browserDidNavigate() {
        guard let window else { return }
        window.title = browser.folderTitle
        let location = browser.location
        window.subtitle = browser.canGoToEnclosingFolder ? location?.title ?? "" : ""
        navigationGroup?.subitems[0].isEnabled = browser.canGoBack
        navigationGroup?.subitems[1].isEnabled = browser.canGoForward
        if !browser.isSearching, let searchItem {
            searchItem.searchField.stringValue = ""
        }
    }

    /// Lists the folder again on coming back to the window, in case files changed in Finder meanwhile.
    func windowDidBecomeKey(_ notification: Notification) {
        if !browser.isSearching {
            browser.reload()
        }
    }

    // MARK: - Actions

    @objc func goBack(_ sender: Any?) {
        browser.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        browser.goForward()
    }

    @objc func goToEnclosingFolder(_ sender: Any?) {
        browser.goToEnclosingFolder()
    }

    @objc func changeNavigation(_ sender: NSToolbarItemGroup) {
        sender.selectedIndex == 0 ? browser.goBack() : browser.goForward()
    }

    @objc func showAsGrid(_ sender: Any?) {
        setViewMode(.grid)
    }

    @objc func showAsList(_ sender: Any?) {
        setViewMode(.list)
    }

    @objc func makeIconsBigger(_ sender: Any?) {
        browser.setGridIconSize(browser.gridIconSize + 16)
    }

    @objc func makeIconsSmaller(_ sender: Any?) {
        browser.setGridIconSize(browser.gridIconSize - 16)
    }

    @objc func changeViewMode(_ sender: NSToolbarItemGroup) {
        setViewMode(sender.selectedIndex == 0 ? .grid : .list)
    }

    private func setViewMode(_ mode: BrowserViewMode) {
        browser.viewMode = mode
        viewModeGroup?.selectedIndex = mode == .grid ? 0 : 1
    }

    @objc func playAll(_ sender: Any?) {
        browser.playAll(shuffled: false)
    }

    @objc func shuffleAll(_ sender: Any?) {
        browser.playAll(shuffled: true)
    }

    @objc func openSelection(_ sender: Any?) {
        browser.open(browser.selectedItems)
    }

    @objc func showSelectionInFinder(_ sender: Any?) {
        let urls = browser.selectedItems.map(\.url)
        if urls.isEmpty, let folderURL = browser.folderURL {
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    @objc func moveSelectionToTrash(_ sender: Any?) {
        browser.trash(browser.selectedItems)
    }

    @objc func showQueue(_ sender: Any?) {
        splitViewController.nowPlayingBarViewController.toggleQueue(sender)
    }

    @objc func performFind(_ sender: Any?) {
        guard let searchItem else { return }
        window?.makeFirstResponder(searchItem.searchField)
    }

    @objc func search(_ sender: NSSearchField) {
        browser.search(sender.stringValue)
    }

    var viewModeGroup: NSToolbarItemGroup? {
        window?.toolbar?.items.first { $0.itemIdentifier == .viewMode } as? NSToolbarItemGroup
    }

    var navigationGroup: NSToolbarItemGroup? {
        window?.toolbar?.items.first { $0.itemIdentifier == .navigation } as? NSToolbarItemGroup
    }

    var searchItem: NSSearchToolbarItem? {
        window?.toolbar?.items.first { $0.itemIdentifier == .search } as? NSSearchToolbarItem
    }
}

extension MainWindowController: NSMenuItemValidation {

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let hasSelection = !browser.selectedItems.isEmpty
        switch menuItem.action {
        case #selector(goBack(_:)):
            return browser.canGoBack
        case #selector(goForward(_:)):
            return browser.canGoForward
        case #selector(goToEnclosingFolder(_:)):
            return browser.canGoToEnclosingFolder
        case #selector(showAsGrid(_:)):
            menuItem.state = browser.viewMode == .grid ? .on : .off
        case #selector(showAsList(_:)):
            menuItem.state = browser.viewMode == .list ? .on : .off
        case #selector(makeIconsBigger(_:)):
            return browser.viewMode == .grid && browser.gridIconSize < BrowserGridItem.iconSizeRange.upperBound
        case #selector(makeIconsSmaller(_:)):
            return browser.viewMode == .grid && browser.gridIconSize > BrowserGridItem.iconSizeRange.lowerBound
        case #selector(playAll(_:)), #selector(shuffleAll(_:)):
            return browser.containsPlayableItems
        case #selector(openSelection(_:)), #selector(moveSelectionToTrash(_:)):
            return hasSelection
        case #selector(showSelectionInFinder(_:)):
            return hasSelection || browser.folderURL != nil
        default:
            break
        }
        return true
    }
}

extension MainWindowController: NSToolbarItemValidation {

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .playAll, .shuffle: browser.containsPlayableItems
        default: true
        }
    }
}
