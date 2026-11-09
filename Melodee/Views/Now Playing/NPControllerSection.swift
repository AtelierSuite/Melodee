import AVKit
import SwiftUI

/// How the artwork is arranged against the rest of the Now Playing controls.
enum NPControllerLayout: Equatable {
    /// The artwork above the track details, seek bar and playback controls.
    case stacked
    /// The artwork beside the track details, with the seek bar and playback controls below them.
    case artworkBesideDetails(artworkSize: CGFloat)
    /// The artwork down one side, with everything else beside it.
    case artworkBesideControls(artworkSize: CGFloat)
}

struct NPControllerSection: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    @Binding var albumArt: Image
    var layout: NPControllerLayout = .stacked
    @State var currentDuration: TimeInterval = .zero
    @State var totalDuration: TimeInterval = .zero
    @State var isSeekbarSeeking: Bool = false

    let updateTimer = Timer.publish(every: 0.5, on: .current, in: .common).autoconnect()

    var body: some View {
        Section {
            Group {
                switch layout {
                case .stacked:
                    VStack(alignment: .center, spacing: 16.0) {
                        artwork
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4.0)
                        trackDetails
                        seekBar
                        playbackControls
                    }
                case .artworkBesideDetails(let artworkSize):
                    VStack(alignment: .center, spacing: 16.0) {
                        HStack(alignment: .center, spacing: 16.0) {
                            artwork
                                .frame(width: artworkSize, height: artworkSize)
                            trackDetails
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        seekBar
                        playbackControls
                    }
                case .artworkBesideControls(let artworkSize):
                    HStack(alignment: .center, spacing: 32.0) {
                        artwork
                            .frame(width: artworkSize, height: artworkSize)
                        VStack(alignment: .center, spacing: 16.0) {
                            trackDetails
                            seekBar
                            playbackControls
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding([.top, .bottom])
        }
        .onReceive(updateTimer, perform: { _ in
            if !isSeekbarSeeking {
                if mediaPlayer.isPlaybackActive, let time = mediaPlayer.playbackTime() {
                    currentDuration = time.currentTime
                    totalDuration = time.totalTime
                } else {
                    currentDuration = .zero
                    totalDuration = .zero
                }
            }
        })
    }

    var artwork: some View {
        ZStack {
            Color.clear
            if mediaPlayer.isCurrentlyPlayingVideo() {
                Group {
                    if mediaPlayer.activeVideoEngine == .extended {
                        NPExtendedVideoSurface()
                    } else {
                        NPVideoSurface()
                    }
                }
                .aspectRatio(mediaPlayer.videoAspectRatio ?? 1.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 16.0)
                        .stroke(.primary, lineWidth: 1/3)
                        .opacity(0.3)
                )
                .animation(.default.speed(2), value: mediaPlayer.videoAspectRatio)
            } else {
                NPArtworkCard(albumArt: albumArt)
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .shadow(color: .black.opacity(0.1), radius: 10.0)
        .transition(.slide.animation(.default))
    }

    var seekBar: some View {
        MusicProgressSlider(value: $currentDuration,
                            inRange: .zero...totalDuration,
                            activeFillColor: .primary,
                            fillColor: .primary.opacity(0.5),
                            emptyColor: .secondary.opacity(0.5),
                            height: 24) { isEditing in
                                isSeekbarSeeking = isEditing
                                if !isSeekbarSeeking {
                                    mediaPlayer.seekTo(currentDuration)
                                }
                            }
        .frame(maxWidth: .infinity, minHeight: 32)
    }

    var playbackControls: some View {
        HStack(alignment: .center, spacing: 10.0) {
            DevicePickerView()
                .frame(width: 24.0, height: 24.0)
            Spacer()
            Group {
                Button {
                    withAnimation(.default.speed(2)) {
                        mediaPlayer.backToPreviousTrack()
                        currentDuration = .zero
                        totalDuration = .zero
                    }
                } label: {
                    Image("Back")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24.0, height: 24.0)
                        .padding(10.0)
                }
                .foregroundStyle(.primary)
                .disabled(!(mediaPlayer.isPlaybackActive && mediaPlayer.canGoToPreviousTrack()))
                .clipShape(Circle())
                Button {
                    if mediaPlayer.isPaused {
                        mediaPlayer.play()
                    } else {
                        mediaPlayer.pause()
                    }
                } label: {
                    Image(mediaPlayer.isPaused ? "Play" : "Pause")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32.0, height: 32.0)
                        .padding(10.0)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(.primary)
                Button {
                    withAnimation(.default.speed(2)) {
                        mediaPlayer.skipToNextTrack()
                    }
                } label: {
                    Image("Next")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24.0, height: 24.0)
                        .padding(10.0)
                }
                .foregroundStyle(.primary)
                .disabled(!(mediaPlayer.isPlaybackActive && mediaPlayer.canGoToNextTrack()))
                .clipShape(Circle())
            }
            Spacer()
            Button {
                withAnimation(.default.speed(2)) {
                    switch mediaPlayer.repeatMode {
                    case .none: mediaPlayer.repeatMode = .single
                    case .single: mediaPlayer.repeatMode = .all
                    case .all: mediaPlayer.repeatMode = .none
                    }
                }
            } label: {
                Group {
                    switch mediaPlayer.repeatMode {
                    case .none:
                        Image(systemName: "repeat")
                            .resizable()
                            .opacity(0.5)
                    case .single:
                        Image(systemName: "repeat.1")
                            .resizable()
                    case .all:
                        Image(systemName: "repeat")
                            .resizable()
                    }
                }
                .scaledToFit()
                .padding(2.0)
                .frame(width: 24.0, height: 24.0)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(!(mediaPlayer.isPlaybackActive))
        }
        .disabled(!mediaPlayer.canStartPlayback())
        .buttonStyle(.plain)
    }

    var trackDetails: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            MarqueeText(text: mediaPlayer.currentlyPlayingAlbumName() ?? "-",
                        font: UIFont.preferredFont(forTextStyle: .caption1),
                        leftFade: 16, rightFade: 16, startDelay: 1.5)
            MarqueeText(text: mediaPlayer.currentlyPlayingTitle() ??
                        NSLocalizedString("Shared.NoFilePlaying", comment: ""),
                        font: UIFont.preferredFont(forTextStyle: .headline),
                        leftFade: 16, rightFade: 16, startDelay: 1.5)
            MarqueeText(text: mediaPlayer.currentlyPlayingArtistName() ?? "-",
                        font: UIFont.preferredFont(forTextStyle: .body),
                        leftFade: 16, rightFade: 16, startDelay: 1.5)
            .opacity(0.5)
        }
    }
}

struct DevicePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        return AVRoutePickerView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Not implemented
    }
}
