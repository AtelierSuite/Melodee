import SwiftUI

/// Chooses how fast playback is, with a gauge that shows whether it's slower, normal or faster.
struct NPPlaybackSpeedMenu: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    var body: some View {
        @Bindable var mediaPlayer = mediaPlayer
        Menu {
            Picker("NowPlaying.PlaybackSpeed", selection: $mediaPlayer.playbackSpeed) {
                ForEach(PlaybackSpeed.options, id: \.self) { speed in
                    Text(verbatim: PlaybackSpeed.label(for: speed))
                        .tag(speed)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: gaugeSymbol)
                .resizable()
                .scaledToFit()
                .padding(2.0)
                .frame(width: 24.0, height: 24.0)
                .contentTransition(.symbolEffect(.replace))
                // A menu is tapped within its own frame, so the label takes the whole 44 point square
                .frame(width: 44.0, height: 44.0)
                .contentShape(Rectangle())
        }
        // Without taking up more room than the icon
        .padding(-10.0)
        .foregroundStyle(.primary)
        .accessibilityLabel("NowPlaying.PlaybackSpeed")
        .accessibilityValue(Text(verbatim: PlaybackSpeed.label(for: mediaPlayer.playbackSpeed)))
    }

    private var gaugeSymbol: String {
        if mediaPlayer.playbackSpeed < PlaybackSpeed.normal {
            "gauge.with.dots.needle.33percent"
        } else if mediaPlayer.playbackSpeed > PlaybackSpeed.normal {
            "gauge.with.dots.needle.67percent"
        } else {
            "gauge.with.dots.needle.50percent"
        }
    }
}
