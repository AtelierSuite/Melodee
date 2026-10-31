//
//  MainMenuBuilder+Controls.swift
//  Melodee
//

import AppKit

extension MainMenuBuilder {

    static func controlsMenu() -> NSMenu {
        let menu = NSMenu(title: MacText.string("Menu.Controls"))
        menu.addItem(item("NowPlaying.Play", action: #selector(AppDelegate.togglePlayPause(_:)), keyEquivalent: " ", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(item(
            "NowPlaying.Next",
            action: #selector(AppDelegate.nextTrack(_:)),
            keyEquivalent: arrowKey(NSRightArrowFunctionKey)
        ))
        menu.addItem(item(
            "NowPlaying.Previous",
            action: #selector(AppDelegate.previousTrack(_:)),
            keyEquivalent: arrowKey(NSLeftArrowFunctionKey)
        ))
        menu.addItem(.separator())
        menu.addItem(item("Toolbar.PlayAll", action: #selector(MainWindowController.playAll(_:))))
        menu.addItem(item("Toolbar.Shuffle", action: #selector(MainWindowController.shuffleAll(_:))))
        menu.addItem(.separator())
        let repeatItem = item("NowPlaying.Repeat", action: nil)
        let repeatMenu = NSMenu()
        let modes: [(String, RepeatMode)] = [("Repeat.Off", .none), ("Repeat.All", .all), ("Repeat.One", .single)]
        for (key, mode) in modes {
            let modeItem = item(key, action: #selector(AppDelegate.setRepeatMode(_:)))
            modeItem.representedObject = mode.rawValue
            repeatMenu.addItem(modeItem)
        }
        repeatItem.submenu = repeatMenu
        menu.addItem(repeatItem)
        menu.addItem(.separator())
        menu.addItem(item("Queue.Clear", action: #selector(AppDelegate.clearQueue(_:))))
        return menu
    }
}
