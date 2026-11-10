import SwiftUI

/// Chooses whether the previous and next buttons change tracks or skip within the file, for use in menus.
struct SkipButtonModePicker: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    var body: some View {
        @Bindable var mediaPlayer = mediaPlayer
        Picker(selection: $mediaPlayer.skipButtonMode) {
            Text("SkipButtons.Automatic")
                .tag(SkipButtonMode.automatic)
            Text("SkipButtons.Tracks")
                .tag(SkipButtonMode.tracks)
            Text("SkipButtons.FifteenSeconds")
                .tag(SkipButtonMode.fifteenSeconds)
        } label: {
            Label("SkipButtons.Title", systemImage: "goforward.15")
        }
        .pickerStyle(.menu)
    }
}
