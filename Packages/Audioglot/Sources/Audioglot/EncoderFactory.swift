@preconcurrency import AVFoundation
import Foundation
import SFBAudioEngine

enum EncoderFactory {

    /// Builds an encoder for `target`. Lossless encoders are left to infer bit depth and sample rate from the source
    /// so nothing is truncated. `bitrate` is in kbps and only applies to lossy targets.
    static func makeEncoder(for target: AudioFormat, outputURL: URL, bitrate: Int?) throws -> AudioEncoder {
        switch target {
        case .wav:
            let encoder = try AudioEncoder(url: outputURL, encoderName: .libsndfile)
            encoder.settings = [.libsndfileMajorFormat: LibsndfileMajorFormat.WAV]
            return encoder
        case .aiff:
            let encoder = try AudioEncoder(url: outputURL, encoderName: .libsndfile)
            encoder.settings = [.libsndfileMajorFormat: LibsndfileMajorFormat.AIFF]
            return encoder
        case .flac:
            let encoder = try AudioEncoder(url: outputURL, encoderName: .FLAC)
            encoder.settings = [.flacCompressionLevel: NSNumber(value: 5)]
            return encoder
        case .alac:
            let encoder = try AudioEncoder(url: outputURL, encoderName: .coreAudio)
            encoder.settings = [
                .coreAudioFileTypeID: NSNumber(value: kAudioFileM4AType),
                .coreAudioFormatID: NSNumber(value: kAudioFormatAppleLossless)
            ]
            return encoder
        case .mp3:
            let encoder = try AudioEncoder(url: outputURL, encoderName: .MP3)
            encoder.settings = [
                .mp3ConstantBitrate: NSNumber(value: bitrate ?? 320),
                .mp3Quality: NSNumber(value: 2)
            ]
            return encoder
        case .aac:
            let encoder = try AudioEncoder(url: outputURL, encoderName: .coreAudio)
            encoder.settings = [
                .coreAudioFileTypeID: NSNumber(value: kAudioFileM4AType),
                .coreAudioFormatID: NSNumber(value: kAudioFormatMPEG4AAC),
                .coreAudioAudioConverterPropertySettings: [
                    NSNumber(value: kAudioConverterEncodeBitRate): NSNumber(value: (bitrate ?? 256) * 1000)
                ]
            ]
            return encoder
        case .vorbis:
            let encoder = try AudioEncoder(url: outputURL, encoderName: .oggVorbis)
            encoder.settings = [
                .vorbisTargetIsBitrate: NSNumber(value: true),
                .vorbisBitrate: NSNumber(value: bitrate ?? 256)
            ]
            return encoder
        case .opus:
            let encoder = try AudioEncoder(url: outputURL, encoderName: .oggOpus)
            encoder.settings = [
                .opusBitrate: NSNumber(value: bitrate ?? 192),
                .opusSignalType: OpusSignalType.music
            ]
            return encoder
        }
    }

    /// Picks a bitrate (kbps) for a lossy target. For lossy sources the bitrate never exceeds the source's, since a
    /// higher bitrate cannot restore quality and only makes the file bigger.
    static func bitrate(for target: AudioFormat, source: AudioSource) -> Int? {
        let isMono = source.channelCount == 1
        let ceiling: Int
        let floor: Int
        switch target {
        case .mp3: (ceiling, floor) = (320, 32)
        case .aac: (ceiling, floor) = (isMono ? 128 : 256, isMono ? 32 : 64)
        case .vorbis: (ceiling, floor) = (isMono ? 128 : 256, isMono ? 48 : 64)
        case .opus: (ceiling, floor) = (isMono ? 96 : 192, 16)
        case .wav, .aiff, .flac, .alac: return nil
        }
        guard !source.isLossless, let sourceBitrate = source.bitrate else { return ceiling }
        return min(ceiling, max(floor, sourceBitrate))
    }

    /// The PCM format handed to the encoder, or `nil` to use the decoder's format as-is.
    static func intermediateFormat(for target: AudioFormat, decoder: AudioDecoder) -> AVAudioFormat? {
        let decoded = decoder.processingFormat
        let isFloat = decoded.commonFormat == .pcmFormatFloat32 || decoded.commonFormat == .pcmFormatFloat64
        let commonFormat: AVAudioCommonFormat
        var sampleRate = decoded.sampleRate

        if target.isLossless {
            // FLAC and ALAC only store integer samples. Everything else is kept exactly as decoded.
            guard (target == .flac || target == .alac) && isFloat else { return nil }
            commonFormat = .pcmFormatInt32
        } else {
            // The AAC, Vorbis and LAME encoders reject or misbehave above 48 kHz, which lossy formats don't
            // benefit from anyway. Opus resamples to 48 kHz internally.
            commonFormat = .pcmFormatFloat32
            sampleRate = min(sampleRate, 48000)
            guard sampleRate != decoded.sampleRate else { return nil }
        }

        if let layout = decoded.channelLayout {
            return AVAudioFormat(commonFormat: commonFormat, sampleRate: sampleRate, interleaved: true,
                                 channelLayout: layout)
        }
        return AVAudioFormat(commonFormat: commonFormat, sampleRate: sampleRate,
                             channels: decoded.channelCount, interleaved: true)
    }
}
