import SwiftUI

/// Chooses how fast playback is, and whether the previous and next buttons change tracks or skip within the file.
struct NPPlaybackOptionsMenu: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    var body: some View {
        @Bindable var mediaPlayer = mediaPlayer
        Menu {
            // The options are listed in the menu, under each picker's name
            Picker(selection: $mediaPlayer.playbackSpeed) {
                ForEach(PlaybackSpeed.options, id: \.self) { speed in
                    Text(verbatim: PlaybackSpeed.label(for: speed))
                        .tag(speed)
                }
            } label: {
                Label("NowPlaying.PlaybackSpeed", systemImage: "gauge.with.dots.needle.67percent")
            }
            .pickerStyle(.inline)
            .labelsVisibility(.visible)
            SkipButtonModePicker()
                .pickerStyle(.inline)
                .labelsVisibility(.visible)
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
