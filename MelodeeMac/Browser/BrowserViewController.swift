//
//  BrowserViewController.swift
//  Melodee
//

import AppKit

final class BrowserViewController: NSViewController {

    let collectionView = BrowserCollectionView()
    let tableView = BrowserTableView()
    private let gridScrollView = NSScrollView()
    private let listScrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var loadTask: Task<Void, Never>?

    private(set) var location: LibraryLocation?
    private(set) var folderURL: URL?
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var folderItems: [BrowserItem] = []
    private(set) var searchQuery: String = ""
    /// The items a context menu acts on, captured when it opens.
    var contextMenuTargets: [BrowserItem] = []
    /// What the browser shows: the folder's contents, or search results while searching.
    var items: [BrowserItem] = []
    /// Called whenever the folder, history or search changes, so the window can update its title and toolbar.
    var onNavigate: (() -> Void)?

    var viewMode: BrowserViewMode = Preferences.browserViewMode {
        didSet {
            Preferences.browserViewMode = viewMode
            updateVisibleView()
        }
    }

    var gridIconSize: CGFloat = Preferences.gridIconSize {
        didSet { Preferences.gridIconSize = gridIconSize }
    }
    var pinchStartIconSize: CGFloat = BrowserGridItem.defaultIconSize

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var isSearching: Bool { !searchQuery.isEmpty }

    var folderTitle: String {
        guard let folderURL, let location else { return location?.title ?? "" }
        return folderURL.standardizedFileURL == location.rootURL?.standardizedFileURL
            ? location.title
            : folderURL.lastPathComponent
    }

    override func loadView() {
        let container = NSView()
        configureGrid()
        configureList()
        gridScrollView.documentView = collectionView
        gridScrollView.addGestureRecognizer(NSMagnificationGestureRecognizer(
            target: self, action: #selector(handlePinch(_:))
        ))
        listScrollView.documentView = tableView
        emptyLabel.font = .preferredFont(forTextStyle: .title3)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        for subview in [gridScrollView, listScrollView, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        for scrollView in [gridScrollView, listScrollView] {
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: container.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
        }
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -48)
        ])
        view = container
        updateVisibleView()
    }

    // MARK: - Navigation

    func show(_ location: LibraryLocation) {
        self.location = location
        backStack.removeAll()
        forwardStack.removeAll()
        guard let rootURL = location.rootURL else {
            folderURL = nil
            showItems([])
            emptyLabel.stringValue = MacText.string("Browser.Unavailable")
            onNavigate?()
            return
        }
        open(folder: rootURL, recordingHistory: false)
    }

    func open(folder url: URL, recordingHistory: Bool = true) {
        if recordingHistory, let folderURL {
            backStack.append(folderURL)
            forwardStack.removeAll()
        }
        folderURL = url
        searchQuery = ""
        reload()
    }

    func goBack() {
        guard let previousURL = backStack.popLast() else { return }
        if let folderURL {
            forwardStack.append(folderURL)
        }
        folderURL = previousURL
        searchQuery = ""
        reload()
    }

    func goForward() {
        guard let nextURL = forwardStack.popLast() else { return }
        if let folderURL {
            backStack.append(folderURL)
        }
        folderURL = nextURL
        searchQuery = ""
        reload()
    }

    /// Opens the folder that contains the current one, without going above the sidebar location.
    func goToEnclosingFolder() {
        guard let folderURL, let rootURL = location?.rootURL,
              folderURL.standardizedFileURL != rootURL.standardizedFileURL else { return }
        open(folder: folderURL.deletingLastPathComponent())
    }

    var canGoToEnclosingFolder: Bool {
        guard let folderURL, let rootURL = location?.rootURL else { return false }
        return folderURL.standardizedFileURL != rootURL.standardizedFileURL
    }

    /// Lists the current folder again, keeping the selected items selected.
    func reload() {
        guard let folderURL else { return }
        let selectedURLs = Set(selectedItems.map(\.url))
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let newItems = await BrowserItem.items(in: folderURL)
            guard !Task.isCancelled, let self else { return }
            folderItems = newItems
            if isSearching {
                search(searchQuery)
            } else {
                showItems(newItems, selecting: selectedURLs)
            }
        }
        onNavigate?()
    }

    func search(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearching, let folderURL else {
            loadTask?.cancel()
            showItems(folderItems)
            onNavigate?()
            return
        }
        let searchQuery = searchQuery
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let results = await BrowserItem.search(searchQuery, in: folderURL)
            guard !Task.isCancelled, let self else { return }
            showItems(results)
        }
        onNavigate?()
    }

    private func showItems(_ newItems: [BrowserItem], selecting selectedURLs: Set<URL> = []) {
        items = newItems
        sortItems()
        collectionView.reloadData()
        tableView.reloadData()
        let selection = IndexSet(items.indices.filter { selectedURLs.contains(items[$0].url) })
        select(selection)
        emptyLabel.stringValue = MacText.string(isSearching ? "Browser.NoResults" : "Browser.Empty")
        emptyLabel.isHidden = !items.isEmpty
    }

    // MARK: - Selection

    var selectedIndexes: IndexSet {
        switch viewMode {
        case .grid: IndexSet(collectionView.selectionIndexPaths.map(\.item))
        case .list: tableView.selectedRowIndexes
        }
    }

    var selectedItems: [BrowserItem] {
        selectedIndexes.filter { items.indices.contains($0) }.map { items[$0] }
    }

    func select(_ indexes: IndexSet) {
        collectionView.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) })
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    /// Keeps the same items selected in both views, so switching views keeps the selection.
    func selectionDidChange(to indexes: IndexSet) {
        if viewMode == .grid {
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        } else {
            collectionView.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) })
        }
    }

    private func updateVisibleView() {
        // Hiding the focused view hands focus elsewhere, so check where it is first
        let window = view.window
        let isBrowserFocused = window?.firstResponder === collectionView || window?.firstResponder === tableView
        gridScrollView.isHidden = viewMode != .grid
        listScrollView.isHidden = viewMode != .list
        if isBrowserFocused {
            window?.makeFirstResponder(visibleView)
        }
    }

    var visibleView: NSView {
        viewMode == .grid ? collectionView : tableView
    }

    // MARK: - Opening

    /// Opens folders in the browser, plays audio files from that point in the list,
    /// and opens everything else in the app the Mac uses for it.
    func open(_ openedItems: [BrowserItem]) {
        guard let first = openedItems.first else { return }
        if openedItems.count == 1, first.isFolder {
            open(folder: first.url)
            return
        }
        let playable = openedItems.filter(\.isPlayable)
        if playable.count == 1, let file = playable.first?.file {
            let folderFiles = items.filter(\.isPlayable).compactMap(\.file)
            let index = folderFiles.firstIndex { $0.path == file.path } ?? 0
            MacServices.shared.player.play(folderFiles, startingAt: index)
        } else if !playable.isEmpty {
            MacServices.shared.player.play(playable.compactMap(\.file))
        }
        let others = openedItems.filter { !$0.isPlayable && !$0.isFolder }
        others.forEach { NSWorkspace.shared.open($0.url) }
    }

    /// Plays every audio file in the folder, in order or shuffled.
    func playAll(shuffled: Bool) {
        var files = items.filter(\.isPlayable).compactMap(\.file)
        if shuffled {
            files.shuffle()
        }
        MacServices.shared.player.play(files)
    }

    var containsPlayableItems: Bool {
        items.contains(where: \.isPlayable)
    }
}
