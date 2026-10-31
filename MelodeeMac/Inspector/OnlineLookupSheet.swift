//
//  OnlineLookupSheet.swift
//  Melodee
//

import PreludeLookup
import SwiftUI

/// Finds the album that the files being edited belong to by recognizing their audio,
/// or by looking it up by name if their songs aren't recognized.
struct OnlineLookupSheet: View {

    @Environment(\.dismiss) private var dismiss

    let files: [FSFile]
    let onApply: () -> Void

    @State private var artist: String
    @State private var album: String
    @State private var selectedRelease: OnlineRelease?
    @State private var results: [OnlineRelease] = []
    @State private var identifiers: [String: Set<String>] = [:]
    @State private var isIdentifying = true
    @State private var isSearching = false
    @State private var isShowingSearchError = false
    @State private var isShowingNoMatch = false

    init(files: [FSFile], artist: String, album: String, onApply: @escaping () -> Void) {
        self.files = files
        self.onApply = onApply
        _artist = State(initialValue: artist)
        _album = State(initialValue: album)
    }

    var body: some View {
        ZStack {
            if let selectedRelease {
                OnlineReleaseDetailView(release: selectedRelease, files: files, identifiers: identifiers) {
                    self.selectedRelease = nil
                } onApply: {
                    onApply()
                    dismiss()
                }
            } else {
                resultsView
            }
        }
        .frame(width: 520, height: 580)
        .alert(MacText.shared("OnlineLookup.SearchFailed"), isPresented: $isShowingSearchError) {
            Button(MacText.shared("Shared.OK"), role: .cancel) { }
        }
        .alert(MacText.shared("OnlineLookup.NoMatch"), isPresented: $isShowingNoMatch) {
            Button(MacText.shared("Shared.OK"), role: .cancel) { }
        }
        .task {
            await identify()
        }
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            Form {
                if isIdentifying || isSearching {
                    Section {
                        VStack(spacing: 12) {
                            ProgressView()
                            if isIdentifying {
                                Text(MacText.shared("OnlineLookup.Identifying"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                } else if results.isEmpty {
                    Section {
                        ContentUnavailableView(MacText.shared("OnlineLookup.NotRecognized"),
                                               systemImage: "music.note",
                                               description: Text(MacText.shared("OnlineLookup.NotRecognized.Description")))
                            // Form rows hug the leading edge, so the view has to fill the row to sit in the middle
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Section(MacText.shared("OnlineLookup.Results")) {
                        ForEach(results) { release in
                            Button {
                                selectedRelease = release
                            } label: {
                                HStack {
                                    OnlineReleaseRow(release: release)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                // Only offered when nothing was recognized, since files often have no tags to search for
                if !isIdentifying && results.isEmpty {
                    searchSection
                }
            }
            .formStyle(.grouped)
            SheetActionBar {
                Spacer()
                Button(MacText.shared("Shared.Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                if !isIdentifying && results.isEmpty {
                    Button(MacText.shared("OnlineLookup.Search")) {
                        Task { await search() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSearch || isSearching)
                }
            }
        }
    }

    private var searchSection: some View {
        Section(MacText.shared("OnlineLookup.SearchByName")) {
            TextField(MacText.shared("Tag.Artist"), text: $artist)
            TextField(MacText.shared("Tag.Album"), text: $album)
        }
        .autocorrectionDisabled()
        .disabled(isSearching)
    }

    private var canSearch: Bool {
        !trimmedArtist.isEmpty || !trimmedAlbum.isEmpty
    }

    private var trimmedArtist: String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAlbum: String {
        album.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Recognizes the files and opens their album straight away if one clearly fits.
    private func identify() async {
        guard isIdentifying else { return }
        let result = await AutomaticLookup.lookUp(filesAt: files.map(\.path))
        results = result.releases
        identifiers = result.identifiers
        withAnimation {
            isIdentifying = false
        }
        if let bestMatch = result.bestMatch {
            selectedRelease = bestMatch
        }
    }

    /// Looks up the single album that best matches the artist and album, and opens it.
    private func search() async {
        guard canSearch, !isSearching else { return }
        isSearching = true
        do {
            if let release = try await AutomaticLookup.lookUp(artist: trimmedArtist, album: trimmedAlbum) {
                selectedRelease = release
            } else {
                isShowingNoMatch = true
            }
        } catch {
            isShowingSearchError = true
        }
        isSearching = false
    }
}

/// The buttons along the bottom of the lookup sheet.
struct SheetActionBar<Content: View>: View {

    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

struct OnlineReleaseRow: View {

    let release: OnlineRelease

    var body: some View {
        HStack(spacing: 12) {
            OnlineArtwork(url: release.thumbnailURL)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: release.title)
                    .lineLimit(2)
                Text(verbatim: release.artist)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let year = release.year {
            parts.append(year)
        }
        if let trackCount = release.trackCount {
            parts.append(String(localized: "OnlineLookup.TrackCount \(trackCount)"))
        }
        parts.append(contentsOf: release.details)
        parts.append(release.source.name)
        return parts.joined(separator: " · ")
    }
}

/// Album art loaded from an online source, with the generic album art while it loads or if it's missing.
struct OnlineArtwork: View {

    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image("Album.Generic")
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.primary.opacity(0.1), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
