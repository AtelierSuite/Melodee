import SwiftUI

/// Saves, trims and clears the playback queue.
struct NPQueueMenu: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    @Environment(FilesystemManager.self) var fileManager

    @State private var isSavingAsPlaylist: Bool = false
    @State private var playlistName: String = ""
    @State private var isStopConfirming: Bool = false

    var body: some View {
        Menu {
            Button("NowPlaying.Queue.SaveAsPlaylist", systemImage: "music.note.list") {
                playlistName = ""
                isSavingAsPlaylist = true
            }
            .disabled(mediaPlayer.queue.isEmpty)
            Divider()
            Button("NowPlaying.Queue.ClearPlayed") {
                withAnimation(.default.speed(2)) {
                    mediaPlayer.clearPlayedTracks()
                }
            }
            .disabled(!mediaPlayer.canClearPlayedTracks())
            Button("NowPlaying.Queue.ClearUpcoming") {
                withAnimation(.default.speed(2)) {
                    mediaPlayer.clearUpcomingTracks()
                }
            }
            .disabled(!mediaPlayer.canClearUpcomingTracks())
            Divider()
            // Stopping also empties the queue, so it's confirmed first
            Button("NowPlaying.Queue.StopPlayback", systemImage: "stop.fill", role: .destructive) {
                isStopConfirming = true
            }
            .disabled(mediaPlayer.queue.isEmpty)
        } label: {
            Image(systemName: "list.triangle")
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
        .accessibilityLabel("Shared.Queue")
        .disabled(mediaPlayer.queue.isEmpty)
        .confirmationDialog("NowPlaying.Stop", isPresented: $isStopConfirming) {
            Button("NowPlaying.Stop", role: .destructive) {
                withAnimation(.default.speed(2)) {
                    mediaPlayer.stop()
                }
            }
        } message: {
            Text("NowPlaying.Stop.Message")
        }
        .alert("NowPlaying.Queue.SaveAsPlaylist.Title", isPresented: $isSavingAsPlaylist) {
            TextField("Playlists.PlaylistName", text: $playlistName)
            Button("Shared.Cancel", role: .cancel) { }
            Button("Shared.Save") {
                saveAsPlaylist()
            }
            .disabled(trimmedPlaylistName.isEmpty)
        }
    }

    private var trimmedPlaylistName: String {
        playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveAsPlaylist() {
        guard !trimmedPlaylistName.isEmpty else { return }
        let rootDirectoryURLs = [fileManager.documentsDirectoryURL,
                                 fileManager.cloudDocumentsDirectoryURL,
                                 fileManager.externalDirectoryURL].compactMap { $0 }
        mediaPlayer.saveQueueAsPlaylist(named: trimmedPlaylistName, rootDirectoryURLs: rootDirectoryURLs)
    }
}
