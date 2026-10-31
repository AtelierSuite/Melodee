import SwiftUI

struct FBAudioFileRow: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    @State var file: FSFile
    var layout: FileBrowserLayout = .list

    var body: some View {
        Button {
            mediaPlayer.playImmediately(file)
        } label: {
            FBFileLabel(file: file, layout: layout)
        }
        .queueSwipeActions(for: file, layout: layout)
    }
}
