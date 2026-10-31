import SwiftUI

struct FBPdfFileRow: View {

    @State var file: FSFile
    var layout: FileBrowserLayout = .list

    var body: some View {
        NavigationLink(value: ViewPath.pdfViewer(file: file)) {
            FBFileLabel(file: file, layout: layout)
        }
        .navigationLinkIndicatorVisibility(.hidden)
    }
}
