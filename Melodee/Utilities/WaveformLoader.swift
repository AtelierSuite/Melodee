@preconcurrency import AVFoundation
import Accelerate
import Foundation
import SFBAudioEngine

/// The loudness of a file over time, for drawing.
struct Waveform: Sendable, Equatable {
    /// Peak levels from 0 to 1, evenly spaced across the file. Scaled so the loudest peak is 1.
    var peaks: [Float]
    var duration: TimeInterval
}

/// Reads a file's audio and reduces it to a ``Waveform``.
enum WaveformLoader {

    static let defaultBucketCount = 1200

    private final class CachedWaveform {
        let waveform: Waveform
        init(_ waveform: Waveform) { self.waveform = waveform }
    }

    nonisolated(unsafe) private static let cache = NSCache<NSString, CachedWaveform>()

    /// Loads the waveform of the audio file, or of the video's audio track, at `url`.
    static func load(url: URL, isVideo: Bool, bucketCount: Int = defaultBucketCount) async throws -> Waveform {
        let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let key = "\(url.path(percentEncoded: false))|\(modificationDate)|\(bucketCount)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.waveform
        }
        let waveform = try await Task.detached(priority: .userInitiated) {
            if isVideo {
                return try await videoWaveform(url: url, bucketCount: bucketCount)
            }
            return try audioWaveform(url: url, bucketCount: bucketCount)
        }.value
        cache.setObject(CachedWaveform(waveform), forKey: key)
        return waveform
    }

    // MARK: Audio

    private static func audioWaveform(url: URL, bucketCount: Int) throws -> Waveform {
        let decoder = try AudioDecoder(url: url)
        try decoder.open()
        defer { try? decoder.close() }

        let sourceFormat = decoder.processingFormat
        guard let floatFormat = AVAudioFormat(standardFormatWithSampleRate: sourceFormat.sampleRate,
                                              channels: sourceFormat.channelCount) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let capacity: AVAudioFrameCount = 16384
        guard let decodeBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: capacity),
              let floatBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: capacity) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let converter = sourceFormat == floatFormat ? nil : AVAudioConverter(from: sourceFormat, to: floatFormat)

        var accumulator = PeakAccumulator(totalFrames: max(decoder.length, 1), bucketCount: bucketCount)
        while true {
            try Task.checkCancellation()
            try decoder.decode(into: decodeBuffer, length: capacity)
            guard decodeBuffer.frameLength > 0 else { break }
            let buffer: AVAudioPCMBuffer
            if let converter {
                floatBuffer.frameLength = 0
                try converter.convert(to: floatBuffer, from: decodeBuffer)
                buffer = floatBuffer
            } else {
                buffer = decodeBuffer
            }
            guard let channels = buffer.floatChannelData else { break }
            let pointers = (0..<Int(buffer.format.channelCount)).map { UnsafePointer(channels[$0]) }
            accumulator.add(channels: pointers, stride: 1, frameCount: Int(buffer.frameLength))
        }
        let duration = Double(decoder.length) / sourceFormat.sampleRate
        return Waveform(peaks: accumulator.normalizedPeaks(), duration: duration)
    }

    // MARK: Video

    private static func videoWaveform(url: URL, bucketCount: Int) async throws -> Waveform {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            // A silent video still gets a flat waveform, so its length can be trimmed
            return Waveform(peaks: Array(repeating: 0, count: bucketCount), duration: duration)
        }
        let sampleRate = try await track.load(.formatDescriptions).first
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate } ?? 44100

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }

        let totalFrames = AVAudioFramePosition(max(duration * sampleRate, 1))
        var accumulator = PeakAccumulator(totalFrames: totalFrames, bucketCount: bucketCount)
        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
                  let description = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
                continue
            }
            let channelCount = Int(format.mChannelsPerFrame)
            let byteCount = CMBlockBufferGetDataLength(blockBuffer)
            var samples = [Float](repeating: 0, count: byteCount / MemoryLayout<Float>.size)
            samples.withUnsafeMutableBytes { bytes in
                _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: byteCount,
                                               destination: bytes.baseAddress!)
            }
            samples.withUnsafeBufferPointer { pointer in
                guard let base = pointer.baseAddress, channelCount > 0 else { return }
                let channels = (0..<channelCount).map { base + $0 }
                accumulator.add(channels: channels, stride: channelCount, frameCount: pointer.count / channelCount)
            }
        }
        return Waveform(peaks: accumulator.normalizedPeaks(), duration: duration)
    }
}

/// Collects the loudest sample in each of `bucketCount` equal stretches of the file.
private struct PeakAccumulator {

    let framesPerBucket: Double
    var peaks: [Float]
    var position: Int = 0

    init(totalFrames: AVAudioFramePosition, bucketCount: Int) {
        framesPerBucket = max(Double(totalFrames) / Double(bucketCount), 1)
        peaks = Array(repeating: 0, count: bucketCount)
    }

    mutating func add(channels: [UnsafePointer<Float>], stride: Int, frameCount: Int) {
        var offset = 0
        while offset < frameCount {
            let bucket = min(Int(Double(position) / framesPerBucket), peaks.count - 1)
            let bucketEnd = Int((Double(bucket + 1) * framesPerBucket).rounded(.up))
            let count = max(1, min(frameCount - offset, bucketEnd - position))
            var peak = peaks[bucket]
            for channel in channels {
                var channelPeak: Float = 0
                vDSP_maxmgv(channel + offset * stride, vDSP_Stride(stride), &channelPeak, vDSP_Length(count))
                peak = max(peak, channelPeak)
            }
            peaks[bucket] = peak
            offset += count
            position += count
        }
    }

    func normalizedPeaks() -> [Float] {
        guard let loudest = peaks.max(), loudest > 0 else { return peaks }
        return peaks.map { min($0 / loudest, 1) }
    }
}
