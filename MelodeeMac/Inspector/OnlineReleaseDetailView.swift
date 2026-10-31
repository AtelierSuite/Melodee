//
//  OnlineReleaseDetailView.swift
//  Melodee
//

import PreludeLookup
import SwiftUI

/// Shows how an online release's tracks match the files, and applies the chosen fields.
struct OnlineReleaseDetailView: View {

    @Environment(\.dismiss) private var dismiss

    let release: OnlineRelease
    let files: [FSFile]
    /// Track IDs recognized for each file, by path.
    let identifiers: [String: Set<String>]
    let onBack: () -> Void
    let onApply: () -> Void

    @AppStorage("OnlineLookup.Fields") private var storedFields: String =
        LookupField.defaultFields.map(\.rawValue).sorted().joined(separator: ",")
    @State private var detail: OnlineReleaseDetail?
    @State private var matches: [LookupMatch] = []
    @State private var isLoading = true
    @State private var isApplying = false
    @State private var isShowingApplyError = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    releaseHeader
                }
                if let detail {
                    Section {
                        ForEach($matches) { $match in
                            LookupMatchPicker(match: $match, tracks: detail.tracks)
                        }
                    } header: {
                        Text(MacText.shared("OnlineLookup.Matches"))
                    } footer: {
                        Text(MacText.string("Inspector.LookupMatches.Footer"))
                    }
                    Section(MacText.shared("OnlineLookup.Fields")) {
                        ForEach(LookupField.allCases.filter { $0.isAvailable(in: detail) }) { field in
                            Toggle(String(localized: field.name), isOn: binding(for: field))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .overlay {
                if isLoading {
                    ProgressView()
                } else if detail == nil {
                    ContentUnavailableView(MacText.shared("OnlineLookup.LoadFailed"),
                                           systemImage: "wifi.exclamationmark")
                }
            }
            .disabled(isApplying)
            actionBar
        }
        .alert(MacText.shared("TagEditor.SaveFailed.Message"), isPresented: $isShowingApplyError) {
            Button(MacText.shared("Shared.OK"), role: .cancel) { }
        }
        .task {
            await load()
        }
    }

    private var releaseHeader: some View {
        HStack(spacing: 16) {
            OnlineArtwork(url: (detail?.release ?? release).thumbnailURL)
                .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: release.title)
                    .font(.headline)
                    .lineLimit(3)
                Text(verbatim: release.artist)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String? {
        let parts = [release.year, detail?.genre, release.source.name].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var actionBar: some View {
        SheetActionBar {
            Button {
                onBack()
            } label: {
                Label(MacText.string("Toolbar.Back"), systemImage: "chevron.left")
            }
            .disabled(isApplying)
            Spacer()
            if isApplying {
                ProgressView()
                    .controlSize(.small)
            }
            Button(MacText.shared("Shared.Cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isApplying)
            Button(MacText.shared("OnlineLookup.Apply")) {
                Task { await apply() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(detail == nil || isApplying || selectedFields.isEmpty || !matches.contains { $0.trackID != nil })
        }
    }

    private var selectedFields: Set<LookupField> {
        let fields = Set(storedFields.split(separator: ",").compactMap { LookupField(rawValue: String($0)) })
        guard let detail else { return fields }
        return fields.filter { $0.isAvailable(in: detail) }
    }

    private func binding(for field: LookupField) -> Binding<Bool> {
        Binding {
            storedFields.split(separator: ",").contains { $0 == field.rawValue }
        } set: { isOn in
            var fields = Set(storedFields.split(separator: ",").map(String.init))
            if isOn {
                fields.insert(field.rawValue)
            } else {
                fields.remove(field.rawValue)
            }
            storedFields = fields.sorted().joined(separator: ",")
        }
    }

    private func load() async {
        guard detail == nil else { return }
        isLoading = true
        async let fileMatches = LookupMatch.read(paths: files.map(\.path))
        do {
            let loaded = try await release.source.detail(for: release)
            matches = LookupMatch.matched(await fileMatches, to: loaded.tracks, identifiers: identifiers)
            detail = loaded
        } catch {
            _ = await fileMatches
        }
        isLoading = false
    }

    private func apply() async {
        guard let detail else { return }
        isApplying = true
        let fields = selectedFields
        var albumArt: Data?
        if fields.contains(.albumArt), let url = detail.release.artworkURL {
            albumArt = try? await LookupSource.data(from: url)
        }
        let artwork = albumArt
        let tracks = Dictionary(uniqueKeysWithValues: detail.tracks.map { ($0.id, $0) })
        let pairs = matches.compactMap { match in
            match.trackID.flatMap { tracks[$0] }.map { (match.path, $0) }
        }
        let allApplied = await Task.detached(priority: .userInitiated) {
            pairs.map { path, track in
                detail.apply(track, fields: fields, albumArt: artwork, toFileAt: path)
            }
            .allSatisfy { $0 }
        }.value
        isApplying = false
        if allApplied {
            onApply()
        } else {
            isShowingApplyError = true
        }
    }
}

/// Chooses which of the release's tracks a file is written as.
private struct LookupMatchPicker: View {

    @Binding var match: LookupMatch
    let tracks: [OnlineTrack]

    var body: some View {
        Picker(selection: $match.trackID) {
            Text(MacText.shared("BatchEdit.DontChange"))
                .tag(OnlineTrack.ID?.none)
            if hasMultipleDiscs {
                // Each disc gets its own section, so long albums stay easy to scan
                ForEach(discs, id: \.self) { disc in
                    Section(String(localized: "OnlineLookup.Disc \(disc) \(discs.count)")) {
                        trackOptions(tracks.filter { $0.disc == disc })
                    }
                }
            } else {
                trackOptions(tracks)
            }
        } label: {
            Text(verbatim: match.filename)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(match.filename)
        }
    }

    private var discs: [Int] {
        Array(Set(tracks.map(\.disc))).sorted()
    }

    private var hasMultipleDiscs: Bool {
        discs.count > 1
    }

    private func trackOptions(_ tracks: [OnlineTrack]) -> some View {
        ForEach(tracks) { track in
            Text(verbatim: "\(track.number). \(track.title)")
                .tag(OnlineTrack.ID?.some(track.id))
        }
    }
}
