import Foundation

extension Audioglot {

    /// Extensions of files that may be trimmable. The codec decides in the end: a file is only trimmed when its
    /// codec can be written back, which ``trim(_:from:to:outputURL:progress:)`` checks.
    public static let trimmableExtensions: Set<String> = [
        "wav", "wave", "aif", "aiff", "aifc", "flac", "m4a", "m4b", "mp3", "ogg", "oga", "opus"
    ]

    /// Writes the part of the file at `url` between `start` and `end` (in seconds) to `outputURL`, in the same
    /// format as the source. The source is left untouched.
    ///
    /// Every cut lands on an exact sample.
    /// - AAC-LC is copied packet by packet, so its quality never changes. See ``AACPacketTrimmer``.
    /// - MP3 is copied frame by frame, so its quality never changes either. See ``MP3FrameTrimmer``.
    /// - WAV, AIFF, FLAC and ALAC are re-encoded losslessly.
    /// - Vorbis, Opus, other AAC profiles, and MP3s whose start can't be placed exactly (a Xing frame without a
    ///   LAME tag) are re-encoded at no more than the source's bitrate.
    ///
    /// - Throws: ``AudioglotError/trimNotSupported(_:)`` for codecs Audioglot can't write,
    ///   ``AudioglotError/invalidTrimRange`` when the range is empty, ``AudioglotError/outputExists(_:)`` when the
    ///   output file already exists, `CancellationError` when the calling task is cancelled, or the underlying
    ///   decoder, encoder or export error.
    public static func trim(
        _ url: URL,
        from start: TimeInterval,
        to end: TimeInterval,
        outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard start >= 0, end > start else { throw AudioglotError.invalidTrimRange }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AudioglotError.outputExists(outputURL)
        }
        let source = try AudioSource(contentsOf: url)
        guard let format = source.format else { throw AudioglotError.trimNotSupported(source.codecName) }

        do {
            if format == .aac && AACPacketTrimmer.canTrim(url) {
                try await trimAACPackets(url, from: start, to: end, outputURL: outputURL, progress: progress)
            } else if format == .mp3,
                      try await trimMP3Frames(url, from: start, to: end, outputURL: outputURL, progress: progress) {
                // Copied without re-encoding
            } else {
                try await transcode(source: source, target: format, outputURL: outputURL,
                                    timeRange: start...end, progress: progress)
            }
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    @concurrent
    private static func trimAACPackets(_ url: URL, from start: TimeInterval, to end: TimeInterval,
                                       outputURL: URL, progress: (@Sendable (Double) -> Void)?) async throws {
        try AACPacketTrimmer.trim(url, from: start, to: end, outputURL: outputURL, progress: progress)
    }

    /// Trims by copying frames, returning false when the file can't be trimmed that way and must be re-encoded.
    @concurrent
    private static func trimMP3Frames(_ url: URL, from start: TimeInterval, to end: TimeInterval,
                                      outputURL: URL, progress: (@Sendable (Double) -> Void)?) async throws -> Bool {
        do {
            try MP3FrameTrimmer.trim(url, from: start, to: end, outputURL: outputURL, progress: progress)
            return true
        } catch is MP3FrameTrimmer.Unsupported {
            return false
        }
    }
}
