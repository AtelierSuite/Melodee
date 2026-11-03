@preconcurrency import AVFoundation
import Foundation
import SFBAudioEngine

/// Converts audio files between formats, only ever keeping or lowering fidelity.
public enum Audioglot {

    /// Converts the file at `url`. See ``convert(_:to:outputURL:progress:)-(AudioSource,_,_,_)``.
    @discardableResult
    public static func convert(
        _ url: URL,
        to target: AudioFormat,
        outputURL: URL? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await convert(AudioSource(contentsOf: url), to: target, outputURL: outputURL, progress: progress)
    }

    /// Converts `source` to `target` and returns the URL of the new file. The source is left untouched.
    ///
    /// - Parameters:
    ///   - outputURL: Where to write. Defaults to ``defaultOutputURL(for:target:)``.
    ///   - progress: Called with values from 0 to 1 as the conversion advances.
    /// - Throws: ``AudioglotError/conversionNotAllowed(from:to:)`` when the matrix forbids the conversion,
    ///   ``AudioglotError/outputExists(_:)`` when the output file already exists, `CancellationError` when the
    ///   calling task is cancelled, or the underlying decoder or encoder error.
    @discardableResult
    public static func convert(
        _ source: AudioSource,
        to target: AudioFormat,
        outputURL: URL? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        guard source.canConvert(to: target) else {
            throw AudioglotError.conversionNotAllowed(from: source.codecName, to: target)
        }
        let outputURL = outputURL ?? defaultOutputURL(for: source, target: target)
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AudioglotError.outputExists(outputURL)
        }

        do {
            try await transcode(source: source, target: target, outputURL: outputURL, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        return outputURL
    }

    /// Formats the file at `url` may be converted to, or an empty array if it can't be decoded.
    ///
    /// Only reads the stream header, so it's cheap enough to call while building a menu.
    public static func availableTargets(for url: URL) -> [AudioFormat] {
        (try? AudioSource(contentsOf: url, readingBitrate: false))?.availableTargets ?? []
    }

    /// Next to the source, with the target's extension. When that would be the source itself (for example ALAC to
    /// AAC, which are both `.m4a`), the format name is appended: `Song (AAC).m4a`.
    public static func defaultOutputURL(for source: AudioSource, target: AudioFormat) -> URL {
        let base = source.url.deletingPathExtension()
        let url = base.appendingPathExtension(target.fileExtension)
        guard url.standardizedFileURL.path == source.url.standardizedFileURL.path else { return url }
        return base.deletingLastPathComponent()
            .appendingPathComponent("\(base.lastPathComponent) (\(target.displayName))")
            .appendingPathExtension(target.fileExtension)
    }

    @concurrent
    private static func transcode(
        source: AudioSource,
        target: AudioFormat,
        outputURL: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        let decoder = try AudioDecoder(url: source.url)
        try decoder.open()
        defer { try? decoder.close() }

        let encoder = try EncoderFactory.makeEncoder(
            for: target, outputURL: outputURL, bitrate: EncoderFactory.bitrate(for: target, source: source)
        )
        try encoder.setSourceFormat(EncoderFactory.intermediateFormat(for: target, decoder: decoder)
                                    ?? decoder.processingFormat)
        encoder.estimatedFramesToEncode = decoder.length
        try encoder.openReturningError()
        defer { try? encoder.close() }

        let frameCapacity: AVAudioFrameCount = 4096
        guard let converter = AVAudioConverter(from: decoder.processingFormat, to: encoder.processingFormat),
              let decodeBuffer = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: frameCapacity),
              let encodeBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity)
        else {
            throw AudioglotError.unsupportedAudioFormat
        }

        let totalFrames = decoder.length
        var lastReportedPercent = -1
        progress?(0)

        while true {
            try Task.checkCancellation()

            var decodeError: Error?
            var convertError: NSError?
            let status = converter.convert(to: encodeBuffer, error: &convertError) { packetCount, inputStatus in
                do {
                    try decoder.decode(into: decodeBuffer, length: packetCount)
                } catch {
                    decodeError = error
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                if decodeBuffer.frameLength == 0 {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return decodeBuffer
            }

            if let decodeError { throw decodeError }
            if status == .error { throw convertError ?? AudioglotError.unsupportedAudioFormat }
            if encodeBuffer.frameLength > 0 {
                try encoder.encode(from: encodeBuffer, length: encodeBuffer.frameLength)
            }
            if status == .endOfStream { break }

            if let progress, totalFrames > 0 {
                let percent = Int(Double(decoder.position) / Double(totalFrames) * 100)
                if percent != lastReportedPercent {
                    lastReportedPercent = percent
                    progress(min(Double(percent) / 100, 1))
                }
            }
        }

        try encoder.finish()
        progress?(1)
    }
}
