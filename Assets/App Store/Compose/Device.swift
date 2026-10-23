import AppKit

/// `Assets/App Store`, which holds the frames, the raw captures, and the composed output.
let assetsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

/// Captures live in `Raw/<device>/<lang>/` and are written to `<device>/<lang>/`.
enum Device: String {
    case iPhone
    case iPad

    /// 6.5" iPhone and 13" iPad.
    var canvasSize: NSSize {
        switch self {
        case .iPhone: NSSize(width: 1284, height: 2778)
        case .iPad: NSSize(width: 2048, height: 2732)
        }
    }

    /// The top of the header's line box.
    var textTop: CGFloat {
        switch self {
        case .iPhone: 120
        case .iPad: 110
        }
    }

    var textWidth: CGFloat {
        switch self {
        case .iPhone: 1124
        case .iPad: 1800
        }
    }

    var headerSize: CGFloat {
        switch self {
        case .iPhone: 104
        case .iPad: 116
        }
    }

    var captionSize: CGFloat {
        switch self {
        case .iPhone: 62
        case .iPad: 64
        }
    }

    /// The hardware's center on the canvas, and its width. It runs off the bottom.
    var placementCenter: NSPoint {
        switch self {
        case .iPhone: NSPoint(x: 642, y: 1640)
        case .iPad: NSPoint(x: 1024, y: 1650)
        }
    }

    var placementWidth: CGFloat {
        switch self {
        case .iPhone: 1060
        case .iPad: 1560
        }
    }

    func rawURL(_ name: String, language: String) -> URL {
        assetsDir.appendingPathComponent("Raw").appendingPathComponent(rawValue)
            .appendingPathComponent(language).appendingPathComponent(name)
    }

    func outDir(_ language: String) -> URL {
        assetsDir.appendingPathComponent(rawValue).appendingPathComponent(language)
    }
}
