import AVFoundation
import Foundation

/// A format Videoglot can write from a video file.
public enum VideoFormat: String, CaseIterable, Sendable, Hashable, Identifiable {
    case mp4
    case mov
    case m4v
    /// The video's audio track on its own.
    case m4a

    public var id: String { rawValue }

    public var displayName: String { rawValue.uppercased() }

    public var fileExtension: String { rawValue }

    /// Whether the output drops the video track.
    public var isAudioOnly: Bool { self == .m4a }

    var fileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        case .m4v: return .m4v
        case .m4a: return .m4a
        }
    }

    /// Video file extensions Videoglot reads.
    public static let sourceExtensions: Set<String> = ["mp4", "m4v", "mov", "3gp", "3g2"]

    /// Targets offered for a file with this extension, before its tracks are inspected. The file's own container
    /// is never offered. Conversions copy streams as-is, so quality never changes.
    public static func targets(forPathExtension pathExtension: String) -> [VideoFormat] {
        let source = pathExtension.lowercased()
        guard sourceExtensions.contains(source) else { return [] }
        return allCases.filter { $0.rawValue != source }
    }
}
