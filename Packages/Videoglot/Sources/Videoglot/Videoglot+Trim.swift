@preconcurrency import AVFoundation
import Foundation

extension Videoglot {

    /// Extensions of videos that can be trimmed.
    public static let trimmableExtensions: Set<String> = ["mp4", "m4v", "mov"]

    /// Writes the part of the video at `url` between `start` and `end` (in seconds) to `outputURL`, in the same
    /// container. Streams are copied as-is, so quality never changes. The end is cut at the requested frame; the
    /// start may move back to the previous keyframe, since a video can only begin on one without re-encoding.
    public static func trim(
        _ url: URL,
        from start: TimeInterval,
        to end: TimeInterval,
        outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let sourceExtension = url.pathExtension.lowercased()
        guard trimmableExtensions.contains(sourceExtension),
              let format = VideoFormat(rawValue: sourceExtension) else {
            throw VideoglotError.trimNotSupported(sourceExtension)
        }
        guard start >= 0, end > start else { throw VideoglotError.invalidTrimRange }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw VideoglotError.outputExists(outputURL)
        }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration)
        let timescale = max(duration.timescale, 600)
        let endTime = CMTimeMinimum(CMTime(seconds: end, preferredTimescale: timescale), duration)
        let startTime = CMTime(seconds: start, preferredTimescale: timescale)
        guard endTime > startTime else { throw VideoglotError.invalidTrimRange }

        guard await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough,
                                                       with: asset, outputFileType: format.fileType),
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else {
            throw VideoglotError.incompatibleStreams(format)
        }
        session.timeRange = CMTimeRange(start: startTime, end: endTime)
        session.metadata = try await asset.load(.metadata)

        do {
            try await export(session, to: outputURL, as: format.fileType, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
