import MediaAccessibility
import SwiftUI

/// Renders active subtitle cues, synced lyrics, or plain unsynced lyrics over a video surface.
/// Respects the system caption style (`MACaptionAppearance`) and stays legible over bright and dark frames.
struct SubtitleOverlayView: View {

    let text: String?
    var isLyrics: Bool = false
    var unsyncedLyrics: String? = nil
    /// Compact sizing for inline video cards (such as Now Playing on iPhone).
    var isCompact: Bool = false
    /// Extra bottom clearance (for example when controls are visible).
    var bottomPadding: CGFloat = 14.0

    @State private var style = CaptionAppearanceStyle.current()

    var body: some View {
        ZStack(alignment: .bottom) {
            if let unsyncedLyrics, !unsyncedLyrics.isEmpty {
                unsyncedLyricsPanel(unsyncedLyrics)
            } else if let text, !text.isEmpty {
                timedCaptionBanner(text)
                    .padding(.horizontal, isCompact ? 10.0 : 28.0)
                    .padding(.bottom, bottomPadding)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeInOut(duration: 0.14), value: text)
        .onReceive(NotificationCenter.default.publisher(for: kMACaptionAppearanceSettingsChangedNotification as Notification.Name)) { _ in
            style = CaptionAppearanceStyle.current()
        }
    }

    @ViewBuilder
    private func timedCaptionBanner(_ text: String) -> some View {
        let baseSize: CGFloat = isCompact ? 14.0 : 22.0
        let captionText = Text(verbatim: text)
            .font(style.font(baseSize: baseSize, isLyrics: isLyrics))
            .foregroundStyle(style.foregroundColor)
            .multilineTextAlignment(.center)
            .lineSpacing(isCompact ? 2.0 : 4.0)

        styledEdges(captionText)
            .padding(.horizontal, isCompact ? 10.0 : 16.0)
            .padding(.vertical, isCompact ? 5.0 : 8.0)
            .background {
                RoundedRectangle(cornerRadius: isCompact ? 8.0 : 10.0, style: .continuous)
                    .fill(style.backgroundColor)
            }
            .shadow(color: .black.opacity(0.45), radius: 4.0, y: 1.0)
    }

    @ViewBuilder
    private func styledEdges<V: View>(_ content: V) -> some View {
        switch style.textEdgeStyle {
        case .dropShadow:
            content.shadow(color: .black.opacity(0.9), radius: 2.0, x: 1.0, y: 2.0)
        case .uniform:
            content
                .shadow(color: .black, radius: 0.8, x: 1.0, y: 0.0)
                .shadow(color: .black, radius: 0.8, x: -1.0, y: 0.0)
                .shadow(color: .black, radius: 0.8, x: 0.0, y: 1.0)
                .shadow(color: .black, radius: 0.8, x: 0.0, y: -1.0)
        case .raised:
            content.shadow(color: .black.opacity(0.85), radius: 1.0, x: 0.0, y: 2.0)
        case .depressed:
            content.shadow(color: .black.opacity(0.85), radius: 1.0, x: 0.0, y: -1.5)
        default:
            content.shadow(color: .black.opacity(0.75), radius: 2.0, y: 1.0)
        }
    }

    private func unsyncedLyricsPanel(_ lyrics: String) -> some View {
        ScrollView {
            Text(verbatim: lyrics)
                .font(style.font(baseSize: isCompact ? 13.0 : 16.0, isLyrics: true))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(isCompact ? 12.0 : 20.0)
        }
        .frame(maxWidth: isCompact ? .infinity : 540.0)
        .frame(maxHeight: isCompact ? 120.0 : 240.0)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12.0, style: .continuous))
        .padding(.horizontal, isCompact ? 10.0 : 24.0)
        .padding(.bottom, bottomPadding)
    }
}
