import SwiftUI

struct TagEditorSheet: View {

    @Environment(\.dismiss) var dismiss
    var files: [FSFile]
    @State var showsTokens: Bool = false

    var body: some View {
        NavigationStack {
            TagEditorView(files: files)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("TagEditor.Tokens.Title", systemImage: "curlybraces") {
                            showsTokens = true
                        }
                        .popoverTip(TETokensTip(), arrowEdge: .top)
                        .popover(isPresented: $showsTokens) {
                            List {
                                TEAvailableTokensSection()
                            }
                            .listStyle(.plain)
                            .frame(minWidth: 320.0, idealWidth: 360.0, minHeight: 320.0, idealHeight: 440.0)
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) {
                            dismiss()
                        }
                    }
                }
        }
    }
}

extension View {
    /// Presents the tag editor as a sheet, or full screen in wide windows such as on iPad so it gets the
    /// desktop layout.
    func tagEditorPresentation(_ presentation: Binding<TagEditorPresentation?>) -> some View {
        modifier(TagEditorPresentationModifier(presentation: presentation))
    }
}

struct TagEditorPresentationModifier: ViewModifier {

    @Binding var presentation: TagEditorPresentation?

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var isWide: Bool {
        horizontalSizeClass == .regular
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: isWide ? .constant(nil) : $presentation) { presentation in
                TagEditorSheet(files: presentation.files)
            }
            .fullScreenCover(item: isWide ? $presentation : .constant(nil)) { presentation in
                TagEditorSheet(files: presentation.files)
            }
    }
}
