//
//  AppDelegate.swift
//  Melodee
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?
    private let player = MacServices.shared.player

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenuBuilder.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow(nil)
        }
        return true
    }

    /// Music keeps playing with the window closed, as it does in Music.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Windows

    @objc func showMainWindow(_ sender: Any?) {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
        }
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: AboutCredits.make()])
    }

    @objc func openGitHub(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/AtelierSuite/Melodee") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Adds folders to the sidebar, so Melodee can play music kept anywhere on the Mac.
    @objc func addFolder(_ sender: Any?) {
        showMainWindow(nil)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = MacText.string("AddFolder.Prompt")
        panel.message = MacText.string("AddFolder.Message")
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            let bookmarks = panel.urls.compactMap { MacServices.shared.externalFolders.addBookmark(for: $0) }
            NotificationCenter.default.post(name: .libraryLocationsDidChange, object: nil)
            if let bookmark = bookmarks.last {
                self?.mainWindowController?.splitViewController.sidebarViewController.select(.folder(bookmark))
            }
        }
        if let window = mainWindowController?.window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    // MARK: - Playback

    @objc func togglePlayPause(_ sender: Any?) {
        player.togglePlayPause()
    }

    @objc func nextTrack(_ sender: Any?) {
        player.skipToNextTrack()
    }

    @objc func previousTrack(_ sender: Any?) {
        player.backToPreviousTrack()
    }

    @objc func setRepeatMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let mode = RepeatMode(rawValue: rawValue) else {
            return
        }
        player.repeatMode = mode
    }

    @objc func clearQueue(_ sender: Any?) {
        player.clearQueue()
    }
}

extension AppDelegate: NSMenuItemValidation {

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePlayPause(_:)):
            menuItem.title = MacText.string(player.isPlaying ? "NowPlaying.Pause" : "NowPlaying.Play")
            // Space types a space while editing text, so leave it to the text field
            if NSApp.keyWindow?.firstResponder is NSText {
                return false
            }
            return player.canPlay
        case #selector(nextTrack(_:)):
            return player.canGoToNextTrack
        case #selector(previousTrack(_:)):
            return player.canGoToPreviousTrack
        case #selector(setRepeatMode(_:)):
            menuItem.state = (menuItem.representedObject as? String) == player.repeatMode.rawValue ? .on : .off
        case #selector(clearQueue(_:)):
            return player.canPlay
        default:
            break
        }
        return true
    }
}
