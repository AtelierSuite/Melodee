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
