import SwiftUI

struct NowPlayingView: View {

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(MediaPlayerManager.self) var mediaPlayer

    @State var albumArt: Image = Image("Album.Generic")
    @State var previousQueueID: String = ""
    @State var isClearQueueButtonConfirming: Bool = false
    @State var listHeight: CGFloat = .zero

    // Height kept free for the top padding, track details, seek bar and playback controls.
    static let compactReservedHeight: CGFloat = 280.0
    static let compactMinimumArtworkHeight: CGFloat = 72.0

    // On short screens such as iPhone in landscape, shrink the artwork so the playback
    // controls stay on screen instead of being pushed below it.
    var artworkMaxHeight: CGFloat? {
        guard verticalSizeClass == .compact, listHeight > 0 else { return nil }
        return max(listHeight - Self.compactReservedHeight, Self.compactMinimumArtworkHeight)
    }

    var body: some View {
        List {
            Group {
                NPControllerSection(albumArt: $albumArt, artworkMaxHeight: artworkMaxHeight)
                    .listRowSeparator(.hidden)
                    .padding(.top, 28.0)
                NPQueueSection()
                    .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                        return dimensions.width
                    }
                if !mediaPlayer.queue.isEmpty {
                    Section {
                        Button {
                            withAnimation(.default.speed(2)) {
                                if isClearQueueButtonConfirming {
                                    mediaPlayer.stop()
                                }
                                isClearQueueButtonConfirming.toggle()
                            }
                        } label: {
                            Label(
                                (
                                    isClearQueueButtonConfirming ?
                                    String(localized: "Shared.AreYouSure") :
                                    String(localized: "NowPlaying.ClearQueue")
                                ),
                                systemImage: "eraser.line.dashed"
                            )
                        }
                        .foregroundStyle(.red)
                        .disabled(mediaPlayer.queue.isEmpty)
                        .listRowSeparator(.hidden)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .listRowInsets(.init(top: 0.0, leading: 32.0, bottom: 0.0, trailing: 32.0))
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            listHeight = height
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            isClearQueueButtonConfirming = false
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
