//
//  ScreenshotStage.swift
//  Melodee
//

#if DEBUG
import AppKit

/// Sets the scene for a Mac App Store screenshot, driven by `Assets/App Store/capture-mac.sh`,
/// which launches the app with these arguments and captures the window once it is ready:
///
///     -ScreenshotLibrary <path>       the sample library, shown as On My Mac in place of Documents
///     -ScreenshotFolder <path>        the folder to open, relative to the library
///     -ScreenshotViewMode grid|list   how the folder is shown
///     -ScreenshotPlay <name>          a file in the folder to play, from its place in the folder
///     -ScreenshotSelect <name>        a file in the folder to select
///     -ScreenshotPanel queue|tags     the queue, or the tag inspector for the selected file
///
/// Debug builds only: everything here is for the screenshots, and is never meant to run for anyone else.
@MainActor
enum ScreenshotStage {

    /// The window size the screenshots are taken at, drawn at twice its size on a Retina display.
    static let windowSize = NSSize(width: 1280, height: 800)

    private static let defaults = UserDefaults.standard

    static var isRequested: Bool { defaults.string(forKey: "ScreenshotLibrary") != nil }

    /// Points On My Mac at the sample library before the window lists it, so the
    /// screenshots never read the Mac's own Documents folder.
    static func prepare() {
        guard let library = defaults.string(forKey: "ScreenshotLibrary") else { return }
        MacServices.shared.fileManager.documentsDirectoryURL = URL(filePath: library, directoryHint: .isDirectory)
        Preferences.selectedLocation = LibraryLocation.local.identifier
        Preferences.repeatMode = .none
        if let viewMode = defaults.string(forKey: "ScreenshotViewMode").flatMap(BrowserViewMode.init(rawValue:)) {
            Preferences.browserViewMode = viewMode
        }
    }

    static func stage(_ windowController: MainWindowController) {
        guard let window = windowController.window,
              let library = MacServices.shared.fileManager.documentsDirectoryURL else { return }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let screen = NSScreen.screens.max { $0.backingScaleFactor < $1.backingScaleFactor } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            window.setFrame(NSRect(origin: NSPoint(x: visible.minX + 20, y: visible.maxY - windowSize.height - 20),
                                   size: windowSize), display: true)
        }

        let browser = windowController.browser
        // The browser shows On My Mac once the window appears, which would undo opening the folder before then.
        guard browser.location != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { stage(windowController) }
            return
        }
        if let folder = defaults.string(forKey: "ScreenshotFolder") {
            browser.open(folder: library.appending(path: folder, directoryHint: .isDirectory))
        }
        whenListed(browser) {
            if let name = defaults.string(forKey: "ScreenshotPlay"), let item = item(named: name, in: browser) {
                browser.open([item])
                // Partway in, so the progress bar shows the track playing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MacServices.shared.player.seek(to: 74)
                }
            }
            if let name = defaults.string(forKey: "ScreenshotSelect"),
               let index = browser.items.firstIndex(where: { $0.url.lastPathComponent == name }) {
                browser.select(IndexSet(integer: index))
                browser.selectionDidChange(to: IndexSet(integer: index))
            }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(browser.visibleView)
            // Once the window is in front and the album art has loaded.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                showPanel(in: windowController)
            }
        }
    }

    private static func showPanel(in windowController: MainWindowController) {
        let splitViewController = windowController.splitViewController
        switch defaults.string(forKey: "ScreenshotPanel") {
        case "queue":
            splitViewController.nowPlayingBarViewController.toggleQueue(nil)
        case "tags":
            splitViewController.editTags(of: windowController.browser.selectedItems.compactMap(\.file))
            // Out of the first field, so no text is selected in the inspector.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                windowController.window?.makeFirstResponder(windowController.browser.visibleView)
            }
        default:
            break
        }
    }

    private static func item(named name: String, in browser: BrowserViewController) -> BrowserItem? {
        browser.items.first { $0.url.lastPathComponent == name }
    }

    /// Runs once the browser has listed the folder it was asked to open.
    private static func whenListed(_ browser: BrowserViewController, then action: @escaping @MainActor () -> Void) {
        let folder = browser.folderURL?.standardizedFileURL.path(percentEncoded: false)
        let isListed = !browser.items.isEmpty && browser.items.allSatisfy {
            $0.url.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false) == folder
        }
        guard isListed else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { whenListed(browser, then: action) }
            return
        }
        action()
    }
}
#endif
