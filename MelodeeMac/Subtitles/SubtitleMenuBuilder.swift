//
//  SubtitleMenuBuilder.swift
//  Melodee
//

import AppKit

/// Populates an AppKit `NSMenu` with Off, all available subtitle & lyrics tracks for the playing video,
/// and an item to open the Lyrics & Subtitle Editor.
@MainActor
enum SubtitleMenuBuilder {

    static func populate(_ menu: NSMenu, player: MacPlayer, target: AnyObject?) {
        menu.removeAllItems()
        let controller = player.subtitleController

        let offItem = NSMenuItem(
            title: MacText.shared("Subtitles.Off"),
            action: #selector(AppDelegate.selectSubtitleTrack(_:)),
            keyEquivalent: ""
        )
        offItem.target = target
        offItem.representedObject = nil
        offItem.state = controller.selectedTrackID == nil ? .on : .off
        offItem.isEnabled = player.isPlayingVideo
        menu.addItem(offItem)

        let subtitles = controller.availableTracks.filter { !$0.isLyrics }
        let lyrics = controller.availableTracks.filter(\.isLyrics)

        if !subtitles.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: MacText.shared("Subtitles.Section.Subtitles")))
            for track in subtitles {
                menu.addItem(trackItem(track, selectedID: controller.selectedTrackID, target: target))
            }
        }

        if !lyrics.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: MacText.shared("Subtitles.Section.Lyrics")))
            for track in lyrics {
                menu.addItem(trackItem(track, selectedID: controller.selectedTrackID, target: target))
            }
        }

        if player.isPlayingVideo {
            menu.addItem(.separator())
            let editItem = NSMenuItem(
                title: MacText.shared("SubtitleEditor.Open"),
                action: #selector(AppDelegate.editCurrentVideoSubtitles(_:)),
                keyEquivalent: ""
            )
            editItem.target = target
            menu.addItem(editItem)
        }
    }

    private static func trackItem(
        _ track: VideoSubtitleTrack,
        selectedID: String?,
        target: AnyObject?
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: track.title,
            action: #selector(AppDelegate.selectSubtitleTrack(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = track.id
        item.state = selectedID == track.id ? .on : .off
        return item
    }
}
