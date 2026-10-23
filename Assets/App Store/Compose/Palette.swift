import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

/// Melodee's iris, with tints taken from the sample library's covers.
@MainActor
enum Palette {
    static let ink = color(0x1C1830)
    static let paper = color(0xFFFFFF)

    static let iris = Theme(stops: [(color(0xB8AEF7), 0), (color(0xEDEAFF), 0.85)], text: ink)
    static let teaParty = Theme(stops: [(color(0xF4C9A8), 0), (color(0xFFF3E4), 0.85)], text: ink)
    static let sweets = Theme(stops: [(color(0xF5B6D2), 0), (color(0xFFEEF5), 0.85)], text: ink)
    static let seance = Theme(stops: [(color(0xB6E9E2), 0), (color(0xEAE6FF), 0.85)], text: ink)
    static let nocturne = Theme(stops: [(color(0x120C2C), 0), (color(0x44307E), 1)], text: paper)
    static let atelier = Theme(stops: [(color(0x0C1530), 0), (color(0x5A2D74), 1)], text: paper)
}
