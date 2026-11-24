@preconcurrency import AVFoundation
import Foundation
import Videoglot

/// Plays a subtitle file or synced lyrics as a real subtitle track, so AVPlayer draws it everywhere,
/// including in Picture in Picture and on AirPlay.
struct VideoSubtitleComposition: @unchecked Sendable {

    let asset: AVAsset
    /// The subtitle-only file the composition reads from, which must outlive it.
    let subtitleFileURL: URL

    private static let directoryURL = URL.cachesDirectory.appending(path: "SubtitleTracks", directoryHint: .isDirectory)

    /// Builds the video's own video and audio with `document` as its only subtitle track.
    /// A composition offers no subtitle options once it holds more than one subtitle track,
    /// so the video's own subtitle tracks are left out.
    static func make(videoURL: URL, document: TimedTextDocument) async throws -> VideoSubtitleComposition {
        let videoAsset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await videoAsset.load(.duration)
        let tracks = try await videoAsset.load(.tracks)
        let videoTrack = tracks.first { $0.mediaType == .video }
        let videoSize = (try? await videoTrack?.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let subtitleFileURL = directoryURL.appending(path: "\(UUID().uuidString).mp4")
        try await Videoglot.writeSubtitleTrackFile(
            document,
            duration: duration.isNumeric ? duration.seconds : 0,
            videoSize: videoSize,
            to: subtitleFileURL
        )

        do {
            let subtitleAsset = AVURLAsset(url: subtitleFileURL)
            let composition = AVMutableComposition()
            let fullRange = CMTimeRange(start: .zero, duration: duration)
            for track in tracks where track.mediaType == .video || track.mediaType == .audio {
                guard try await track.load(.isEnabled),
                      let compositionTrack = composition.addMutableTrack(
                        withMediaType: track.mediaType,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                      ) else { continue }
                try compositionTrack.insertTimeRange(fullRange, of: track, at: .zero)
                compositionTrack.preferredTransform = try await track.load(.preferredTransform)
                compositionTrack.languageCode = try? await track.load(.languageCode)
                compositionTrack.extendedLanguageTag = try? await track.load(.extendedLanguageTag)
            }
            for track in try await subtitleAsset.load(.tracks) {
                let timeRange = try await track.load(.timeRange)
                guard let compositionTrack = composition.addMutableTrack(
                    withMediaType: track.mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { continue }
                try compositionTrack.insertTimeRange(timeRange, of: track, at: timeRange.start)
                compositionTrack.languageCode = try? await track.load(.languageCode)
                compositionTrack.extendedLanguageTag = try? await track.load(.extendedLanguageTag)
            }
            return VideoSubtitleComposition(asset: composition, subtitleFileURL: subtitleFileURL)
        } catch {
            try? FileManager.default.removeItem(at: subtitleFileURL)
            throw error
        }
    }

    /// Removes subtitle files left over from earlier launches, keeping the ones still in use.
    static func removeStaleFiles(keeping fileURLs: Set<URL> = []) {
        let keptPaths = Set(fileURLs.map(\.standardizedFileURL.path))
        let contents = (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        for url in contents where !keptPaths.contains(url.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
