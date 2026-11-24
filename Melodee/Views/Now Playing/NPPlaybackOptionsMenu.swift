import SwiftUI

/// Opens the equalizer, and chooses whether the previous and next buttons change tracks or skip within the file.
struct NPPlaybackOptionsMenu: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    @State private var isEqualizerPresented: Bool = false

    var body: some View {
        Menu {
            Button("Equalizer", systemImage: "slider.vertical.3") {
                isEqualizerPresented = true
            }
            SkipButtonModePicker()
                .pickerStyle(.inline)
                .labelsVisibility(.visible)
            if mediaPlayer.isCurrentlyPlayingVideo() {
                Menu {
                    NPSubtitleMenuContent()
                } label: {
                    Label("Subtitles.MenuTitle", systemImage: "captions.bubble")
                }
            }
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
        .sheet(isPresented: $isEqualizerPresented) {
            NPEqualizerSheet()
        }
    }
}
