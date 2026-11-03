@preconcurrency import AVFoundation
import Foundation
import SFBAudioEngine

/// What Audioglot learned about an audio file by reading its stream, not its file extension.
public struct AudioSource: Sendable, Hashable {

    public let url: URL

    /// The codec, when it is one Audioglot can also write.
    ///
    /// `nil` for codecs such as Speex, WavPack or Monkey's Audio, and for PCM in containers other than WAV or AIFF.
    public let format: AudioFormat?

    /// Whether the codec preserves audio exactly. Decides which targets are allowed.
    public let isLossless: Bool

    /// Average bitrate in kbps, when known.
    public let bitrate: Int?

    public let sampleRate: Double
    public let channelCount: Int

    /// A label for the codec, used in error messages.
    public var codecName: String {
        format?.displayName ?? url.pathExtension.uppercased()
    }

    /// Formats this file may be converted to: lossless sources can go anywhere, lossy sources only to other lossy
    /// formats. The source's own format is never offered.
    public var availableTargets: [AudioFormat] {
        AudioFormat.allCases.filter(canConvert(to:))
    }

    public func canConvert(to target: AudioFormat) -> Bool {
        if target == format { return false }
        return isLossless || !target.isLossless
    }

    public init(url: URL, format: AudioFormat?, isLossless: Bool, bitrate: Int?, sampleRate: Double, channelCount: Int) {
        self.url = url
        self.format = format
        self.isLossless = isLossless
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    /// Reads the audio stream at `url` to identify its codec.
    public init(contentsOf url: URL) throws {
        try self.init(contentsOf: url, readingBitrate: true)
    }

    /// `readingBitrate: false` skips parsing tags and artwork, for when only the codec matters.
    init(contentsOf url: URL, readingBitrate: Bool) throws {
        let decoder = try AudioDecoder(url: url)
        try decoder.open()
        defer { try? decoder.close() }

        let sourceFormat = decoder.sourceFormat
        var formatID = sourceFormat.streamDescription.pointee.mFormatID
        var isLossless = decoder.decodingIsLossless
        if Self.isFloatPCMFromLibsndfile(decoder) {
            formatID = kAudioFormatLinearPCM
            isLossless = true
        }
        let properties = readingBitrate ? try? AudioFile(readingPropertiesAndMetadataFrom: url).properties : nil

        self.url = url
        self.format = Self.format(for: formatID, pathExtension: url.pathExtension.lowercased())
        self.isLossless = isLossless
        self.bitrate = properties?.bitrate.map { Int($0.rounded()) }.flatMap { $0 > 0 ? $0 : nil }
        self.sampleRate = sourceFormat.sampleRate
        self.channelCount = Int(sourceFormat.channelCount)
    }

    /// SFBAudioEngine's libsndfile decoder reports 32/64-bit float WAV and AIFF with a generic 'SNDF' format ID and
    /// conservatively calls them lossy. Float PCM is uncompressed, so treat it as lossless PCM.
    static func isFloatPCMFromLibsndfile(_ decoder: AudioDecoder) -> Bool {
        let source = decoder.sourceFormat.streamDescription.pointee
        let processing = decoder.processingFormat.commonFormat
        return source.mFormatID == 0x534E_4446 // 'SNDF'
            && (source.mBitsPerChannel == 32 || source.mBitsPerChannel == 64)
            && (processing == .pcmFormatFloat32 || processing == .pcmFormatFloat64)
    }

    static func format(for formatID: AudioFormatID, pathExtension: String) -> AudioFormat? {
        switch formatID {
        case kAudioFormatLinearPCM:
            switch pathExtension {
            case "wav", "wave": return .wav
            case "aif", "aiff", "aifc": return .aiff
            default: return nil
            }
        case kAudioFormatFLAC: return .flac
        case kAudioFormatAppleLossless: return .alac
        case kAudioFormatMPEGLayer3: return .mp3
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD, kAudioFormatMPEG4AAC_ELD_SBR,
             kAudioFormatMPEG4AAC_ELD_V2:
            return .aac
        case 0x564F_5242: return .vorbis // kSFBAudioFormatVorbis, 'VORB'
        case kAudioFormatOpus: return .opus
        default: return nil
        }
    }
}
