import SwiftUI

struct FBVideoFileRow: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    @State var file: FSFile
    var layout: FileBrowserLayout = .list

    var body: some View {
        Button {
            mediaPlayer.playImmediately(file)
        } label: {
            FBFileLabel(file: file, layout: layout)
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
}
