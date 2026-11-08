import Foundation

public enum VideoglotError: LocalizedError, Equatable {
    /// The file's extension isn't a video container Videoglot reads, or the target is its own container.
    case conversionNotAllowed(from: String, to: VideoFormat)
    /// The streams can't be copied into the target container without re-encoding.
    case incompatibleStreams(VideoFormat)
    /// Audio extraction was requested but the video has no audio track.
    case noAudioTrack
    /// A file already exists where the converted file would be written.
    case outputExists(URL)
    /// The file's container can't be trimmed without re-encoding.
    case trimNotSupported(String)
    /// The trim's end is not after its start, or lies outside the video.
    case invalidTrimRange

    public var errorDescription: String? {
        switch self {
        case .conversionNotAllowed(let source, let target):
            return "Converting \(source.uppercased()) to \(target.displayName) is not supported."
        case .incompatibleStreams(let target):
            return "This video's streams can't be stored in \(target.displayName) without re-encoding."
        case .noAudioTrack:
            return "This video has no audio track."
        case .outputExists(let url):
            return "\"\(url.lastPathComponent)\" already exists."
        case .trimNotSupported(let container):
            return "\(container.uppercased()) videos can't be trimmed."
        case .invalidTrimRange:
            return "The trimmed section is empty."
        }
    }
}
