import SwiftUI

/// The Now Playing artwork, which flips over when tapped to reveal the visualizer on its back.
struct NPArtworkCard: View {

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var albumArt: Image

    /// Remembers which face was showing, so the Now Playing sheet reopens to it.
    @AppStorage(Self.showsVisualizerKey) private var showsVisualizer: Bool = false
    /// Drives the flip. App storage changes don't carry the animation they were made in, so the
    /// flip is animated from this state and the stored value is updated alongside it.
    @State private var isShowingVisualizer: Bool
    /// Whether the visualizer is showing every style to choose from.
    @State private var isChoosingStyle: Bool = false

    private static let showsVisualizerKey = "NowPlaying.ShowsVisualizer"

    init(albumArt: Image) {
        self.albumArt = albumArt
        _isShowingVisualizer = State(initialValue: UserDefaults.standard.bool(forKey: Self.showsVisualizerKey))
    }

    var body: some View {
        // The artwork sizes the card, and both faces are drawn over it at the same size
        albumArt
            .resizable()
            .scaledToFit()
            .hidden()
            .overlay {
                albumArt
                    .resizable()
                    .scaledToFit()
                    .modifier(CardFace())
                    .modifier(FlipRotation(angle: isShowingVisualizer ? 180.0 : 0.0,
                                           isBack: false,
                                           isFlat: reduceMotion))
                    .accessibilityHidden(true)
            }
            .overlay {
                NPVisualizer(albumArt: albumArt,
                             isFaceUp: isShowingVisualizer,
                             isChoosingStyle: $isChoosingStyle)
                    .modifier(CardFace())
                    .modifier(FlipRotation(angle: isShowingVisualizer ? 180.0 : 0.0,
                                           isBack: true,
                                           isFlat: reduceMotion))
                    .accessibilityHidden(!isShowingVisualizer)
            }
            .background {
                // Flips the card for VoiceOver, alongside the visualizer's own controls
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(
                        isShowingVisualizer ?
                        String(localized: "NowPlaying.ShowArtwork") :
                        String(localized: "NowPlaying.ShowVisualizer")
                    )
                    .accessibilityAction {
                        flip()
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16.0))
            .onTapGesture {
                // Taps while choosing a style are for the style picker
                guard !isChoosingStyle else { return }
                flip()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isShowingVisualizer)
            .accessibilityElement(children: .contain)
    }

    private func flip() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.6, bounce: 0.25)) {
            isShowingVisualizer.toggle()
            if !isShowingVisualizer {
                isChoosingStyle = false
            }
        }
        showsVisualizer = isShowingVisualizer
    }
}

/// Rounds a face of the card and outlines it like the rest of the Now Playing artwork.
private struct CardFace: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 16.0))
            .overlay(
                RoundedRectangle(cornerRadius: 16.0)
                    .stroke(.primary, lineWidth: 1/3)
                    .opacity(0.3)
            )
    }
}

/// Turns one face of the card about its vertical axis, showing it only while it faces the user.
///
/// The angle is animated directly, so each face can be swapped in exactly when the card is edge on.
private struct FlipRotation: ViewModifier, Animatable {

    /// 0 when the front faces the user, and 180 when the back does.
    var angle: Double
    let isBack: Bool
    /// Crossfades the faces instead of turning them, for Reduce Motion.
    let isFlat: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let progress = min(max(angle / 180.0, 0.0), 1.0)
        if isFlat {
            content
                .opacity(isBack ? progress : 1.0 - progress)
                // Only the visualizer has controls, and only while it's showing
                .allowsHitTesting(isBack && progress > 0.5)
        } else {
            let isVisible = isBack ? angle >= 90.0 : angle < 90.0
            // Lift the card a little towards the user as it turns
            let lift = 1.0 + 0.08 * sin(progress * .pi)
            content
                .rotation3DEffect(.degrees(isBack ? angle - 180.0 : angle),
                                  axis: (x: 0.0, y: 1.0, z: 0.0),
                                  perspective: 0.4)
                .scaleEffect(lift)
                .opacity(isVisible ? 1.0 : 0.0)
                // Only the visualizer has controls, and only while it's showing
                .allowsHitTesting(isBack && isVisible)
        }
    }
}
