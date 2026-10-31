import SwiftUI

/// The label for a file in the files view, shown as a list row or a grid cell.
struct FBFileLabel: View {

    var file: FSFile
    var subtitle: String?
    var layout: FileBrowserLayout

    var body: some View {
        switch layout {
        case .list:
            ListFileRow(file: .constant(file), subtitle: subtitle)
                .tint(.primary)
        case .grid:
            GridFileCell(file: file, subtitle: subtitle)
        }
    }
}

