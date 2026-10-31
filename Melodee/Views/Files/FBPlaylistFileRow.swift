import SwiftUI

struct FBPlaylistFileRow: View {

    @State var file: FSFile
    var layout: FileBrowserLayout = .list
    var scopeRootURL: URL

    var body: some View {
        NavigationLink(value: ViewPath.playlistViewer(file: file, scopeRootURL: scopeRootURL)) {
            FBFileLabel(file: file, layout: layout)
        }
        .navigationLinkIndicatorVisibility(.hidden)
    }
}
