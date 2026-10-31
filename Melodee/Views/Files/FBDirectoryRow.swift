import SwiftUI

struct FBDirectoryRow: View {

    @State var directory: FSDirectory
    var storageLocation: StorageLocation
    var layout: FileBrowserLayout = .list

    var body: some View {
        NavigationLink(value: ViewPath.fileBrowser(directory: directory, storageLocation: storageLocation)) {
            switch layout {
            case .list: ListFolderRow(name: directory.name)
            case .grid: GridFolderCell(name: directory.name)
            }
        }
    }
}
