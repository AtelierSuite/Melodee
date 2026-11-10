import AVFoundation
import Foundation
import Prelude
import SFBAudioEngine

/// Guesses whether an audio file is a podcast episode or an audiobook rather than music,
/// so the previous and next buttons can skip within it instead of changing tracks.
enum SpokenWordDetector {

    /// Files at least this long, with no track number, are taken to be spoken word when nothing else says.
    static let minimumUntaggedDuration: TimeInterval = 20.0 * 60.0

    private static let audiobookExtensions: Set<String> = ["m4b", "aax"]
    private static let mp4Extensions: Set<String> = ["m4a", "m4b", "m4p", "mp4", "aax"]
    /// Tags that podcast apps and iTunes write: PCST, TCAT, TDES, TGID and WFED in ID3,
    /// and pcst, catg, desc, egid and purl in MP4.
    private static let podcastPropertyKeys: [String] = [
        "PODCASTURL", "PODCASTID", "PODCASTCATEGORY", "PODCASTDESC"
    ]
    private static let spokenWordGenres: [String] = [
        "podcast", "audiobook", "audio book", "spoken word", "speech"
    ]
    /// The MP4 media kind (`stik`) values for audiobooks and podcasts.
    private static let spokenWordMediaKinds: Set<Int> = [2, 21]
    private static let musicMediaKind = 1

    /// Reads the file's tags, which takes a moment, so it always runs away from the caller's actor.
    @concurrent static func isSpokenWord(atPath path: String) async -> Bool {
        let url = URL(filePath: path)
        let fileExtension = url.pathExtension.lowercased()
        if audiobookExtensions.contains(fileExtension) {
            return true
        }
        let properties = TagLibFile(path: path)?.properties ?? [:]
        if let verdict = verdict(fromTags: properties) {
            return verdict
        }
        if mp4Extensions.contains(fileExtension), let verdict = await verdict(fromMediaKindOf: url) {
            return verdict
        }
        // Long files that aren't numbered as part of an album are most likely talk
        let hasTrackNumber = !(properties["TRACKNUMBER"]?.allSatisfy(\.isEmpty) ?? true)
        guard !hasTrackNumber,
              let duration = try? AudioFile(readingPropertiesAndMetadataFrom: url).properties.duration else {
            return false
        }
        return duration >= minimumUntaggedDuration
    }

    /// True or false when the tags say so, or nil when they don't.
    private nonisolated static func verdict(fromTags properties: [String: [String]]) -> Bool? {
        // ID3's PCST frame has no value, while MP4's pcst atom is a flag
        if let podcastFlag = properties["PODCAST"] {
            if podcastFlag.isEmpty || podcastFlag.contains(where: { $0 != "0" }) {
                return true
            }
        }
        for key in podcastPropertyKeys where properties[key]?.contains(where: { !$0.isEmpty }) == true {
            return true
        }
        let genres = (properties["GENRE"] ?? []).map { $0.lowercased() }
        if genres.contains(where: { genre in spokenWordGenres.contains { genre.contains($0) } }) {
            return true
        }
        return nil
    }

    /// Reads the media kind iTunes and podcast apps store in MP4 files, which TagLib doesn't report.
    private nonisolated static func verdict(fromMediaKindOf url: URL) async -> Bool? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.loadMetadata(for: .iTunesMetadata),
              let item = AVMetadataItem.metadataItems(from: metadata,
                                                      withKey: "stik" as NSString,
                                                      keySpace: .iTunes).first,
              let mediaKind = try? await item.load(.numberValue)?.intValue else {
            return nil
        }
        if spokenWordMediaKinds.contains(mediaKind) {
            return true
        }
        return mediaKind == musicMediaKind ? false : nil
    }
}
