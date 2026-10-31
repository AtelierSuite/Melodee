import SwiftUI

struct FBTextFileRow: View {

    @State var file: FSFile
    var layout: FileBrowserLayout = .list

    var body: some View {
        NavigationLink(value: ViewPath.textViewer(file: file)) {
            FBFileLabel(file: file, layout: layout)
        }
    }
}
