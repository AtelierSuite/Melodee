//
//  MainSplitViewController.swift
//  Melodee
//

import AppKit
import SwiftUI

final class MainSplitViewController: NSSplitViewController {

    let sidebarViewController = SidebarViewController()
    let browserViewController = BrowserViewController()
    let nowPlayingBarViewController = NowPlayingBarViewController()
    let inspectorModel = TagInspectorModel()
    private var inspectorItem: NSSplitViewItem?
    private var inspectorHost: NSViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        let contentItem = NSSplitViewItem(viewController: ContentViewController(
            browser: browserViewController,
            nowPlayingBar: nowPlayingBarViewController
        ))
        contentItem.minimumThickness = 560
        // The tag inspector only opens from Edit Track Information, and closes once the tags are saved
        let inspectorHost = NSHostingController(rootView: TagInspectorView(model: inspectorModel))
        inspectorHost.sizingOptions = []
        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorHost)
        inspectorItem.minimumThickness = 300
        inspectorItem.maximumThickness = 440
        inspectorItem.canCollapse = true
        inspectorItem.isCollapsed = true
        self.inspectorItem = inspectorItem
        self.inspectorHost = inspectorHost
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        addSplitViewItem(inspectorItem)
        splitView.autosaveName = "MainSplitView"
        sidebarViewController.onSelect = { [weak self] location in
            self?.browserViewController.show(location)
        }
        browserViewController.onEditTags = { [weak self] files in
            self?.editTags(of: files)
        }
        inspectorModel.onSave = { [weak self] files, closesInspector in
            self?.tagsDidChange(in: files)
            if closesInspector {
                self?.closeInspector()
            }
        }
        inspectorModel.onCancel = { [weak self] in
            self?.closeInspector()
        }
        inspectorModel.onDirtyChange = { [weak self] isDirty in
            self?.view.window?.isDocumentEdited = isDirty
        }
    }

    func editTags(of files: [FSFile]) {
        guard !files.isEmpty else { return }
        inspectorModel.edit(files)
        inspectorItem?.animator().isCollapsed = false
        if let inspectorView = inspectorHost?.view {
            view.window?.makeFirstResponder(inspectorView)
        }
    }

    func closeInspector() {
        inspectorItem?.animator().isCollapsed = true
        view.window?.makeFirstResponder(browserViewController.visibleView)
        inspectorModel.edit([])
        view.window?.isDocumentEdited = false
    }

    /// Shows the new album art in the grid and the new tags in the Now Playing bar.
    private func tagsDidChange(in files: [FSFile]) {
        let paths = Set(files.map(\.path))
        ThumbnailCache.shared.removeThumbnails(forPaths: paths)
        browserViewController.reloadItems(atPaths: paths)
        MacServices.shared.player.refreshMetadata(forPaths: paths)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // The split view restores its last layout, which could leave the inspector open with nothing to edit
        if inspectorModel.files.isEmpty {
            inspectorItem?.isCollapsed = true
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if browserViewController.location == nil, let location = sidebarViewController.selectedLocation {
            browserViewController.show(location)
            view.window?.makeFirstResponder(browserViewController.visibleView)
        }
    }
}

/// The browser with the Now Playing bar beneath it.
private final class ContentViewController: NSViewController {

    private let browser: BrowserViewController
    private let nowPlayingBar: NowPlayingBarViewController

    init(browser: BrowserViewController, nowPlayingBar: NowPlayingBarViewController) {
        self.browser = browser
        self.nowPlayingBar = nowPlayingBar
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView()
        addChild(browser)
        addChild(nowPlayingBar)
        for subview in [browser.view, nowPlayingBar.view] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        // The bar floats over the bottom of the browser, which scrolls beneath it
        NSLayoutConstraint.activate([
            browser.view.topAnchor.constraint(equalTo: container.topAnchor),
            browser.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            browser.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            browser.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            nowPlayingBar.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.barMargin),
            nowPlayingBar.view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.barMargin),
            nowPlayingBar.view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.barMargin)
        ])
        view = container
    }

    private static let barMargin: CGFloat = 12

    /// Lets the browser's last row scroll clear of the bar.
    override func viewDidLayout() {
        super.viewDidLayout()
        let inset = nowPlayingBar.view.frame.height + Self.barMargin * 2
        if browser.view.additionalSafeAreaInsets.bottom != inset {
            browser.view.additionalSafeAreaInsets.bottom = inset
        }
    }
}
