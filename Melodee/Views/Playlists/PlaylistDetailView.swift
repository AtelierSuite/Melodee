import SwiftUI

struct PlaylistDetailView: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    /// The .mpl file
    var file: FSFile
    var fileManager: FilesystemManager
    var scopeRootURL: URL

    @State var playlist: Playlist?
    @State var resolvedFiles: [ResolvedPlaylistFile] = []
    @State var isRenamingPlaylist: Bool = false
    @State var editedPlaylistName: String = ""
    @State var isManagingFiles: Bool = false

    @State var heightOfTitle: CGFloat = 1.0
    @State var isTitleHidden: Bool = false

    var playlistName: String {
        playlist?.name ?? file.name
    }

    var fileURL: URL {
        URL(fileURLWithPath: file.path)
    }

    var baseURL: URL {
        fileURL.deletingLastPathComponent()
    }

    var audioFiles: [ResolvedPlaylistFile] {
        resolvedFiles.filter { $0.file.type == .audio }
    }

    var nonAudioFiles: [ResolvedPlaylistFile] {
        resolvedFiles.filter { $0.file.type != .audio }
    }

    var body: some View {
        List {
            Section {
                Text(playlistName)
                    .font(.largeTitle)
                    .textCase(.none)
                    .bold()
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        heightOfTitle = height
                    }
                    .opacity(isTitleHidden ? 0 : 1)
                    .listRowSeparator(.hidden, edges: .all)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                HStack(alignment: .center, spacing: 8.0) {
                    Group {
                        ActionButton(text: "Shared.PlayAll", icon: "Play", isPrimary: true) {
                            playAll()
                        }
                        ActionButton(text: "Shared.Shuffle", icon: "Shuffle", isPrimary: false) {
                            shuffleAll()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(audioFiles.isEmpty)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                .listRowBackground(Color.clear)
                .alignmentGuide(.listRowSeparatorLeading) { _ in
                    return 0.0
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .listSectionSeparator(.hidden, edges: .top)
            if !audioFiles.isEmpty {
                Section {
                    ForEach(audioFiles) { item in
                        FBAudioFileRow(file: item.file)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        deleteItems(from: audioFiles, at: offsets)
                    }
                }
            }
            if !nonAudioFiles.isEmpty {
                Section("Playlists.OtherFiles") {
                    ForEach(nonAudioFiles) { item in
                        playlistFileRow(for: item.file)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        deleteItems(from: nonAudioFiles, at: offsets)
                    }
                }
            }
            if resolvedFiles.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Playlists.Detail.Empty.Title", systemImage: "music.note")
                    } description: {
                        Text("Playlists.Detail.Empty.Description")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                Button {
                    isManagingFiles = true
                } label: {
                    Text("Playlists.Manage")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8.0)
                        .padding(.horizontal, 12.0)
                        .background(.fill.tertiary, in: Capsule())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > heightOfTitle
        } action: { _, isHidden in
            withAnimation {
                isTitleHidden = isHidden
            }
        }
        .navigationTitle(playlistName)
        .listStyle(.plain)
        .playbackBarContentInset()
        .scrollContentBackground(.hidden)
        .background(
            .linearGradient(
                colors: [.backgroundGradientTop, .backgroundGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    editedPlaylistName = playlistName
                    isRenamingPlaylist = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
            ToolbarItem(placement: .principal) {
                Text(playlistName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .bold()
                    .opacity(isTitleHidden ? 1 : 0)
                    .transition(.opacity.animation(.default.speed(0.2)))
            }
        }
        .alert("Playlists.Rename", isPresented: $isRenamingPlaylist) {
            TextField("Playlists.PlaylistName", text: $editedPlaylistName)
            Button("Shared.Cancel", role: .cancel) { }
            Button("Shared.Save") {
                let trimmed = editedPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, var updated = playlist {
                    updated.name = trimmed
                    playlist = updated
                    PlaylistManager.save(updated, to: fileURL)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            loadPlaylist()
        }
        .sheet(isPresented: $isManagingFiles) {
            if let playlist {
                ManagePlaylistSheet(
                    scopeRootURL: scopeRootURL,
                    playlistDirectoryURL: baseURL,
                    fileManager: fileManager,
                    existingFiles: playlist.files
                ) { updatedFiles in
                    var updated = playlist
                    updated.files = updatedFiles
                    self.playlist = updated
                    PlaylistManager.save(updated, to: fileURL)
                    resolveFiles()
                }
            }
        }
    }

    func loadPlaylist() {
        playlist = PlaylistManager.load(from: fileURL)
        resolveFiles()
    }

    func resolveFiles() {
        guard let playlist else {
            resolvedFiles = []
            return
        }
        var resolved: [ResolvedPlaylistFile] = []
        for playlistFile in playlist.files {
            if let fsFile = playlistFile.resolve(relativeTo: baseURL) {
                resolved.append(ResolvedPlaylistFile(playlistFile: playlistFile, file: fsFile))
            }
        }
        resolvedFiles = resolved
    }

    func deleteItems(from section: [ResolvedPlaylistFile], at offsets: IndexSet) {
        guard var updated = playlist else { return }
        for index in offsets {
            let item = section[index]
            updated.files.removeAll { $0.relativePath == item.playlistFile.relativePath }
        }
        playlist = updated
        PlaylistManager.save(updated, to: fileURL)
        resolveFiles()
    }

    func playAll() {
        mediaPlayer.stop()
        for item in audioFiles {
            mediaPlayer.queueLast(file: item.file)
        }
        mediaPlayer.play()
    }

    func shuffleAll() {
        mediaPlayer.stop()
        let shuffled = audioFiles.shuffled()
        for item in shuffled {
            mediaPlayer.queueLast(file: item.file)
        }
        mediaPlayer.play()
    }

    @ViewBuilder
    func playlistFileRow(for file: FSFile) -> some View {
        switch file.type {
        case .image: FBImageFileRow(file: file)
        case .text: FBTextFileRow(file: file)
        case .pdf: FBPdfFileRow(file: file)
        case .zip: ListFileRow(file: .constant(file))
        default: ListFileRow(file: .constant(file))
        }
    }

}

struct ResolvedPlaylistFile: Identifiable {
    let playlistFile: PlaylistFile
    let file: FSFile
    var id: String { playlistFile.relativePath + file.path }
}
