@preconcurrency import AVFoundation
import Foundation

/// Converts video files between containers and extracts their audio, without lowering quality where possible.
///
/// - Container changes (MP4, MOV, M4V) copy the video and audio streams as-is.
/// - Audio extraction to M4A copies the audio stream as-is when it is AAC or ALAC. Other codecs (such as PCM in a
///   MOV) are encoded to AAC, which is lower fidelity and therefore allowed.
public enum Videoglot {

    /// Converts the video at `url` to `target` and returns the URL of the new file. The source is left untouched.
    ///
    /// - Parameters:
    ///   - outputURL: Where to write. Defaults to ``defaultOutputURL(for:target:)``.
    ///   - progress: Called with values from 0 to 1 as the export advances.
    @discardableResult
    public static func convert(
        _ url: URL,
        to target: VideoFormat,
        outputURL: URL? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let sourceExtension = url.pathExtension.lowercased()
        guard VideoFormat.targets(forPathExtension: sourceExtension).contains(target) else {
            throw VideoglotError.conversionNotAllowed(from: sourceExtension, to: target)
        }
        let outputURL = outputURL ?? defaultOutputURL(for: url, target: target)
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw VideoglotError.outputExists(outputURL)
        }

        let asset = AVURLAsset(url: url)
        let session = try await target.isAudioOnly
            ? audioExportSession(for: asset)
            : containerExportSession(for: asset, target: target)

        do {
            try await export(session, to: outputURL, as: target.fileType, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        return outputURL
    }

    /// Next to the source, with the target's extension.
    public static func defaultOutputURL(for url: URL, target: VideoFormat) -> URL {
        url.deletingPathExtension().appendingPathExtension(target.fileExtension)
    }

    private static func containerExportSession(for asset: AVURLAsset, target: VideoFormat) async throws
        -> AVAssetExportSession {
        guard await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough,
                                                       with: asset, outputFileType: target.fileType),
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else {
            throw VideoglotError.incompatibleStreams(target)
        }
        return session
    }

    private static func audioExportSession(for asset: AVURLAsset) async throws -> AVAssetExportSession {
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoglotError.noAudioTrack
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio,
                                                                 preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw VideoglotError.noAudioTrack
        }
        let timeRange = try await audioTrack.load(.timeRange)
        try compositionTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)

        // Copy AAC and ALAC as-is. Anything else (such as PCM, which passthrough would write into the M4A
        // unchanged) is encoded to AAC.
        let codec = try await audioTrack.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
        let preset = codec.map(passthroughAudioCodecs.contains) == true
            ? AVAssetExportPresetPassthrough
            : AVAssetExportPresetAppleM4A
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw VideoglotError.incompatibleStreams(.m4a)
        }
        // A composition has no metadata of its own; carry over the video's title, artwork and so on.
        session.metadata = try await asset.load(.metadata)
        return session
    }

    private static let passthroughAudioCodecs: Set<FourCharCode> = [
        kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatAppleLossless
    ]

    private static func export(
        _ session: AVAssetExportSession,
        to outputURL: URL,
        as fileType: AVFileType,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        progress?(0)
        // AVAssetExportSession's state stream is meant to be observed while the export runs.
        nonisolated(unsafe) let observedSession = session
        let monitor = Task {
            guard let progress else { return }
            for await state in observedSession.states(updateInterval: 0.1) {
                if case .exporting(let exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { monitor.cancel() }
        try await session.export(to: outputURL, as: fileType)
        progress?(1)
    }
}
