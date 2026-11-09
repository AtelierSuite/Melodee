import SwiftUI

/// Seconds to cut from the start and end of several files at once.
struct BatchTrimCuts: Equatable {
    var startCut: TimeInterval = 0
    var endCut: TimeInterval = 0

    var isEmpty: Bool {
        startCut <= 0 && endCut <= 0
    }

    /// The range kept in a file of `duration` seconds, or nil if the file is too short for these cuts.
    func range(forDuration duration: TimeInterval) -> ClosedRange<TimeInterval>? {
        let start = max(0, startCut)
        let end = duration - max(0, endCut)
        guard end - start >= MediaTrimmer.minimumLength else { return nil }
        return start...end
    }
}

struct BatchTrimPresentation: Identifiable {
    let id = UUID()
    let files: [FSFile]
}

/// Asks how much to cut from the start and end of every selected file.
struct BatchTrimView: View {

    @Environment(\.dismiss) var dismiss

    var fileCount: Int
    var onTrim: (BatchTrimCuts) -> Void

    @State var cuts = BatchTrimCuts()

    var isValid: Bool {
        !cuts.isEmpty && cuts.startCut >= 0 && cuts.endCut >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    secondsRow("Trim.Batch.FromStart", value: $cuts.startCut)
                    secondsRow("Trim.Batch.FromEnd", value: $cuts.endCut)
                } footer: {
                    Text("Trim.Batch.Footer")
                }
            }
            .navigationTitle(Text("Trim.Batch.Title.\(fileCount)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Trim.Action", systemImage: "checkmark", role: .confirm) {
                        onTrim(cuts)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    func secondsRow(_ title: LocalizedStringKey, value: Binding<TimeInterval>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4.0) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                Text("Trim.Batch.Seconds")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
