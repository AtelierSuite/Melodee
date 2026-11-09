import SwiftUI

/// Lets the controls in a `NPVideoControlsOverlay` tell it how they're being used.
struct NPVideoControlsContext {
    /// Hides the controls straight away.
    let hide: () -> Void
    /// Restarts the countdown to hiding the controls, after one of them is used.
    let keepShowing: () -> Void
    /// Keeps the controls up while true, such as while seeking, and restarts the countdown once false.
    let setHeld: (Bool) -> Void
}

/// Sits over the playing video. Tapping the video reveals its controls over a slight darkening.
/// They fade out after 2 seconds, or when the video is tapped again.
/// With VoiceOver on they stay up, as there is no tap to reveal them.
struct NPVideoControlsOverlay<Controls: View>: View {

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) var isVoiceOverEnabled

    /// Whether the controls can be shown, such as not while the full screen video is being swiped away.
    var isEnabled: Bool = true
    /// How much the video is darkened behind the controls.
    var dimming: Double = 0.2
    @ViewBuilder var controls: (NPVideoControlsContext) -> Controls

    @State private var isShowingControls: Bool = false
    @State private var isHeld: Bool = false
    /// Changes whenever the controls are used, to restart the countdown to hiding them.
    @State private var interactionID = UUID()

    var body: some View {
        ZStack {
            // Catches taps on the video, which has no gestures of its own
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    setShowingControls(!isShowingControls)
                }
                .accessibilityHidden(true)
            if isEnabled && (isShowingControls || isVoiceOverEnabled) {
                Color.black.opacity(dimming)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                controls(context)
                    .transition(.opacity)
            }
        }
        .task(id: interactionID) {
            guard isShowingControls, !isHeld else { return }
            // Stay for 2 seconds, then fade out slowly over 1 second
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            setShowingControls(false, animation: .easeInOut(duration: 1.0))
        }
    }

    private var context: NPVideoControlsContext {
        NPVideoControlsContext(
            hide: { setShowingControls(false) },
            keepShowing: { interactionID = UUID() },
            setHeld: { newValue in
                isHeld = newValue
                interactionID = UUID()
            }
        )
    }

    private func setShowingControls(_ newValue: Bool, animation: Animation? = nil) {
        let defaultAnimation: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.25)
        withAnimation(animation ?? defaultAnimation) {
            isShowingControls = newValue
        }
        interactionID = UUID()
    }
}

/// A round glass button over the video, sized and spaced like the visualizer's switch button.
struct NPVideoOverlayButton: View {

    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16.0, weight: .semibold))
                .frame(width: 24.0, height: 24.0)
        }
        .buttonStyle(.glass(.clear))
        .buttonBorderShape(.circle)
        .foregroundStyle(.white)
        .padding(10.0)
        .accessibilityLabel(accessibilityLabel)
    }
}
