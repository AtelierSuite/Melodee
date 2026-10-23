import AppKit

struct Copy {
    let header: String
    let caption: String
}

/// Color stops from the bottom of the canvas to the top, and the text drawn over them.
struct Theme {
    let stops: [(NSColor, CGFloat)]
    let text: NSColor
}

/// One App Store screenshot: its copy, background, and the capture shown in the device.
struct Screenshot {
    let name: String
    /// Keyed by language code. A language without copy is skipped.
    let copy: [String: Copy]
    let theme: Theme
}
