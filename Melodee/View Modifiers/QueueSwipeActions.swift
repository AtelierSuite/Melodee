import SwiftUI

/// Adds the Play Next and Play Last swipe actions to a file row. Only list rows get them, grid cells don't.
struct QueueSwipeActions: ViewModifier {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    var file: FSFile
    var layout: FileBrowserLayout

    @ViewBuilder
    func body(content: Content) -> some View {
        switch layout {
        case .list:
            content
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
        case .grid:
            content
        }
    }
}

extension View {
    func queueSwipeActions(for file: FSFile, layout: FileBrowserLayout) -> some View {
        modifier(QueueSwipeActions(file: file, layout: layout))
    }
}
