import SFBAudioEngine
import SwiftUI
import TipKit

struct FolderView: View {

    @State var fileManager: FilesystemManager
    @Environment(MediaPlayerManager.self) var mediaPlayer

    @AppStorage("SelectedLibrarySource") var selectedSource: LibrarySource = .local
    @AppStorage("FileBrowserLayout") var layout: FileBrowserLayout = .list

    @State var currentDirectory: FSDirectory?
    @State var files: [any FilesystemObject] = []
    @State var state = FBState()
    @State var isSelectingExternalDirectory = false
    @State var storageLocation: StorageLocation = .local
    @State var isCreatingPlaylist = false
    @State var isCreatingFolder = false
    @State var newFolderName: String = ""
    @State var isAttributionsPresented: Bool = false
    @State var searchText: String = ""
    @State var searchFolderResults: [FSDirectory] = []
    @State var searchFileResults: [FSFile] = []
    @State var dropTargetPath: String?

    var overrideStorageLocation: StorageLocation?
    var isLibraryRoot: Bool = false

    init(
        currentDirectory: FSDirectory? = nil,
        overrideStorageLocation: StorageLocation? = nil,
        isLibraryRoot: Bool = false,
        fileManager: FilesystemManager? = nil
    ) {
        self.currentDirectory = currentDirectory
        self.overrideStorageLocation = overrideStorageLocation
        self.isLibraryRoot = isLibraryRoot
        self._fileManager = State(initialValue: fileManager ?? FilesystemManager())
    }

    var isCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @State var heightOfTitle: CGFloat = 1.0
    @State var isTitleHidden: Bool = false

    var body: some View {
        Group {
            switch layout {
            case .list: listContent
            case .grid: gridContent
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > heightOfTitle
        } action: { _, isHidden in
            withAnimation {
                isTitleHidden = isHidden
            }
        }
        .navigationTitle(viewTitle())
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text("Search.Prompt")
        )
        .onChange(of: searchText) {
            performSearch()
        }
        .playbackBarContentInset()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Section {
                        layoutPicker
                    }
                    if folderContainsTaggableFiles() || folderContainsFiles() {
                        Section {
                            if folderContainsTaggableFiles() {
                                Button {
                                    state.tagEditorPresentation = TagEditorPresentation(files: taggableFiles())
                                } label: {
                                    Label("Shared.EditTag.All", systemImage: "tag")
                                }
                            }
                            if folderContainsFiles() {
                                Button {
                                    state.batchRenamePresentation = BatchRenamePresentation(
                                        files: files.compactMap { $0 as? FSFile }
                                    )
                                } label: {
                                    Label("BatchRename.All", systemImage: "pencil.and.list.clipboard")
                                }
                            }
                        }
                    }
                    Section {
                        Link(destination: URL(string: "https://github.com/AtelierSuite/Melodee")!) {
                            Label("More.GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        Button("More.Attributions") {
                            isAttributionsPresented = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newFolderName = ""
                        isCreatingFolder = true
                    } label: {
                        Label("Shared.NewFolder", systemImage: "folder")
                    }
                    Button {
                        isCreatingPlaylist = true
                    } label: {
                        Label("Shared.NewPlaylist", systemImage: "music.note.list")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .principal) {
                if isLibraryRoot {
                    LibrarySourcePicker(
                        selectedSource: $selectedSource,
                        isCloudAvailable: isCloudAvailable
                    )
                } else {
                    Text(viewTitle())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200.0)
                        .bold()
                        .opacity(isTitleHidden ? 1 : 0)
                        .transition(.opacity.animation(.default.speed(0.2)))
                }
            }
        }
        .overlay {
            if isSearching {
                if searchFolderResults.isEmpty && searchFileResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            } else if files.count == 0 && currentDirectory == nil && state.isInitialLoadCompleted {
                // Show ContentUnavailableView with button for root directories
                if storageLocation == .local || storageLocation == .cloud {
                    ContentUnavailableView {
                        Label("FileBrowser.Tip.NoFiles.Title", systemImage: "questionmark.folder.fill")
                    } description: {
                        Text("FileBrowser.Tip.NoFiles.Text")
                    } actions: {
                        Button {
                            openInFilesApp()
                        } label: {
                            Text("FileBrowser.OpenInFiles")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if files.count == 0 && state.isInitialLoadCompleted {
                ContentUnavailableView("FileBrowser.Hint", systemImage: "questionmark.folder")
                    .font(.body)
            }
        }
        .refreshable {
            refreshFiles()
        }
        .overlay {
            if state.isExtractingZIP {
                // TODO: ProgressAlert should be on a higher level
                //       (cover the entire view, instead of just the view inside the navigation stack
                ProgressAlert(title: "Alert.ExtractingZIP.Title",
                              message: "Alert.ExtractingZIP.Text",
                              percentage: $state.extractionPercentage) {
                    withAnimation(.easeOut.speed(2)) {
                        state.isExtractionCancelling = true
                        fileManager.extractionProgress?.cancel()
                        state.extractionPercentage = 0
                        state.isExtractingZIP = false
                    }
                }
            }
        }
        .environment(fileManager)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let overrideStorageLocation {
                storageLocation = overrideStorageLocation
            }
            if !state.isInitialLoadCompleted {
                refreshFiles()
            }
        }
        .onChange(of: state.fileBeingRenamed) { _, newValue in
            if let fileBeingRenamed = newValue {
                state.newFileName = fileBeingRenamed.name
            } else {
                state.newFileName = ""
            }
        }
        .onChange(of: state.directoryBeingRenamed) { _, newValue in
            if let directoryBeingRenamed = newValue {
                state.newDirectoryName = directoryBeingRenamed.name
            } else {
                state.newDirectoryName = ""
            }
        }
        .onChange(of: state.sortOption) {
            sortFiles()
        }
        .onChange(of: state.sortOrder) {
            sortFiles()
        }
        .fileBrowserAlerts(state: $state, refreshFiles: refreshFiles)
        .tagEditorPresentation($state.tagEditorPresentation)
        .sheet(item: $state.batchRenamePresentation) { presentation in
            BatchRenameView(
                files: presentation.files,
                scopeRootURL: scopeRootURL(),
                fileManager: fileManager
            ) {
                refreshFiles()
            }
        }
        .sheet(isPresented: $isCreatingPlaylist) {
            CreatePlaylistSheet(
                scopeRootURL: scopeRootURL(),
                saveDirectoryURL: currentDirectoryURL(),
                fileManager: fileManager
            ) {
                refreshFiles()
            }
        }
        .sheet(isPresented: $isAttributionsPresented) {
            NavigationStack {
                MoreLicensesView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .close) {
                                isAttributionsPresented = false
                            }
                        }
                    }
            }
        }
        .alert("Alert.CreateFolder.Title", isPresented: $isCreatingFolder) {
            TextField("Shared.NewDirectoryName", text: $newFolderName)
            Button("Shared.Create") {
                createFolder()
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Shared.Cancel", role: .cancel) {
                newFolderName = ""
            }
        }
    }

    var listContent: some View {
        List {
            if isSearching {
                if !searchFolderResults.isEmpty {
                    Section("Search.Folders") {
                        ForEach(searchFolderResults, id: \.path) { directory in
                            fileBrowserRow(for: directory)
                        }
                    }
                }
                if !searchFileResults.isEmpty {
                    Section("Search.Files") {
                        ForEach(searchFileResults, id: \.path) { file in
                            fileBrowserRow(for: file)
                        }
                    }
                }
            } else {
                Section {
                    if !isLibraryRoot {
                        folderTitle
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    folderActions
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden, edges: .top)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in
                            return 0.0
                        }
                }
                .listSectionSeparator(.hidden, edges: .top)
                Section {
                    ForEach(files, id: \.path) { file in
                        fileBrowserRow(for: file)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    var gridContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0.0) {
                if isSearching {
                    if !searchFolderResults.isEmpty {
                        gridSection("Search.Folders", items: searchFolderResults)
                    }
                    if !searchFileResults.isEmpty {
                        gridSection("Search.Files", items: searchFileResults)
                    }
                } else {
                    if !isLibraryRoot {
                        folderTitle
                            .padding(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    }
                    folderActions
                        .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                    fileGrid(files)
                }
            }
        }
    }

    func gridSection(_ title: LocalizedStringKey, items: [any FilesystemObject]) -> some View {
        Section {
            fileGrid(items)
        } header: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
        }
    }

    func fileGrid(_ items: [any FilesystemObject]) -> some View {
        LazyVGrid(
            columns: [GridItem(
                .adaptive(minimum: GridCell.minimumWidth,
                          maximum: GridCell.maximumWidth),
                spacing: 12.0,
                alignment: .top
            )],
            alignment: .leading,
            spacing: 16.0
        ) {
            ForEach(items, id: \.path) { file in
                fileBrowserRow(for: file)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16.0)
        .padding(.bottom, 16.0)
    }

    var folderTitle: some View {
        Text(viewTitle())
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
    }

    var folderActions: some View {
        HStack(alignment: .center, spacing: 8.0) {
            Group {
                ActionButton(text: "Shared.PlayAll", icon: "Play", isPrimary: true) {
                    mediaPlayer.stop()
                    for file in files {
                        if let file = file as? FSFile, file.isPlayableMedia() {
                            mediaPlayer.queueLast(file: file)
                        }
                    }
                    mediaPlayer.play()
                }
                ActionButton(text: "Shared.Shuffle", icon: "Shuffle", isPrimary: false) {
                    mediaPlayer.stop()
                    var filesReordered: [FSFile] = []
                    for file in files {
                        if let file = file as? FSFile, file.isPlayableMedia() {
                            filesReordered.append(file)
                        }
                    }
                    filesReordered = filesReordered.shuffled()
                    for file in filesReordered {
                        mediaPlayer.queueLast(file: file)
                    }
                    mediaPlayer.play()
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(!folderContainsPlayableMedia())
            sortMenu
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    var layoutPicker: some View {
        Picker("FileBrowser.Layout", selection: $layout) {
            Label("FileBrowser.Layout.Grid", systemImage: "square.grid.2x2")
                .tag(FileBrowserLayout.grid)
            Label("FileBrowser.Layout.List", systemImage: "list.bullet")
                .tag(FileBrowserLayout.list)
        }
        .pickerStyle(.palette)
    }

    var sortMenu: some View {
        Menu {
            Section("Sort.Title") {
                Picker("Sort.SortBy", selection: $state.sortOption) {
                    Label("Sort.FileName", systemImage: "doc")
                        .tag(SortOption.fileName)
                    Label("Sort.TrackTitle", systemImage: "music.note")
                        .tag(SortOption.trackTitle)
                    Label("Sort.TrackNumber", systemImage: "number")
                        .tag(SortOption.trackNumber)
                    Label("Sort.AlbumName", systemImage: "square.stack")
                        .tag(SortOption.albumName)
                    Label("Sort.ArtistName", systemImage: "music.mic")
                        .tag(SortOption.artistName)
                }
            }
            .labelsVisibility(.visible)
            .menuActionDismissBehavior(.disabled)
            Section {
                Picker("Sort.Order", selection: $state.sortOrder) {
                    Label("Sort.Ascending", systemImage: "arrow.up")
                        .tag(SortOrder.ascending)
                    Label("Sort.Descending", systemImage: "arrow.down")
                        .tag(SortOrder.descending)
                }
            }
            .menuActionDismissBehavior(.disabled)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .resizable()
                .scaledToFit()
                .frame(width: 18.0, height: 18.0)
                .bold()
                .frame(width: 24.0, height: 24.0)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Sort.Title")
    }

    @ViewBuilder
    func fileBrowserRow(for file: any FilesystemObject) -> some View {
        let isDropTarget = dropTargetPath == file.path
        Group {
            if let directory = file as? FSDirectory {
                FBDirectoryRow(directory: directory, storageLocation: storageLocation, layout: layout)
                    // Dropping files and folders on a folder moves them into it
                    .dropDestination(for: URL.self) { urls, _ in
                        moveItems(urls, into: directory)
                    } isTargeted: { isTargeted in
                        if isTargeted {
                            dropTargetPath = directory.path
                        } else if dropTargetPath == directory.path {
                            dropTargetPath = nil
                        }
                    }
            } else if let file = file as? FSFile {
                fileRow(for: file)
            }
        }
        .background {
            if layout == .grid && isDropTarget {
                RoundedRectangle(cornerRadius: 12.0)
                    .fill(Color.accentColor.opacity(0.2))
                    .padding(-4.0)
            }
        }
        .draggable(URL(fileURLWithPath: file.path))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: layout == .grid ? 10.0 : 0.0))
        .contextMenu {
            FBContextMenu(state: $state, file: file, extractZIPAction: {
                if let file = file as? FSFile {
                    extractZIP(file: file)
                }
            }, refreshFilesAction: {
                refreshFiles()
            })
        }
        .listRowBackground(isDropTarget ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    /// Moves items dragged from this library into a folder. Items from other apps aren't moved.
    func moveItems(_ urls: [URL], into directory: FSDirectory) -> Bool {
        let scopePath = FilesystemManager.normalizedPath(scopeRootURL().path(percentEncoded: false))
        let libraryURLs = urls.filter { url in
            url.isFileURL && FilesystemManager.normalizedPath(url.path(percentEncoded: false)).hasPrefix(scopePath + "/")
        }
        guard !libraryURLs.isEmpty else { return false }
        let result = FilesystemManager.move(libraryURLs, into: URL(fileURLWithPath: directory.path))
        mediaPlayer.updateQueuedFilePaths(afterMoving: result.movedPaths)
        refreshFiles()
        if let failure = result.failures.first {
            state.errorText = failure.localizedDescription
            state.isErrorAlertPresenting = true
        }
        return !result.movedPaths.isEmpty
    }

    @ViewBuilder
    func fileRow(for file: FSFile) -> some View {
        switch file.type {
        case .audio: FBAudioFileRow(file: file, layout: layout, sortOption: state.sortOption)
        case .video: FBVideoFileRow(file: file, layout: layout)
        case .image: FBImageFileRow(file: file, layout: layout)
        case .text: FBTextFileRow(file: file, layout: layout)
        case .pdf: FBPdfFileRow(file: file, layout: layout)
        case .zip: FBZipFileRow(file: file, layout: layout) { extractZIP(file: file) }
        case .playlist: FBPlaylistFileRow(file: file, layout: layout, scopeRootURL: scopeRootURL())
        default: FBFileLabel(file: file, layout: layout)
        }
    }

    func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchFolderResults = []
            searchFileResults = []
            return
        }
        let results = fileManager.search(matching: query, in: currentDirectoryURL())
        searchFolderResults = results.folders.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        searchFileResults = results.files.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func createFolder() {
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let folderURL = currentDirectoryURL().appendingPathComponent(trimmedName, isDirectory: true)
        fileManager.createDirectory(at: folderURL.path(percentEncoded: false))
        newFolderName = ""
        refreshFiles()
    }

    func currentDirectoryURL() -> URL {
        if let currentDirectory {
            return URL(fileURLWithPath: currentDirectory.path)
        }
        return scopeRootURL()
    }

    func scopeRootURL() -> URL {
        switch storageLocation {
        case .local:
            return fileManager.documentsDirectoryURL ?? FileManager.default.temporaryDirectory
        case .cloud:
            return fileManager.cloudDocumentsDirectoryURL ?? FileManager.default.temporaryDirectory
        case .external:
            return fileManager.directory ?? FileManager.default.temporaryDirectory
        }
    }

    func updateFileManagerDirectory() {
        switch storageLocation {
        case .local:
            fileManager.directory = fileManager.documentsDirectoryURL
        case .cloud:
            fileManager.directory = fileManager.cloudDocumentsDirectoryURL
        case .external:
            if let currentDirectory {
                fileManager.directory = URL(fileURLWithPath: currentDirectory.path)
            }
        }
    }

    func viewTitle() -> String {
        switch storageLocation {
        case .cloud:
            return currentDirectory?.name ??
            NSLocalizedString("Shared.iCloudDrive", comment: "")
        case .local:
            return currentDirectory?.name ??
            NSLocalizedString("Shared.OnMyDevice", comment: "")
        case .external:
            return currentDirectory?.name ?? fileManager.directory?.lastPathComponent ??
            NSLocalizedString("ViewTitle.Files", comment: "")
        }
    }

    func refreshFiles() {
        updateFileManagerDirectory()
        withAnimation {
            if let path = currentDirectory?.path {
                self.files = fileManager.files(in: URL(fileURLWithPath: path), recursive: false)
            } else {
                self.files = fileManager.files(recursive: false)
            }
            sortFiles()
            state.isInitialLoadCompleted = true
        }
    }

    func extractZIP(file: FSFile) {
        withAnimation(.easeOut.speed(2)) {
            state.isExtractingZIP = true
        }
        UIApplication.shared.isIdleTimerDisabled = true
        nonisolated(unsafe) let fileManagerRef = fileManager
        fileManager.extractFiles(file: file) {
            MainActor.assumeIsolated {
                state.extractionPercentage =
                    Int((fileManagerRef.extractionProgress?.fractionCompleted ?? 0) * 100)
            }
        } onError: { error in
            MainActor.assumeIsolated {
                UIApplication.shared.isIdleTimerDisabled = false
                withAnimation(.easeOut.speed(2)) {
                    state.isExtractingZIP = false
                    state.errorText = error
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    state.isErrorAlertPresenting = true
                }
            }
        } onCompletion: {
            MainActor.assumeIsolated {
                UIApplication.shared.isIdleTimerDisabled = false
                withAnimation(.easeOut.speed(2)) {
                    state.isExtractingZIP = false
                }
                refreshFiles()
            }
        }
    }

    func folderContainsPlayableMedia() -> Bool {
        files.contains { ($0 as? FSFile)?.isPlayableMedia() ?? false }
    }

    func folderContainsFiles() -> Bool {
        files.contains { $0 is FSFile }
    }

    func folderContainsTaggableFiles() -> Bool {
        files.contains { ($0 as? FSFile)?.isTaggableAudio() ?? false }
    }

    func taggableFiles() -> [FSFile] {
        files.compactMap { $0 as? FSFile }.filter { $0.isTaggableAudio() }
    }

    func sortFiles() {
        // Separate into groups: folders > playlists > audio tracks > other files
        var directories = files.filter { $0 is FSDirectory }
        let allFiles = files.compactMap { $0 as? FSFile }
        var playlists: [any FilesystemObject] = allFiles.filter { $0.type == .playlist }
        var audioFiles: [any FilesystemObject] = allFiles.filter { $0.type == .audio }
        var otherFiles: [any FilesystemObject] = allFiles.filter {
            $0.type != .playlist && $0.type != .audio
        }

        // Sort directories alphabetically (always by name)
        directories.sort { lhs, rhs in
            let result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            return state.sortOrder == .ascending ? result : !result
        }

        // Sort playlists by name
        playlists.sort { lhs, rhs in
            let result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            return state.sortOrder == .ascending ? result : !result
        }

        // Build tag cache for tag-based sort options
        // Skip evicted iCloud files to avoid triggering downloads that would freeze the UI
        var tagCache: [String: AudioFile] = [:]
        if state.sortOption != .fileName {
            for item in audioFiles {
                if let file = item as? FSFile, file.isTaggableAudio(), !file.isEvicted(),
                   let audioFile = AudioFile.read(for: file) {
                    tagCache[file.path] = audioFile
                }
            }
        }

        // Sort audio files by the selected sort option
        audioFiles.sort { lhs, rhs in
            guard let lhsFile = lhs as? FSFile, let rhsFile = rhs as? FSFile else {
                return false
            }
            let comparison: ComparisonResult
            switch state.sortOption {
            case .fileName:
                comparison = lhsFile.name.localizedStandardCompare(rhsFile.name)
            case .trackTitle:
                let lhsTitle = tagCache[lhsFile.path]?.title ?? ""
                let rhsTitle = tagCache[rhsFile.path]?.title ?? ""
                comparison = lhsTitle.localizedStandardCompare(rhsTitle)
            case .trackNumber:
                let lhsTrack = tagCache[lhsFile.path]?.trackNumber ?? Int.max
                let rhsTrack = tagCache[rhsFile.path]?.trackNumber ?? Int.max
                if lhsTrack != rhsTrack {
                    comparison = lhsTrack < rhsTrack ? .orderedAscending : .orderedDescending
                } else {
                    comparison = .orderedSame
                }
            case .albumName:
                let lhsAlbum = tagCache[lhsFile.path]?.albumTitle ?? ""
                let rhsAlbum = tagCache[rhsFile.path]?.albumTitle ?? ""
                comparison = lhsAlbum.localizedStandardCompare(rhsAlbum)
            case .artistName:
                let lhsArtist = tagCache[lhsFile.path]?.artist ?? ""
                let rhsArtist = tagCache[rhsFile.path]?.artist ?? ""
                comparison = lhsArtist.localizedStandardCompare(rhsArtist)
            }

            // Fall back to file name when primary sort values are equal
            let resolved = comparison == .orderedSame
                ? lhsFile.name.localizedStandardCompare(rhsFile.name)
                : comparison
            return state.sortOrder == .ascending
                ? resolved == .orderedAscending
                : resolved == .orderedDescending
        }

        // Sort other files by name
        otherFiles.sort { lhs, rhs in
            let result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            return state.sortOrder == .ascending ? result : !result
        }

        // Combine: folders > playlists > audio tracks > other files
        files = directories + playlists + audioFiles + otherFiles
    }

    func openInFilesApp() {
        guard let filesUrl = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }
        let sharedDocumentsUrlString: String = filesUrl.absoluteString.replacingOccurrences(
            of: "file://",
            with: "shareddocuments://"
        )
        guard let sharedDocumentsUrl = URL(string: sharedDocumentsUrlString) else { return }
        if UIApplication.shared.canOpenURL(sharedDocumentsUrl) {
            UIApplication.shared.open(sharedDocumentsUrl, options: [:])
        }
    }
}
