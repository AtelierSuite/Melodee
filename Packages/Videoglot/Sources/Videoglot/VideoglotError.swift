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
    /// The file's container doesn't support embedding subtitle tracks.
    case subtitleEmbedNotSupported(String)
    /// The requested embedded subtitle track wasn't found.
    case subtitleTrackNotFound
    /// Reading an embedded subtitle track failed.
    case subtitleReadFailed
    /// Writing an embedded subtitle track failed.
    case subtitleWriteFailed

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
        case .subtitleEmbedNotSupported(let container):
            return "Subtitles can't be embedded into \(container.uppercased()) videos."
        case .subtitleTrackNotFound:
            return "The selected subtitle track wasn't found in this video."
        case .subtitleReadFailed:
            return "Couldn't read the subtitle track from this video."
        case .subtitleWriteFailed:
            return "Couldn't embed the subtitle track into this video."
        }
    }
}
