import SwiftUI

struct FBZipFileRow: View {

    @Environment(FilesystemManager.self) var fileManager

    @State var file: FSFile
    var layout: FileBrowserLayout = .list
    @State var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            FBFileLabel(file: file, layout: layout)
        }
    }
}
