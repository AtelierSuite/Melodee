//
//  MainMenuBuilder+File.swift
//  Melodee
//

import AppKit

extension MainMenuBuilder {

    static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: MacText.string("Menu.File"))
        menu.addItem(item("Menu.AddFolder", action: #selector(AppDelegate.addFolder(_:)), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(item(
            "Menu.Open",
            action: #selector(MainWindowController.openSelection(_:)),
            keyEquivalent: arrowKey(NSDownArrowFunctionKey)
        ))
        menu.addItem(item(
            "Browser.ShowInFinder",
            action: #selector(MainWindowController.showSelectionInFinder(_:)),
            keyEquivalent: "r"
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            "Browser.MoveToTrash",
            action: #selector(MainWindowController.moveSelectionToTrash(_:)),
            keyEquivalent: "\u{8}"
        ))
        menu.addItem(.separator())
        menu.addItem(item("Menu.Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        return menu
    }
}
