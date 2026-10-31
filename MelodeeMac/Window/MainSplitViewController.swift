//
//  MainSplitViewController.swift
//  Melodee
//

import AppKit

final class MainSplitViewController: NSSplitViewController {

    let sidebarViewController = SidebarViewController()
    let browserViewController = BrowserViewController()
    let nowPlayingBarViewController = NowPlayingBarViewController()

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
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        splitView.autosaveName = "MainSplitView"
        sidebarViewController.onSelect = { [weak self] location in
            self?.browserViewController.show(location)
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
