import Foundation

public enum AudioglotError: LocalizedError, Equatable {
    /// The conversion would increase fidelity (lossy to lossless) or targets the source's own format.
    case conversionNotAllowed(from: String, to: AudioFormat)
    /// A file already exists where the converted file would be written.
    case outputExists(URL)
    /// The decoder or encoder could not agree on an audio format.
    case unsupportedAudioFormat
    /// The file's codec can't be written back, or its decoder can't seek, so it can't be trimmed.
    case trimNotSupported(String)
    /// The trim's end is not after its start, or lies outside the file.
    case invalidTrimRange

    public var errorDescription: String? {
        switch self {
        case .conversionNotAllowed(let source, let target):
            return "Converting \(source) to \(target.displayName) is not supported."
        case .outputExists(let url):
            return "\"\(url.lastPathComponent)\" already exists."
        case .unsupportedAudioFormat:
            return "The audio format of this file is not supported."
        case .trimNotSupported(let codec):
            return "\(codec) files can't be trimmed."
        case .invalidTrimRange:
            return "The trimmed section is empty."
        }
    }
}
