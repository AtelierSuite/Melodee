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
    /// Whether the video is shown full screen. The full screen video takes the video view while it's shown.
    @State var isVideoFullScreen: Bool = false
    /// Where the video is, for the full screen video to grow out of and shrink back into.
    @State var videoFrame = NPScreenFrameReference()

    let updateTimer = Timer.publish(every: 0.25, on: .current, in: .common).autoconnect()

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
                        NPExtendedVideoSurface(isActive: !isVideoFullScreen)
                    } else {
                        NPVideoSurface(isActive: !isVideoFullScreen)
                    }
                }
                .aspectRatio(mediaPlayer.videoAspectRatio ?? 1.0, contentMode: .fit)
                .background(NPScreenFrameReader(reference: videoFrame))
                .overlay {
                    NPVideoControlsOverlay { controls in
                        HStack(alignment: .top) {
                            if mediaPlayer.supportsVideoPictureInPicture {
                                NPVideoOverlayButton(
                                    systemImage: "pip.enter",
                                    accessibilityLabel: String(localized: "NowPlaying.PictureInPicture")
                                ) {
                                    controls.hide()
                                    mediaPlayer.startVideoPictureInPicture()
                                }
                            }
                            Spacer(minLength: 0.0)
                            NPVideoOverlayButton(
                                systemImage: "arrow.up.left.and.arrow.down.right",
                                accessibilityLabel: String(localized: "NowPlaying.EnterFullScreen")
                            ) {
                                controls.hide()
                                setVideoFullScreen(true)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 16.0)
                        .stroke(.primary, lineWidth: 1/3)
                        .opacity(0.3)
                )
                .animation(.default.speed(2), value: mediaPlayer.videoAspectRatio)
                .fullScreenCover(isPresented: $isVideoFullScreen) {
                    NPFullScreenVideo(sourceFrame: videoFrame) {
                        setVideoFullScreen(false)
                    }
                    .environment(mediaPlayer)
                }
            } else {
                NPArtworkCard(albumArt: albumArt)
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .shadow(color: .black.opacity(0.1), radius: 10.0)
        .transition(.slide.animation(.default))
    }

    /// Shows or hides the full screen video without the system's slide up, as it animates out of the video itself.
    /// The video view moves between the two in the same update, so playback carries on uninterrupted.
    private func setVideoFullScreen(_ isFullScreen: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isVideoFullScreen = isFullScreen
        }
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
                // Holding the previous and next track buttons rewinds and fast forwards instead
                NPTransportButton(imageName: "Back", scrubDirection: .backward) {
                    guard mediaPlayer.canGoToPreviousTrack() else { return }
                    withAnimation(.default.speed(2)) {
                        mediaPlayer.backToPreviousTrack()
                        currentDuration = .zero
                        totalDuration = .zero
                    }
                }
                .foregroundStyle(.primary)
                .disabled(!(mediaPlayer.isPlaybackActive &&
                            (mediaPlayer.canGoToPreviousTrack() || mediaPlayer.supportsSeeking())))
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
                NPTransportButton(imageName: "Next", scrubDirection: .forward) {
                    guard mediaPlayer.canGoToNextTrack() else { return }
                    withAnimation(.default.speed(2)) {
                        mediaPlayer.skipToNextTrack()
                    }
                }
                .foregroundStyle(.primary)
                .disabled(!(mediaPlayer.isPlaybackActive &&
                            (mediaPlayer.canGoToNextTrack() || mediaPlayer.supportsSeeking())))
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
