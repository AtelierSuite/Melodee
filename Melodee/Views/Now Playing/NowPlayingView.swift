import SwiftUI

/// Where Now Playing is shown.
enum NowPlayingPresentation {
    /// In a sheet over the file browser.
    case sheet
    /// In a column beside the file browser.
    case column
    /// Over the whole window, in place of the column beside the file browser.
    case fullScreen
}

struct NowPlayingView: View {

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(MediaPlayerManager.self) var mediaPlayer

    @State var albumArt: Image = Image("Album.Generic")
    @State var previousQueueID: String = ""
    @State var listSize: CGSize = .zero
    @State var isVideoFullScreen: Bool = false
    @State var videoFrame = NPScreenFrameReference()
    @AppStorage(NPAdditionalControls.isExpandedKey) var isAdditionalControlsExpanded: Bool = false

    /// Where Now Playing is shown, which decides how much room the artwork has.
    var presentation: NowPlayingPresentation = .sheet

    static let topPadding: CGFloat = 28.0
    static let rowInset: CGFloat = 32.0
    // Height kept free for the top padding, seek bar and playback controls, when the track
    // details sit beside the artwork.
    static let besideDetailsReservedHeight: CGFloat = 186.0
    // Height kept free for the top padding and the controller section's own padding, when the
    // artwork runs down the side.
    static let besideControlsReservedHeight: CGFloat = 68.0
    static let minimumArtworkSize: CGFloat = 96.0

    // On short screens such as iPhone in landscape, and when Now Playing fills the screen
    // beside nothing else, lay the artwork out beside the controls so it can be sized to the
    // height instead of being squeezed above them.
    var controllerLayout: NPControllerLayout {
        guard listSize.height > 0 else { return .stacked }
        let contentWidth = listSize.width - Self.rowInset * 2
        switch presentation {
        case .column where verticalSizeClass == .compact:
            // The column is narrow, so the artwork takes most of its width and the track
            // details get the rest, with the seek bar and controls below them.
            let reservedHeight = Self.besideDetailsReservedHeight +
                (isAdditionalControlsExpanded ? NPAdditionalControls.height : 0.0)
            let size = min(listSize.height - reservedHeight, contentWidth * 0.6)
            return .artworkBesideDetails(artworkSize: max(size, Self.minimumArtworkSize))
        case .sheet where verticalSizeClass == .compact, .fullScreen:
            // There is room across, so the artwork runs down the whole left side.
            let size = min(listSize.height - Self.besideControlsReservedHeight, contentWidth * 0.5)
            return .artworkBesideControls(artworkSize: max(size, Self.minimumArtworkSize))
        default:
            return .stacked
        }
    }

    var body: some View {
        List {
            Group {
                NPControllerSection(albumArt: $albumArt, layout: controllerLayout,
                                    topPadding: presentation == .sheet ? Self.topPadding : 0.0,
                                    isVideoFullScreen: $isVideoFullScreen, videoFrame: videoFrame)
                    .listRowSeparator(.hidden)
                NPQueueSection()
                    .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                        return dimensions.width
                    }
            }
            .listRowInsets(.init(top: 0.0, leading: Self.rowInset, bottom: 0.0, trailing: Self.rowInset))
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            listSize = size
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .resumePlaybackAlert(for: .queue)
        .fullScreenCover(isPresented: $isVideoFullScreen) {
            NPFullScreenVideo(sourceFrame: videoFrame) {
                NPControllerSection.setVideoFullScreen(false, $isVideoFullScreen, mediaPlayer: mediaPlayer)
            }
            .environment(mediaPlayer)
        }
        .background {
            // The artwork is laid out as an overlay so its size can't widen the background past
            // this view, which matters when Now Playing sits in a column beside the file browser.
            Group {
                switch colorScheme {
                case .light: Color.white
                case .dark: Color.black
                @unknown default: Color.black
                }
            }
            .overlay {
                albumArt
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 64.0)
                    .opacity(0.3)
            }
            .clipped()
            .ignoresSafeArea()
        }
        .task {
            if previousQueueID != mediaPlayer.currentlyPlayingID {
                setAlbumArt()
                previousQueueID = mediaPlayer.currentlyPlayingID
            }
        }
        .onChange(of: mediaPlayer.currentlyPlayingID, { _, _ in
            Task {
                setAlbumArt()
                previousQueueID = mediaPlayer.currentlyPlayingID
            }
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
}
