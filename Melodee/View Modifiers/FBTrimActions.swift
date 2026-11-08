import SwiftUI

/// Presents the trimmer, pastes a copied trim onto several files, and restores originals, for the file browser.
struct FileBrowserTrimActions: ViewModifier {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    @Binding var state: FBState
    var refreshFiles: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $state.trimPresentation) { presentation in
                TrimmerView(file: presentation.file, onChange: refreshFiles)
            }
            .confirmationDialog(
                pasteTrimTitle,
                isPresented: $state.isPasteTrimConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Trim.Paste.FromEnd") {
                    pasteTrim(anchor: .endOfFile)
                }
                Button("Trim.Paste.KeepLength") {
                    pasteTrim(anchor: .keptLength)
                }
                Button("Shared.Cancel", role: .cancel) {
                    state.pasteTrimFiles = []
                }
            }
            .confirmationDialog(
                "Trim.Restore",
                isPresented: $state.isRestoreConfirmationPresented,
                titleVisibility: .visible,
                presenting: state.fileBeingRestored
            ) { file in
                Button("Trim.Restore", role: .destructive) {
                    restoreOriginal(of: file)
                }
            } message: { file in
                Text("Trim.Restore.Message.\(file.name)")
            }
            .alert("Trim.Error.Title", isPresented: Binding(get: { state.trimAlertMessage != nil },
                                                             set: { if !$0 { state.trimAlertMessage = nil } })) {
                Button("Shared.OK", role: .cancel) { }
            } message: {
                Text(verbatim: state.trimAlertMessage ?? "")
            }
    }

    var pasteTrimTitle: Text {
        if let sourceName = CopiedTrim.clipboard?.sourceName {
            return Text("Trim.Paste.Title.\(sourceName)")
        }
        return Text("Trim.Paste")
    }

    func restoreOriginal(of file: FSFile) {
        do {
            try MediaTrimmer.restoreOriginal(of: file)
            mediaPlayer.fileDidChangeOnDisk(atPath: file.path)
        } catch {
            state.trimAlertMessage = error.localizedDescription
        }
        state.fileBeingRestored = nil
        refreshFiles()
    }

    /// Trims each file with the copied trim, one after another, showing the conversion progress alert.
    func pasteTrim(anchor: CopiedTrim.Anchor) {
        guard let trim = CopiedTrim.clipboard else { return }
        let files = state.pasteTrimFiles
        state.pasteTrimFiles = []
        guard !files.isEmpty else { return }
        state.conversionTitle = "Trim.Saving"
        state.conversionProgress = 0
        state.isConverting = true

        Task {
            var skippedCount = 0
            var failures: [String] = []
            for (index, file) in files.enumerated() {
                guard let duration = try? await MediaTrimmer.originalDuration(of: file),
                      let range = trim.range(forDuration: duration, anchor: anchor) else {
                    skippedCount += 1
                    continue
                }
                do {
                    try await MediaTrimmer.trim(file, to: range) { value in
                        Task { @MainActor in
                            state.conversionProgress = (Double(index) + value) / Double(files.count)
                        }
                    }
                    mediaPlayer.fileDidChangeOnDisk(atPath: file.path)
                } catch {
                    failures.append("\(file.name): \(error.localizedDescription)")
                }
                state.conversionProgress = Double(index + 1) / Double(files.count)
            }
            state.isConverting = false
            refreshFiles()

            var messages: [String] = []
            if skippedCount > 0 {
                messages.append(String(localized: "Trim.Paste.Skipped.\(skippedCount)"))
            }
            messages.append(contentsOf: failures)
            if !messages.isEmpty {
                state.trimAlertMessage = messages.joined(separator: "\n")
            }
        }
    }
}

extension View {
    func fileBrowserTrimActions(state: Binding<FBState>, refreshFiles: @escaping () -> Void) -> some View {
        modifier(FileBrowserTrimActions(state: state, refreshFiles: refreshFiles))
    }
}
