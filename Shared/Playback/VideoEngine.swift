import Foundation

/// Which player plays video files.
enum VideoEngine: String, CaseIterable, Identifiable {
    /// Apple's AVPlayer, with the system playback controls, Picture in Picture and AirPlay.
    case standard = "default"
    /// VLCKit, which plays more formats and deinterlaces interlaced video.
    case extended

    static let storageKey = "VideoEngine"

    var id: String { rawValue }

    static var current: VideoEngine {
        UserDefaults.standard.string(forKey: storageKey).flatMap(VideoEngine.init(rawValue:)) ?? .standard
    }
}
