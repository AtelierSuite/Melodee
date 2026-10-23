import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

/// The dark purple every screenshot is set on.
@MainActor
enum Palette {
    static let paper = color(0xFFFFFF)

    static let nocturne = Theme(stops: [(color(0x120C2C), 0), (color(0x44307E), 1)], text: paper)
}
