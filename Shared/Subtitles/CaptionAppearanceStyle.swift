import CoreText
import MediaAccessibility
import SwiftUI

/// System caption appearance resolved from `MediaAccessibility` (`MACaptionAppearance`),
/// with high-contrast defaults that remain legible over both light and dark video frames.
struct CaptionAppearanceStyle: Equatable {

    let foregroundColor: Color
    let backgroundColor: Color
    let textEdgeStyle: MACaptionAppearanceTextEdgeStyle
    let relativeFontScale: CGFloat
    let fontName: String?

    /// Reads the user's current system caption appearance settings.
    static func current() -> CaptionAppearanceStyle {
        let domain: MACaptionAppearanceDomain = .user

        var fgBehavior = MACaptionAppearanceBehavior.useValue
        let fgCG = MACaptionAppearanceCopyForegroundColor(domain, &fgBehavior).takeRetainedValue()
        let fgOpacity = MACaptionAppearanceGetForegroundOpacity(domain, &fgBehavior)
        let foregroundColor = Color(cgColor: fgCG).opacity(fgOpacity > 0 ? fgOpacity : 1.0)

        var bgBehavior = MACaptionAppearanceBehavior.useValue
        let bgCG = MACaptionAppearanceCopyBackgroundColor(domain, &bgBehavior).takeRetainedValue()
        let bgOpacity = MACaptionAppearanceGetBackgroundOpacity(domain, &bgBehavior)
        // Ensure legible backing even if the system default returns fully transparent without edge styling
        var edgeBehavior = MACaptionAppearanceBehavior.useValue
        let edgeStyle = MACaptionAppearanceGetTextEdgeStyle(domain, &edgeBehavior)

        let effectiveBgOpacity: CGFloat
        if bgOpacity > 0.05 {
            effectiveBgOpacity = bgOpacity
        } else if edgeStyle == .none || edgeStyle == .undefined {
            effectiveBgOpacity = 0.68
        } else {
            effectiveBgOpacity = bgOpacity
        }
        let backgroundColor = Color(cgColor: bgCG).opacity(effectiveBgOpacity)

        var sizeBehavior = MACaptionAppearanceBehavior.useValue
        let rawScale = MACaptionAppearanceGetRelativeCharacterSize(domain, &sizeBehavior)
        let relativeFontScale = (rawScale.isFinite && rawScale >= 0.5 && rawScale <= 2.5) ? rawScale : 1.0

        var fontBehavior = MACaptionAppearanceBehavior.useValue
        let descriptor = MACaptionAppearanceCopyFontDescriptorForStyle(domain, &fontBehavior, .default).takeRetainedValue()
        let fontName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String

        return CaptionAppearanceStyle(
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            textEdgeStyle: edgeStyle,
            relativeFontScale: relativeFontScale,
            fontName: fontName
        )
    }

    func font(baseSize: CGFloat, isLyrics: Bool) -> Font {
        let size = max(11, baseSize * relativeFontScale)
        if let fontName, !fontName.isEmpty {
            let base = Font.custom(fontName, size: size)
            return isLyrics ? base.italic() : base
        }
        let base = Font.system(size: size, weight: isLyrics ? .semibold : .medium, design: .rounded)
        return isLyrics ? base.italic() : base
    }
}
