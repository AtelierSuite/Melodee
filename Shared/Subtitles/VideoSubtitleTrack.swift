import Foundation
import Videoglot

/// Where a selectable subtitle or lyrics track for a video comes from.
enum VideoSubtitleSource: Hashable, Sendable {
    /// An embedded subtitle track exposed by AVFoundation (`AVMediaSelectionGroup` `.legible`).
    case avMediaOption(index: Int)
    /// An embedded text/subtitle track exposed by VLCKit (e.g. MKV, ASS, SRT, PGS inside container).
    case vlcTextTrack(trackID: String)
    /// A sidecar subtitle or synced-lyrics file beside the video (`.srt`, `.vtt`, `.ass`, `.ssa`, `.lrc`).
    case sidecar(SidecarTimedTextFile)
    /// Lyrics embedded in the video file's metadata (`©lyr` / `LYRICS` / `USLT`).
    case embeddedLyrics(isSynced: Bool)
}

/// A selectable subtitle or lyrics track for video playback.
struct VideoSubtitleTrack: Identifiable, Hashable, Sendable {

    let id: String
    let title: String
    let languageCode: String?
    let isLyrics: Bool
    let source: VideoSubtitleSource

    /// Whether this track is rendered natively by AVPlayer or VLCKit (rather than Melodee's overlay).
    var isNativeEngineTrack: Bool {
        switch source {
        case .avMediaOption, .vlcTextTrack: true
        case .sidecar, .embeddedLyrics: false
        }
    }
}
