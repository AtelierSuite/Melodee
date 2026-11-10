import SwiftUI

/// A previous or next button that, when held, fast forwards or rewinds through the current file instead.
struct NPTransportButton: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    let image: Image
    let scrubDirection: ScrubDirection
    let action: () -> Void

    /// Set when the press scrubbed, so letting go doesn't also change tracks.
    @State private var didScrub: Bool = false

    var body: some View {
        Button {
            guard !didScrub else {
                didScrub = false
                return
            }
            action()
        } label: {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 24.0, height: 24.0)
                .padding(10.0)
        }
        .buttonStyle(HoldableButtonStyle(onPress: {
            didScrub = false
        }, onHoldChanged: { isHolding in
            if isHolding {
                guard mediaPlayer.supportsSeeking() else { return }
                didScrub = true
                mediaPlayer.beginScrubbing(scrubDirection)
            } else {
                mediaPlayer.endScrubbing()
            }
        }))
    }
}

/// A plain button style that reports when the button has been held down for a moment, and when it is let go.
struct HoldableButtonStyle: ButtonStyle {

    var holdDuration: Duration = .milliseconds(400)
    let onPress: () -> Void
    let onHoldChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        HoldableButtonBody(configuration: configuration,
                           holdDuration: holdDuration,
                           onPress: onPress,
                           onHoldChanged: onHoldChanged)
    }
}

private struct HoldableButtonBody: View {

    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyleConfiguration
    let holdDuration: Duration
    let onPress: () -> Void
    let onHoldChanged: (Bool) -> Void

    @State private var isHolding: Bool = false

    var body: some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1.0) : 0.3)
            .task(id: configuration.isPressed) {
                if configuration.isPressed {
                    onPress()
                    try? await Task.sleep(for: holdDuration)
                    guard !Task.isCancelled, !isHolding else { return }
                    isHolding = true
                    onHoldChanged(true)
                } else if isHolding {
                    isHolding = false
                    onHoldChanged(false)
                }
            }
            .onDisappear {
                if isHolding {
                    isHolding = false
                    onHoldChanged(false)
                }
            }
    }
}
