import SwiftUI

struct BatchRenameView: View {

    @Environment(\.dismiss) var dismiss
    @Environment(MediaPlayerManager.self) var mediaPlayer

    var files: [FSFile]
    var scopeRootURL: URL
    var fileManager: FilesystemManager
    var onCompletion: () -> Void

    @State var rules = BatchRenameRules()
    @State var includedTypes: Set<FileType> = []
    @State var excludedPaths: Set<String> = []
    @State var failures: [BatchRenameFailure] = []
    @State var isShowingFailures: Bool = false

    init(files: [FSFile], scopeRootURL: URL, fileManager: FilesystemManager, onCompletion: @escaping () -> Void) {
        self.files = files
        self.scopeRootURL = scopeRootURL
        self.fileManager = fileManager
        self.onCompletion = onCompletion
        self._includedTypes = State(initialValue: Set(files.map(\.type)))
    }

    var availableTypes: [FileType] {
        var seenTypes: Set<FileType> = []
        return files.map(\.type).filter { seenTypes.insert($0).inserted }
    }

    var includedFiles: [FSFile] {
        files.filter { includedTypes.contains($0.type) && !excludedPaths.contains($0.path) }
    }

    var items: [BatchRenameItem] {
        BatchRenamePlanner.plan(files: includedFiles, rules: rules)
    }

    var body: some View {
        let items = items
        let itemsByPath = Dictionary(uniqueKeysWithValues: items.map { ($0.file.path, $0) })
        let renameCount = items.filter { $0.status == .willRename }.count
        let problemCount = items.filter { $0.status.isProblem }.count
        NavigationStack {
            Form {
                ruleSection
                optionsSection
                if availableTypes.count > 1 {
                    Section("BatchRename.FileTypes") {
                        ForEach(availableTypes, id: \.self) { type in
                            Toggle(isOn: typeBinding(for: type)) {
                                Label {
                                    Text(typeName(type))
                                } icon: {
                                    type.icon()
                                        .foregroundStyle(type.iconColor)
                                }
                            }
                        }
                    }
                }
                Section {
                    ForEach(files.filter { includedTypes.contains($0.type) }, id: \.path) { file in
                        previewRow(for: file, item: itemsByPath[file.path])
                    }
                } header: {
                    Text("BatchRename.Preview")
                } footer: {
                    VStack(alignment: .leading, spacing: 4.0) {
                        Text(NSLocalizedString("BatchRename.Summary", comment: "")
                            .replacingOccurrences(of: "%1", with: String(renameCount))
                            .replacingOccurrences(of: "%2", with: String(items.count)))
                        if problemCount > 0 {
                            Text(NSLocalizedString("BatchRename.Summary.Problems", comment: "")
                                .replacingOccurrences(of: "%1", with: String(problemCount)))
                            .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("BatchRename.Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Shared.Rename", systemImage: "checkmark", role: .confirm) {
                        rename(items)
                    }
                    .disabled(renameCount == 0 || problemCount > 0 || rules.isRegularExpressionInvalid)
                }
            }
            .alert("BatchRename.Failed.Title", isPresented: $isShowingFailures) {
                Button("Shared.OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(verbatim: failures.map { "\($0.fileName): \($0.reason)" }.joined(separator: "\n"))
            }
        }
        .interactiveDismissDisabled(renameCount > 0)
    }

    var ruleSection: some View {
        Section {
            Picker("BatchRename.Rule", selection: $rules.mode) {
                Text("BatchRename.Mode.Replace").tag(BatchRenameMode.replace)
                Text("BatchRename.Mode.KeepFront").tag(BatchRenameMode.keepFront)
                Text("BatchRename.Mode.KeepBack").tag(BatchRenameMode.keepBack)
            }
            switch rules.mode {
            case .replace:
                textFieldRow("BatchRename.Find", text: $rules.findText)
                textFieldRow("BatchRename.ReplaceWith", text: $rules.replaceText)
                Toggle("BatchRename.CaseSensitive", isOn: $rules.isCaseSensitive)
                Toggle("BatchRename.RegularExpression", isOn: $rules.isRegularExpression)
            case .keepFront, .keepBack:
                textFieldRow("BatchRename.Delimiter", text: $rules.delimiter)
                Picker("BatchRename.SplitAt", selection: $rules.splitOccurrence) {
                    Text("BatchRename.SplitAt.First").tag(BatchRenameSplitOccurrence.first)
                    Text("BatchRename.SplitAt.Last").tag(BatchRenameSplitOccurrence.last)
                }
            }
        } header: {
            Text("BatchRename.Rule")
        } footer: {
            switch rules.mode {
            case .replace:
                if rules.isRegularExpressionInvalid {
                    Text("BatchRename.InvalidRegularExpression")
                        .foregroundStyle(.red)
                }
            case .keepFront, .keepBack:
                Text("BatchRename.Split.Footer")
            }
        }
    }

    var optionsSection: some View {
        Section("BatchRename.Options") {
            textFieldRow("BatchRename.Prefix", text: $rules.prefix)
            textFieldRow("BatchRename.Suffix", text: $rules.suffix)
            Toggle("BatchRename.TrimWhitespace", isOn: $rules.trimsWhitespace)
            Toggle("BatchRename.Numbering", isOn: $rules.isNumbering)
            if rules.isNumbering {
                Stepper(value: $rules.numberStart, in: 0...99999) {
                    LabeledContent("BatchRename.Numbering.StartAt", value: String(rules.numberStart))
                }
                Stepper(value: $rules.numberDigits, in: 1...6) {
                    LabeledContent("BatchRename.Numbering.Digits", value: String(rules.numberDigits))
                }
                textFieldRow("BatchRename.Numbering.Separator", text: $rules.numberSeparator)
                Picker("BatchRename.Numbering.Position", selection: $rules.numberPosition) {
                    Text("BatchRename.Numbering.Position.Before").tag(BatchRenameNumberPosition.before)
                    Text("BatchRename.Numbering.Position.After").tag(BatchRenameNumberPosition.after)
                }
            }
        }
    }

    func textFieldRow(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(verbatim: ""))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    @ViewBuilder
    func previewRow(for file: FSFile, item: BatchRenameItem?) -> some View {
        let isIncluded = item != nil
        Button {
            if isIncluded {
                excludedPaths.insert(file.path)
            } else {
                excludedPaths.remove(file.path)
            }
        } label: {
            HStack(alignment: .center, spacing: 12.0) {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isIncluded ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2.0) {
                    let oldFileName = URL(filePath: file.path).lastPathComponent
                    if let item, item.status != .unchanged {
                        Text(verbatim: oldFileName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(verbatim: item.newFileName)
                            .foregroundStyle(item.status.isProblem ? .red : .primary)
                        if let message = problemMessage(for: item.status) {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text(verbatim: oldFileName)
                            .foregroundStyle(isIncluded ? .primary : .secondary)
                        if isIncluded {
                            Text("BatchRename.Unchanged")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    func problemMessage(for status: BatchRenameStatus) -> LocalizedStringKey? {
        switch status {
        case .unchanged, .willRename: return nil
        case .empty: return "BatchRename.Problem.Empty"
        case .invalidName: return "BatchRename.Problem.InvalidName"
        case .conflictsWithExistingFile: return "BatchRename.Problem.ConflictsWithExistingFile"
        case .conflictsWithinBatch: return "BatchRename.Problem.ConflictsWithinBatch"
        }
    }

    func typeBinding(for type: FileType) -> Binding<Bool> {
        Binding {
            includedTypes.contains(type)
        } set: { isIncluded in
            if isIncluded {
                includedTypes.insert(type)
            } else {
                includedTypes.remove(type)
            }
        }
    }

    func typeName(_ type: FileType) -> LocalizedStringKey {
        switch type {
        case .audio: return "BatchRename.FileType.Audio"
        case .video: return "BatchRename.FileType.Video"
        case .image: return "BatchRename.FileType.Image"
        case .text: return "BatchRename.FileType.Text"
        case .pdf: return "BatchRename.FileType.PDF"
        case .zip: return "BatchRename.FileType.ZIP"
        case .playlist: return "BatchRename.FileType.Playlist"
        case .notSet: return "BatchRename.FileType.Other"
        }
    }

    func rename(_ items: [BatchRenameItem]) {
        let result = fileManager.batchRename(items)
        if !result.renamedPaths.isEmpty {
            fileManager.updatePlaylists(in: scopeRootURL, renamedPaths: result.renamedPaths)
            mediaPlayer.updateQueuedFilePaths(result.renamedPaths)
        }
        onCompletion()
        if result.failures.isEmpty {
            dismiss()
        } else {
            failures = result.failures
            isShowingFailures = true
        }
    }
}
