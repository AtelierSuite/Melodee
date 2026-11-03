import Foundation

/// An audio format that Audioglot can write.
public enum AudioFormat: String, CaseIterable, Sendable, Hashable, Identifiable {
    case wav
    case aiff
    case flac
    case alac
    case mp3
    case aac
    case vorbis
    case opus

    public var id: String { rawValue }

    /// A short, human-readable name for the format.
    public var displayName: String {
        switch self {
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .flac: return "FLAC"
        case .alac: return "ALAC"
        case .mp3: return "MP3"
        case .aac: return "AAC"
        case .vorbis: return "Ogg Vorbis"
        case .opus: return "Opus"
        }
    }

    /// The file extension used when writing this format.
    ///
    /// ALAC and AAC both use `m4a`.
    public var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .aiff: return "aiff"
        case .flac: return "flac"
        case .alac, .aac: return "m4a"
        case .mp3: return "mp3"
        case .vorbis: return "ogg"
        case .opus: return "opus"
        }
    }

    /// Whether the format preserves audio exactly.
    public var isLossless: Bool {
        switch self {
        case .wav, .aiff, .flac, .alac: return true
        case .mp3, .aac, .vorbis, .opus: return false
        }
    }
}
