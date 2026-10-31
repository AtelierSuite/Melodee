import SFBAudioEngine
import SwiftUI

struct FBAudioFileRow: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    @State var file: FSFile
    var layout: FileBrowserLayout = .list
    var sortOption: SortOption = .fileName
    @State var tagSubtitle: String?

    var body: some View {
        Button {
            mediaPlayer.playImmediately(file)
        } label: {
            FBFileLabel(file: file, subtitle: tagSubtitle, layout: layout)
        }
        .task(id: sortOption) {
            // Don't read tags from evicted iCloud files
            let path = file.path
            let evicted = await Task.detached(priority: .utility) {
                FSFile.isEvicted(atPath: path)
            }.value
            guard !evicted else { return }
            tagSubtitle = readTagSubtitle()
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation(.default.speed(2)) {
                    mediaPlayer.queueNext(file: file)
                }
            } label: {
                Label("Shared.Play.Next",
                      systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(.purple)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                withAnimation(.default.speed(2)) {
                    mediaPlayer.queueLast(file: file)
                }
            } label: {
                Label("Shared.Play.Last",
                      systemImage: "text.line.last.and.arrowtriangle.forward")
            }
            .tint(.orange)
        }
    }

    func readTagSubtitle() -> String? {
        guard sortOption != .fileName, file.isTaggableAudio() else {
            return nil
        }
        guard let audioFile = AudioFile.read(for: file) else {
            return nil
        }
        switch sortOption {
        case .fileName:
            return nil
        case .trackTitle:
            let title = audioFile.title ?? ""
            return title.isEmpty ? nil : title
        case .trackNumber:
            return audioFile.trackNumber.map(String.init)
        case .albumName:
            let album = audioFile.albumTitle ?? ""
            return album.isEmpty ? nil : album
        case .artistName:
            let artist = audioFile.artist ?? ""
            return artist.isEmpty ? nil : artist
        }
    }
}
