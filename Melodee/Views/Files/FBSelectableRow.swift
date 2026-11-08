import SwiftUI

/// A file or folder in the files view while selecting. Tapping toggles the selection instead of opening or playing.
/// Folders can't be selected, since the actions in selection mode only work on files.
struct FBSelectableRow: View {

    var item: any FilesystemObject
    var layout: FileBrowserLayout
    var isSelected: Bool
    var toggleAction: () -> Void

    var isSelectable: Bool {
        item is FSFile
    }

    var body: some View {
        Button(action: toggleAction) {
            switch layout {
            case .list:
                HStack(alignment: .center, spacing: 12.0) {
                    FBSelectionIndicator(isSelected: isSelected)
                    label
                    Spacer(minLength: 0.0)
                }
                .contentShape(.rect)
            case .grid:
                label
                    .overlay(alignment: .topLeading) {
                        FBSelectionIndicator(isSelected: isSelected)
                            .background(.regularMaterial, in: .circle)
                            .padding(6.0)
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        .opacity(isSelectable ? 1.0 : 0.4)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    var label: some View {
        if let file = item as? FSFile {
            FBFileLabel(file: file, layout: layout)
        } else {
            switch layout {
            case .list: ListFolderRow(name: item.name)
            case .grid: GridFolderCell(name: item.name)
            }
        }
    }
}

struct FBSelectionIndicator: View {

    var isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? Color.white : Color.secondary,
                             isSelected ? Color.accentColor : Color.clear)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}
