import SwiftUI

struct FBImageFileRow: View {

    @State var file: FSFile
    var layout: FileBrowserLayout = .list

    var body: some View {
        NavigationLink(value: ViewPath.imageViewer(file: file)) {
            FBFileLabel(file: file, layout: layout)
        }
        .navigationLinkIndicatorVisibility(.hidden)
    }
}
