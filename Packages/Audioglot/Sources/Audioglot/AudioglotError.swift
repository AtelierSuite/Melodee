import Foundation

public enum AudioglotError: LocalizedError, Equatable {
    /// The conversion would increase fidelity (lossy to lossless) or targets the source's own format.
    case conversionNotAllowed(from: String, to: AudioFormat)
    /// A file already exists where the converted file would be written.
    case outputExists(URL)
    /// The decoder or encoder could not agree on an audio format.
    case unsupportedAudioFormat

    public var errorDescription: String? {
        switch self {
        case .conversionNotAllowed(let source, let target):
            return "Converting \(source) to \(target.displayName) is not supported."
        case .outputExists(let url):
            return "\"\(url.lastPathComponent)\" already exists."
        case .unsupportedAudioFormat:
            return "The audio format of this file is not supported."
        }
    }
}
