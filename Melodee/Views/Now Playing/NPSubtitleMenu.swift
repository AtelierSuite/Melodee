import SwiftUI

/// Menu items listing Off, every available subtitle or lyrics track, and an optional action to open the editor.
struct NPSubtitleMenuContent: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    var onOpenEditor: (() -> Void)? = nil

    var body: some View {
        let controller = mediaPlayer.subtitleController
        let subtitles = controller.availableTracks.filter { !$0.isLyrics }
        let lyrics = controller.availableTracks.filter(\.isLyrics)

        Button {
            controller.selectTrack(nil)
        } label: {
            if controller.selectedTrackID == nil {
                Label("Subtitles.Off", systemImage: "checkmark")
            } else {
                Text("Subtitles.Off")
            }
        }

        if !subtitles.isEmpty {
            Section("Subtitles.Section.Subtitles") {
                ForEach(subtitles) { track in
                    trackButton(track, isSelected: controller.selectedTrackID == track.id)
                }
            }
        }

        if !lyrics.isEmpty {
            Section("Subtitles.Section.Lyrics") {
                ForEach(lyrics) { track in
                    trackButton(track, isSelected: controller.selectedTrackID == track.id)
                }
            }
        }

        if let onOpenEditor {
            Divider()
            Button {
                onOpenEditor()
            } label: {
                Label("SubtitleEditor.Open", systemImage: "captions.bubble")
            }
        }
    }

    @ViewBuilder
    private func trackButton(_ track: VideoSubtitleTrack, isSelected: Bool) -> some View {
        Button {
            mediaPlayer.subtitleController.selectTrack(track.id)
        } label: {
            if isSelected {
                Label(track.title, systemImage: "checkmark")
            } else {
                Text(verbatim: track.title)
            }
        }
    }
}

/// Round glass subtitle & lyrics menu button shown in video overlays (inline Now Playing and full screen).
struct NPSubtitleOverlayButton: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    var size: NPVideoOverlayButton.Size = .regular
    var controls: NPVideoControlsContext? = nil
    var onOpenEditor: (() -> Void)? = nil

    private var isActive: Bool {
        mediaPlayer.subtitleController.selectedTrackID != nil
    }

    var body: some View {
        Menu {
            NPSubtitleMenuContent(onOpenEditor: onOpenEditor)
        } label: {
            Image(systemName: isActive ? "captions.bubble.fill" : "captions.bubble")
                .font(.system(size: size.symbolSize, weight: .semibold))
                .frame(width: size.labelSize, height: size.labelSize)
        }
        .buttonStyle(.glass(.clear))
        .buttonBorderShape(.circle)
        .foregroundStyle(.white)
        .padding(10.0)
        .accessibilityLabel(String(localized: "Subtitles.MenuTitle"))
        .onTapGesture {
            controls?.keepShowing()
        }
    }
}
