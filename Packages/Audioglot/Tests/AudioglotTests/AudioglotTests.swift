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
                         sampleRate: Double = 44100, channels: AVAudioChannelCount = 2) throws -> URL {
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
        let frames = AVAudioFrameCount(sampleRate)
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
}
