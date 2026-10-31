import SwiftUI

struct NPQueueSection: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    var body: some View {
        @Bindable var mediaPlayer = mediaPlayer
        Section {
            if $mediaPlayer.queue.isEmpty {
                Text(verbatim: "")
                    .listRowSeparator(.hidden)
            } else {
                ForEach($mediaPlayer.queue, id: \.playbackQueueID) { $file in
                    Button {
                        mediaPlayer.playImmediately(file, addToQueue: false)
                    } label: {
                        NPQueueRow(
                            file: file,
                            isCurrent: file.playbackQueueID == mediaPlayer.currentlyPlayingID
                        )
                    }
                    .buttonStyle(.plain)
                    .deleteDisabled(file.playbackQueueID == mediaPlayer.currentlyPlayingID)
                }
                .onMove { indexSet, offset in
                    mediaPlayer.queue.move(fromOffsets: indexSet, toOffset: offset)
                }
                .onDelete { indexSet in
                    mediaPlayer.queue.remove(atOffsets: indexSet)
                }
            }
        } header: {
            HStack(alignment: .center, spacing: 8.0) {
                ListSectionHeader(text: "Shared.Queue")
                Spacer()
                EditButton()
                    .bold()
                    .textCase(.none)
                    .disabled(mediaPlayer.queue.isEmpty)
            }
        }
    }
}
