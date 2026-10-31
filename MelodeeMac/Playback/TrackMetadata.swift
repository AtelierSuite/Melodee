//
//  TrackMetadata.swift
//  Melodee
//

import AppKit
import SFBAudioEngine

/// The tags shown for the file that's playing, falling back to the file and folder names.
struct TrackMetadata {

    var title: String
    var artist: String?
    var album: String?
    var artwork: NSImage?

    init(file: FSFile) {
        let audioFile = file.isTaggableAudio() ? AudioFile.read(for: file) : nil
        let title = audioFile?.title ?? ""
        self.title = title.isEmpty ? file.name : title
        let artist = audioFile?.artist ?? ""
        self.artist = artist.isEmpty ? nil : artist
        let album = audioFile?.albumTitle ?? ""
        self.album = album.isEmpty ? file.containingFolderName() : album
        self.artwork = audioFile?.coverArtData.flatMap(NSImage.init(data:))
    }

    /// The artist and album on one line, as Music shows them.
    var subtitle: String {
        [artist, album].compactMap { $0 }.joined(separator: " — ")
    }
}
