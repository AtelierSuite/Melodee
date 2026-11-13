@preconcurrency import AVFoundation
import Foundation
import SFBAudioEngine
import Testing
@testable import Audioglot

@Suite struct ConversionMatrixTests {

    private func source(_ format: AudioFormat?, lossless: Bool, bitrate: Int? = nil) -> AudioSource {
        AudioSource(url: URL(filePath: "/tmp/song.x"), format: format, isLossless: lossless,
                    bitrate: bitrate, sampleRate: 44100, channelCount: 2)
    }

    @Test func losslessSourcesCanBecomeAnythingButThemselves() {
        for format in AudioFormat.allCases where format.isLossless {
            let targets = source(format, lossless: true).availableTargets
            #expect(targets == AudioFormat.allCases.filter { $0 != format })
        }
    }

    @Test func lossySourcesOnlyBecomeOtherLossyFormats() {
        for format in AudioFormat.allCases where !format.isLossless {
            let targets = source(format, lossless: false).availableTargets
            #expect(targets == AudioFormat.allCases.filter { !$0.isLossless && $0 != format })
        }
    }

    @Test func unknownCodecsFollowTheirFidelity() {
        // e.g. WavPack (lossless) and Speex (lossy), which Audioglot reads but does not write.
        #expect(source(nil, lossless: true).availableTargets == AudioFormat.allCases)
        #expect(source(nil, lossless: false).availableTargets == AudioFormat.allCases.filter { !$0.isLossless })
    }

    @Test func lossyBitrateNeverExceedsSource() {
        #expect(EncoderFactory.bitrate(for: .aac, source: source(.mp3, lossless: false, bitrate: 128)) == 128)
        #expect(EncoderFactory.bitrate(for: .mp3, source: source(.aac, lossless: false, bitrate: 500)) == 320)
        #expect(EncoderFactory.bitrate(for: .opus, source: source(.flac, lossless: true, bitrate: 900)) == 192)
        #expect(EncoderFactory.bitrate(for: .flac, source: source(.wav, lossless: true)) == nil)
    }

    @Test func m4aToM4aGetsADistinctName() {
        let alac = AudioSource(url: URL(filePath: "/music/Song.m4a"), format: .alac, isLossless: true,
                               bitrate: nil, sampleRate: 44100, channelCount: 2)
        #expect(Audioglot.defaultOutputURL(for: alac, target: .aac).lastPathComponent == "Song (AAC).m4a")
        #expect(Audioglot.defaultOutputURL(for: alac, target: .flac).lastPathComponent == "Song.flac")
    }
}

@Suite(.serialized) struct EncodingTests {

    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioglotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Writes one second of a 440 Hz sine wave as WAV.
    private func makeWAV(name: String, bitDepth: Int, float: Bool = false,
                         sampleRate: Double = 44100, channels: AVAudioChannelCount = 2,
                         seconds: Double = 1) throws -> URL {
        let url = directory.appendingPathComponent("\(name).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: float,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] = Float(sin(2 * .pi * 440 * Double(frame) / sampleRate)) * 0.5
            }
        }
        try file.write(from: buffer)
        return url
    }

    @Test(arguments: [
        ("cd", 16, false, 44100.0, AVAudioChannelCount(2)),
        ("hires", 24, false, 96000.0, AVAudioChannelCount(2)),
        ("float", 32, true, 96000.0, AVAudioChannelCount(1))
    ])
    func losslessSourceConvertsToEveryTarget(
        name: String, bitDepth: Int, float: Bool, sampleRate: Double, channels: AVAudioChannelCount
    ) async throws {
        let wav = try makeWAV(name: name, bitDepth: bitDepth, float: float, sampleRate: sampleRate, channels: channels)
        let source = try AudioSource(contentsOf: wav)
        #expect(source.format == .wav)
        #expect(source.isLossless)

        for target in source.availableTargets {
            let output = try await Audioglot.convert(source, to: target)
            let result = try AudioSource(contentsOf: output)
            #expect(result.format == target, "\(name) → \(target)")
            #expect(result.isLossless == target.isLossless, "\(name) → \(target)")
            if target.isLossless, !float {
                let properties = try AudioFile(readingPropertiesAndMetadataFrom: output).properties
                #expect(properties.bitDepth == bitDepth, "\(name) → \(target) kept bit depth")
                #expect(result.sampleRate == sampleRate, "\(name) → \(target) kept sample rate")
            }
            try FileManager.default.removeItem(at: output)
        }
    }

    @Test func lossySourceRefusesLosslessAndCapsBitrate() async throws {
        let wav = try makeWAV(name: "lossy", bitDepth: 16)
        let mp3 = try await Audioglot.convert(wav, to: .mp3)
        try FileManager.default.removeItem(at: wav)

        let source = try AudioSource(contentsOf: mp3)
        #expect(source.format == .mp3)
        #expect(!source.isLossless)
        #expect(source.availableTargets == [.aac, .vorbis, .opus])

        await #expect(throws: AudioglotError.self) {
            try await Audioglot.convert(source, to: .flac)
        }
        for target in source.availableTargets {
            let output = try await Audioglot.convert(source, to: target)
            #expect(try AudioSource(contentsOf: output).format == target)
        }
    }

    @Test func alacAndAacInM4aAreToldApart() async throws {
        let wav = try makeWAV(name: "m4a", bitDepth: 16)
        let alac = try await Audioglot.convert(wav, to: .alac)
        let alacSource = try AudioSource(contentsOf: alac)
        #expect(alacSource.format == .alac)
        #expect(alacSource.isLossless)

        let aac = try await Audioglot.convert(alacSource, to: .aac)
        #expect(aac.lastPathComponent == "m4a (AAC).m4a")
        let aacSource = try AudioSource(contentsOf: aac)
        #expect(aacSource.format == .aac)
        #expect(!aacSource.isLossless)
    }

    @Test func existingOutputIsNotOverwritten() async throws {
        let wav = try makeWAV(name: "exists", bitDepth: 16)
        let flac = try await Audioglot.convert(wav, to: .flac)
        await #expect(throws: AudioglotError.outputExists(flac)) {
            try await Audioglot.convert(wav, to: .flac)
        }
    }

    /// Decodes the whole file, returning its sample count, channel count and loudest sample.
    private func decodeAll(_ url: URL) throws -> (frames: Int, channels: Int, peak: Float) {
        let decoder = try AudioDecoder(url: url)
        try decoder.open()
        defer { try? decoder.close() }
        let format = AVAudioFormat(standardFormatWithSampleRate: decoder.processingFormat.sampleRate,
                                   channels: decoder.processingFormat.channelCount)!
        let converter = AVAudioConverter(from: decoder.processingFormat, to: format)!
        let input = AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: 4096)!
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var frames = 0
        var peak: Float = 0
        while true {
            try decoder.decode(into: input, length: 4096)
            guard input.frameLength > 0 else { break }
            try converter.convert(to: output, from: input)
            frames += Int(output.frameLength)
            for channel in 0..<Int(format.channelCount) {
                for index in 0..<Int(output.frameLength) {
                    peak = max(peak, abs(output.floatChannelData![channel][index]))
                }
            }
        }
        return (frames, Int(format.channelCount), peak)
    }

    @Test(arguments: [AVAudioChannelCount(1), 2])
    func mp3KeepsEverySampleAndChannelCount(channels: AVAudioChannelCount) async throws {
        // SFBAudioEngine's MP3 encoder used to drop the frames LAME returns when flushed, and to crash on mono
        let wav = try makeWAV(name: "mp3-\(channels)", bitDepth: 16, channels: channels, seconds: 3)
        for run in 0..<5 {
            let mp3 = try await Audioglot.convert(wav, to: .mp3, outputURL: directory.appendingPathComponent("\(channels)-\(run).mp3"))
            let result = try decodeAll(mp3)
            #expect(result.frames == 132300)
            #expect(result.channels == Int(channels))
            #expect(abs(result.peak - 0.5) < 0.05, "peak \(result.peak)")
        }
    }

    // MARK: Trimming

    private func duration(of url: URL) throws -> TimeInterval {
        let decoder = try AudioDecoder(url: url)
        try decoder.open()
        defer { try? decoder.close() }
        return Double(decoder.length) / decoder.processingFormat.sampleRate
    }

    @Test func losslessTrimsCutAtExactSamples() async throws {
        let wav = try makeWAV(name: "trim", bitDepth: 16)
        let flac = try await Audioglot.convert(wav, to: .flac)
        let aiff = try await Audioglot.convert(wav, to: .aiff)
        for source in [wav, flac, aiff] {
            let output = directory.appendingPathComponent("trimmed-\(source.lastPathComponent)")
            try await Audioglot.trim(source, from: 0.25, to: 0.75, outputURL: output)
            let decoder = try AudioDecoder(url: output)
            try decoder.open()
            #expect(decoder.length == 22050, "\(source.lastPathComponent)")
            try decoder.close()
            #expect(try AudioSource(contentsOf: output).format == AudioSource(contentsOf: source).format)
        }
    }

    @Test func trimEndPastTheFileIsClamped() async throws {
        let wav = try makeWAV(name: "clamp", bitDepth: 16)
        let output = directory.appendingPathComponent("clamped.wav")
        try await Audioglot.trim(wav, from: 0.5, to: 10, outputURL: output)
        #expect(abs(try duration(of: output) - 0.5) < 0.001)
    }

    @Test func lossyTrimsKeepTheirFormat() async throws {
        let wav = try makeWAV(name: "lossytrim", bitDepth: 16)
        for target in [AudioFormat.mp3, .vorbis, .opus] {
            let encoded = try await Audioglot.convert(wav, to: target)
            let output = directory.appendingPathComponent("trimmed-\(encoded.lastPathComponent)")
            try await Audioglot.trim(encoded, from: 0.2, to: 0.7, outputURL: output)
            #expect(try AudioSource(contentsOf: output).format == target)
            // Encoders add a little padding, so allow a few milliseconds either way
            #expect(abs(try duration(of: output) - 0.5) < 0.06, "\(target)")
        }
    }

    @Test func m4aTrimsCutAtExactSamples() async throws {
        // SFBAudioEngine can't open M4A files of only a few kilobytes, so use a realistic length
        let wav = try makeWAV(name: "m4atrim", bitDepth: 16, seconds: 5)
        for target in [AudioFormat.aac, .alac] {
            let encoded = try await Audioglot.convert(wav, to: target,
                                                      outputURL: directory.appendingPathComponent("\(target).m4a"))
            let output = directory.appendingPathComponent("trimmed-\(target).m4a")
            try await Audioglot.trim(encoded, from: 1.0, to: 3.5, outputURL: output)
            let result = try AudioSource(contentsOf: output)
            #expect(result.format == target)
            let decoder = try AudioDecoder(url: output)
            try decoder.open()
            #expect(decoder.length == 110250, "\(target)")
            try decoder.close()
        }
    }

    /// Decodes the whole file with SFBAudioEngine (mpg123 for MP3), returning its first channel.
    private func decodeFirstChannel(_ url: URL) throws -> [Float] {
        let decoder = try AudioDecoder(url: url)
        try decoder.open()
        defer { try? decoder.close() }
        let format = AVAudioFormat(standardFormatWithSampleRate: decoder.processingFormat.sampleRate,
                                   channels: decoder.processingFormat.channelCount)!
        let converter = AVAudioConverter(from: decoder.processingFormat, to: format)!
        let input = AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: 4096)!
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var samples: [Float] = []
        while true {
            try decoder.decode(into: input, length: 4096)
            guard input.frameLength > 0 else { break }
            try converter.convert(to: output, from: input)
            samples.append(contentsOf: UnsafeBufferPointer(start: output.floatChannelData![0],
                                                           count: Int(output.frameLength)))
        }
        return samples
    }

    @Test(arguments: [
        (44100.0, AVAudioChannelCount(2), 1.0, 3.5),
        (44100.0, AVAudioChannelCount(1), 0.0, 2.0),
        (48000.0, AVAudioChannelCount(2), 2.3, 5.0),
        (22050.0, AVAudioChannelCount(2), 0.7, 4.1)
    ])
    func mp3TrimsCopyFramesAndCutAtExactSamples(sampleRate: Double, channels: AVAudioChannelCount,
                                                start: Double, end: Double) async throws {
        let name = "mp3copy-\(Int(sampleRate))-\(channels)-\(start)"
        let wav = try makeWAV(name: name, bitDepth: 16, sampleRate: sampleRate, channels: channels, seconds: 5)
        let mp3 = try await Audioglot.convert(wav, to: .mp3,
                                              outputURL: directory.appendingPathComponent("\(name).mp3"))
        let output = directory.appendingPathComponent("trimmed-\(name).mp3")
        // Called directly, so a fallback to re-encoding fails the test
        try MP3FrameTrimmer.trim(mp3, from: start, to: end, outputURL: output, progress: nil)

        let startSample = Int((start * sampleRate).rounded())
        let wanted = Int((end * sampleRate).rounded()) - startSample
        let original = try decodeFirstChannel(mp3)
        let trimmed = try decodeFirstChannel(output)
        #expect(trimmed.count == wanted, "mpg123 length")
        #expect(try AVAudioFile(forReading: output).length == AVAudioFramePosition(wanted), "Core Audio length")
        let difference = zip(trimmed, original[startSample...]).map { abs($0 - $1) }.max() ?? 1
        #expect(difference < 0.0001, "decoded samples differ by \(difference)")
        // The bitrate is estimated from size and length, which the pre-roll frames nudge up a little
        let bitrates = (try AudioSource(contentsOf: output).bitrate ?? 0, try AudioSource(contentsOf: mp3).bitrate ?? 0)
        #expect(abs(bitrates.0 - bitrates.1) <= 5, "bitrates \(bitrates)")
    }

    @Test(arguments: [(1.2, 2.6), (0.0, 1.5)])
    func bareMP3StreamIsTrimmedFromItsFirstFrame(start: Double, end: Double) async throws {
        let wav = try makeWAV(name: "bare-\(start)", bitDepth: 16, seconds: 3)
        let mp3 = try await Audioglot.convert(wav, to: .mp3)
        // A bare stream of frames with no Info frame, as some encoders write
        var data = try Data(contentsOf: mp3)
        data.removeSubrange(0..<MP3FrameHeader([UInt8](data), at: 0)!.length)
        let untagged = directory.appendingPathComponent("bare-\(start).mp3")
        try data.write(to: untagged)
        let output = directory.appendingPathComponent("bare-trimmed-\(start).mp3")
        try MP3FrameTrimmer.trim(untagged, from: start, to: end, outputURL: output, progress: nil)

        // Players play every frame of an untagged file, but a trim can't start in the decoder's lead-in
        let startSample = max(MP3FrameTrimmer.decoderDelay, Int((start * 44100).rounded()))
        let wanted = Int((end * 44100).rounded()) - startSample
        let original = try decodeFirstChannel(untagged)
        let trimmed = try decodeFirstChannel(output)
        #expect(trimmed.count == wanted, "mpg123 length")
        #expect(try AVAudioFile(forReading: output).length == AVAudioFramePosition(wanted), "Core Audio length")
        let difference = zip(trimmed, original[startSample...]).map { abs($0 - $1) }.max() ?? 1
        #expect(difference < 0.0001, "decoded samples differ by \(difference)")
    }

    @Test func mp3WithAnInfoFrameButNoLAMETagIsReEncoded() async throws {
        let wav = try makeWAV(name: "nolame", bitDepth: 16, seconds: 3)
        let mp3 = try await Audioglot.convert(wav, to: .mp3)
        var data = try Data(contentsOf: mp3)
        let tag = data.range(of: Data("LAME".utf8))!
        data.replaceSubrange(tag.lowerBound..<(tag.lowerBound + 36), with: [UInt8](repeating: 0, count: 36))
        let untagged = directory.appendingPathComponent("nolame.mp3")
        try data.write(to: untagged)
        #expect(throws: MP3FrameTrimmer.Unsupported.self) {
            try MP3FrameTrimmer.trim(untagged, from: 0.5, to: 2,
                                     outputURL: directory.appendingPathComponent("nolame-x.mp3"), progress: nil)
        }
        let output = directory.appendingPathComponent("nolame-trimmed.mp3")
        try await Audioglot.trim(untagged, from: 0.5, to: 2, outputURL: output)
        #expect(try AudioSource(contentsOf: output).format == .mp3)
    }

    @Test func emptyRangesAreRejected() async throws {
        let wav = try makeWAV(name: "empty", bitDepth: 16)
        let output = directory.appendingPathComponent("empty-out.wav")
        await #expect(throws: AudioglotError.invalidTrimRange) {
            try await Audioglot.trim(wav, from: 0.6, to: 0.4, outputURL: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
