import SwiftUI

/// The controls shown below the playback controls when they're expanded: repeat, shuffle, stop,
/// and the playback options.
struct NPAdditionalControls: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    @State private var isStopConfirming: Bool = false
    @State private var shuffles: Int = 0

    /// Remembers whether the controls were showing, so Now Playing reopens with them.
    static let isExpandedKey = "NowPlaying.ShowsAdditionalControls"
    /// The height the controls add below the playback controls, including the spacing above them.
    static let height: CGFloat = 60.0

    var body: some View {
        HStack(alignment: .center) {
            repeatButton
            Spacer()
            controlButton(systemImage: "shuffle", label: "NowPlaying.ShuffleUpNext") {
                withAnimation(.default.speed(2)) {
                    mediaPlayer.shuffleUpcomingTracks()
                }
                shuffles += 1
            }
            .disabled(!mediaPlayer.canShuffleUpcomingTracks())
            .sensoryFeedback(.impact(weight: .light), trigger: shuffles)
            Spacer()
            // Stopping also empties the queue, so it's confirmed first
            // A filled square looks bigger than the line icons at the same size, so it's inset further
            controlButton(systemImage: "stop.fill", label: "NowPlaying.Stop", inset: 5.0) {
                isStopConfirming = true
            }
            .foregroundStyle(.red)
            .disabled(mediaPlayer.queue.isEmpty)
            .confirmationDialog("NowPlaying.Stop", isPresented: $isStopConfirming) {
                Button("NowPlaying.Stop", role: .destructive) {
                    withAnimation(.default.speed(2)) {
                        mediaPlayer.stop()
                    }
                }
            } message: {
                Text("NowPlaying.Stop.Message")
            }
            Spacer()
            NPPlaybackOptionsMenu()
        }
        .padding(.horizontal, 20.0)
        .padding(.vertical, 10.0)
        .glassEffect(.clear.interactive(), in: .capsule)
        .buttonStyle(DimsWhenDisabled())
        .foregroundStyle(.primary)
        .disabled(!mediaPlayer.isPlaybackActive)
    }

    private func controlButton(systemImage: String, label: LocalizedStringKey, inset: CGFloat = 2.0,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .resizable()
                .scaledToFit()
                .padding(inset)
                .frame(width: 24.0, height: 24.0)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private var repeatButton: some View {
        Button {
            withAnimation(.default.speed(2)) {
                switch mediaPlayer.repeatMode {
                case .none: mediaPlayer.repeatMode = .single
                case .single: mediaPlayer.repeatMode = .all
                case .all: mediaPlayer.repeatMode = .none
                }
            }
        } label: {
            Image(systemName: mediaPlayer.repeatMode == .single ? "repeat.1" : "repeat")
                .resizable()
                .scaledToFit()
                .padding(2.0)
                .frame(width: 24.0, height: 24.0)
                .opacity(mediaPlayer.repeatMode == .none ? 0.5 : 1.0)
        }
        .accessibilityLabel("NowPlaying.Repeat")
        .accessibilityValue(repeatModeDescription)
    }

    private var repeatModeDescription: Text {
        switch mediaPlayer.repeatMode {
        case .none: Text("NowPlaying.Repeat.Off")
        case .single: Text("NowPlaying.Repeat.One")
        case .all: Text("NowPlaying.Repeat.All")
        }
    }
}

/// Fades buttons that can't be used, which borderless buttons tinted with the primary color don't do.
private struct DimsWhenDisabled: ButtonStyle {

    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1.0) : 0.3)
    }
}

/// Shows and hides the additional controls below the playback controls.
struct NPAdditionalControlsToggle: View {

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.25)) {
                isExpanded.toggle()
            }
        } label: {
            // Turns over to point up while the controls are showing
            Image(systemName: "chevron.down")
                .resizable()
                .scaledToFit()
                .padding(4.0)
                .frame(width: 24.0, height: 24.0)
                .rotationEffect(.degrees(isExpanded ? 180.0 : 0.0))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .accessibilityLabel(isExpanded ? "NowPlaying.HideMoreControls" : "NowPlaying.ShowMoreControls")
    }
}

/// Brings the additional controls out from under the toggle at the trailing end of the playback controls,
/// growing, fading and coming into focus. With Reduce Motion, they only fade.
struct NPAdditionalControlsTransition: Transition {

    var reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        if reduceMotion {
            content
                .opacity(phase.isIdentity ? 1.0 : 0.0)
        } else {
            content
                .scaleEffect(phase.isIdentity ? 1.0 : 0.6, anchor: .topTrailing)
                .offset(y: phase.isIdentity ? 0.0 : -16.0)
                .blur(radius: phase.isIdentity ? 0.0 : 6.0)
                .opacity(phase.isIdentity ? 1.0 : 0.0)
        }
    }
}
