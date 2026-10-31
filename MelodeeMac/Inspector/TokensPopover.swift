//
//  TokensPopover.swift
//  Melodee
//

import AppKit
import SwiftUI

struct TokensPopover: View {

    private let tokens: [(name: String, descriptionKey: String)] = [
        ("FILENAME", "TagEditor.Tokens.Filename.Description"),
        ("FOLDERNAME", "TagEditor.Tokens.FolderName.Description"),
        ("DASHFRONT", "TagEditor.Tokens.DashFront.Description"),
        ("DASHBACK", "TagEditor.Tokens.DashBack.Description"),
        ("DOTFRONT", "TagEditor.Tokens.DotFront.Description"),
        ("DOTBACK", "TagEditor.Tokens.DotBack.Description"),
        ("TRACKNUMBER", "TagEditor.Tokens.TrackNumber.Description")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(MacText.shared("TagEditor.Tokens.Title"))
                .font(.headline)
            ForEach(tokens, id: \.name) { token in
                TokenRow(name: token.name, descriptionKey: token.descriptionKey)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

private struct TokenRow: View {

    let name: String
    let descriptionKey: String
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "%\(name)%")
                    .font(.body.monospaced().bold())
                    .textSelection(.enabled)
                Text(MacText.shared(descriptionKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("%\(name)%", forType: .string)
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(didCopy ? .green : .accentColor)
            }
            .buttonStyle(.borderless)
            .help(MacText.shared("Shared.Copy"))
        }
    }
}
