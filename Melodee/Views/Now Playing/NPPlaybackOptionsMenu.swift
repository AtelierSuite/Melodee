import SwiftUI

/// Changes tracks from a visible control, since the previous and next buttons may skip within
/// the file instead, and chooses what those buttons do.
struct NPPlaybackOptionsMenu: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    var body: some View {
        Menu {
            Section {
                Button {
                    withAnimation(.default.speed(2)) {
                        mediaPlayer.backToPreviousTrack()
                    }
                } label: {
                    Label("NowPlaying.PreviousTrack", systemImage: "backward.end")
                }
                .disabled(!mediaPlayer.canGoToPreviousTrack())
                Button {
                    withAnimation(.default.speed(2)) {
                        mediaPlayer.skipToNextTrack()
                    }
                } label: {
                    Label("NowPlaying.NextTrack", systemImage: "forward.end")
                }
                .disabled(!mediaPlayer.canGoToNextTrack())
            }
            Section {
                SkipButtonModePicker()
            }
        } label: {
            Image(systemName: "ellipsis")
                .resizable()
                .scaledToFit()
                .padding(2.0)
                .frame(width: 24.0, height: 24.0)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("NowPlaying.PlaybackOptions")
        .disabled(!mediaPlayer.isPlaybackActive)
    }
}
