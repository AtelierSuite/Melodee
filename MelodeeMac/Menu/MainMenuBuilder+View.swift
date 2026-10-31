//
//  MainMenuBuilder+View.swift
//  Melodee
//

import AppKit

extension MainMenuBuilder {

    static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: MacText.string("Menu.View"))
        menu.addItem(item("ViewMode.Grid", action: #selector(MainWindowController.showAsGrid(_:)), keyEquivalent: "1"))
        menu.addItem(item("ViewMode.List", action: #selector(MainWindowController.showAsList(_:)), keyEquivalent: "2"))
        menu.addItem(.separator())
        menu.addItem(item(
            "Menu.ShowSidebar",
            action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s",
            modifiers: [.command, .control]
        ))
        menu.addItem(item(
            "Menu.ShowQueue",
            action: #selector(MainWindowController.showQueue(_:)),
            keyEquivalent: "u",
            modifiers: [.command, .option]
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            "Menu.EnterFullScreen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f",
            modifiers: [.command, .control]
        ))
        return menu
    }

    static func goMenu() -> NSMenu {
        let menu = NSMenu(title: MacText.string("Menu.Go"))
        menu.addItem(item("Toolbar.Back", action: #selector(MainWindowController.goBack(_:)), keyEquivalent: "["))
        menu.addItem(item("Toolbar.Forward", action: #selector(MainWindowController.goForward(_:)), keyEquivalent: "]"))
        menu.addItem(item(
            "Menu.EnclosingFolder",
            action: #selector(MainWindowController.goToEnclosingFolder(_:)),
            keyEquivalent: arrowKey(NSUpArrowFunctionKey)
        ))
        return menu
    }
}
