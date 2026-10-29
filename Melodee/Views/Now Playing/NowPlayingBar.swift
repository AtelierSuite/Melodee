import SwiftUI

struct NowPlayingBar: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    @State var albumArt: Image = Image("Album.Generic")
    @State var previousQueueID: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 12.0) {
            albumArt
                .resizable()
                .scaledToFit()
                .frame(height: 32.0)
                .clipShape(RoundedRectangle(cornerRadius: 8.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 8.0)
                        .stroke(.primary, lineWidth: 1/3)
                        .opacity(0.3)
                )
                .shadow(color: .black.opacity(0.1), radius: 10.0)
                .transition(.slide.animation(.default))
            MarqueeText(text: mediaPlayer.currentlyPlayingTitle() ??
                            NSLocalizedString("Shared.NoFilePlaying", comment: ""),
                        font: UIFont.preferredFont(forTextStyle: .subheadline),
                        leftFade: 12, rightFade: 12, startDelay: 1.5)
            .frame(maxWidth: .infinity)
            HStack(alignment: .center, spacing: 8.0) {
                Divider()
                if mediaPlayer.isPaused {
                    Button {
                        withAnimation(.default.speed(2)) {
                            mediaPlayer.play()
                        }
                    } label: {
                        buttonImage(imageName: "Play")
                    }
                } else {
                    Button {
                        withAnimation(.default.speed(2)) {
                            mediaPlayer.pause()
                        }
                    } label: {
                        buttonImage(imageName: "Pause")
                    }
                }
                if mediaPlayer.isPlaybackActive && mediaPlayer.canGoToNextTrack() {
                    Button {
                        withAnimation(.default.speed(2)) {
                            mediaPlayer.skipToNextTrack()
                        }
                    } label: {
                        buttonImage(imageName: "Next")
                    }
                }
            }
            .frame(maxHeight: 32.0)
            .tint(.primary)
            .disabled(!mediaPlayer.canStartPlayback())
        }
        .padding()
        .task {
            if previousQueueID != mediaPlayer.currentlyPlayingID {
                setAlbumArt()
                previousQueueID = mediaPlayer.currentlyPlayingID
            }
        }
        .onChange(of: mediaPlayer.currentlyPlayingID, { _, _ in
            setAlbumArt()
            previousQueueID = mediaPlayer.currentlyPlayingID
        })
        .onChange(of: mediaPlayer.metadataRefreshTrigger, { _, _ in
            setAlbumArt()
        })
    }

    func setAlbumArt() {
        let albumArtUIImage = mediaPlayer.albumArt()
        withAnimation(.default.speed(2)) {
            albumArt = Image(uiImage: albumArtUIImage)
        }
    }

    @ViewBuilder
    func buttonImage(imageName: String) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: 20.0, height: 20.0)
            .padding(8.0)
    }
}
