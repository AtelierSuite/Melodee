import AppKit

/// `Assets/App Store`, which holds the frames, the raw captures, and the composed output.
let assetsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

/// Captures live in `Raw/<device>/<lang>/` and are written to `<device>/<lang>/`.
enum Device: String {
    case iPhone
    case iPad
    case mac = "Mac"

    /// 6.5" iPhone, 13" iPad, and the Mac's 16:10.
    var canvasSize: NSSize {
        switch self {
        case .iPhone: NSSize(width: 1284, height: 2778)
        case .iPad: NSSize(width: 2048, height: 2732)
        case .mac: NSSize(width: 2880, height: 1800)
        }
    }

    /// The top of the header's line box.
    var textTop: CGFloat {
        switch self {
        case .iPhone: 120
        case .iPad: 110
        case .mac: 110
        }
    }

    var textWidth: CGFloat {
        switch self {
        case .iPhone: 1124
        case .iPad: 1800
        case .mac: 2400
        }
    }

    var headerSize: CGFloat {
        switch self {
        case .iPhone: 104
        case .iPad: 116
        case .mac: 112
        }
    }

    var captionSize: CGFloat {
        switch self {
        case .iPhone: 62
        case .iPad: 64
        case .mac: 64
        }
    }

    /// The hardware's width, or the window's on the Mac. It is centered in the space below the copy.
    var placementWidth: CGFloat {
        switch self {
        case .iPhone: 1060
        case .iPad: 1560
        case .mac: 2160
        }
    }

    /// The transparent margin, in pixels, that Capture/Mac/crop.swift leaves around the Mac's window:
    /// capture-mac.sh's `window_margin` points at 2x.
    static let windowMargin: CGFloat = 320

    func rawURL(_ name: String, language: String) -> URL {
        assetsDir.appendingPathComponent("Raw").appendingPathComponent(rawValue)
            .appendingPathComponent(language).appendingPathComponent(name)
    }

    func outDir(_ language: String) -> URL {
        assetsDir.appendingPathComponent(rawValue).appendingPathComponent(language)
    }
}
