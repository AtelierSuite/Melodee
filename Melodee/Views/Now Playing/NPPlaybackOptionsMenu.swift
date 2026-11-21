import SwiftUI

/// Chooses whether the previous and next buttons change tracks or skip within the file.
struct NPPlaybackOptionsMenu: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    var body: some View {
        Menu {
            SkipButtonModePicker()
                .pickerStyle(.inline)
                .labelsVisibility(.visible)
        } label: {
            Image(systemName: "ellipsis")
                .resizable()
                .scaledToFit()
                .padding(2.0)
                .frame(width: 24.0, height: 24.0)
                // A menu is tapped within its own frame, so the label takes the whole 44 point square
                .frame(width: 44.0, height: 44.0)
                .contentShape(Rectangle())
        }
        // Without taking up more room than the icon
        .padding(-10.0)
        .foregroundStyle(.primary)
        .accessibilityLabel("NowPlaying.PlaybackOptions")
        .disabled(!mediaPlayer.isPlaybackActive)
    }
}
