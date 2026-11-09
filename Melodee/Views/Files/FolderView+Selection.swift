import SwiftUI

extension FolderView {

    // MARK: Toolbars

    @ToolbarContentBuilder
    var browsingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Section {
                    layoutPicker
                }
                Section {
                    resumePlaybackPicker
                    videoEnginePicker
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
        ToolbarItem(placement: .principal) {
            browsingTitle
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Selection.Select") {
                startSelecting()
            }
            .disabled(selectableFiles().isEmpty)
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
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
    }

    @ViewBuilder
    var browsingTitle: some View {
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

    @ToolbarContentBuilder
    var selectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Group {
                if selectedPaths.isEmpty {
                    Text("Selection.Title")
                } else {
                    Text("Selection.Count.\(selectedPaths.count)")
                }
            }
            .bold()
            .contentTransition(.numericText())
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .confirm) {
                stopSelecting()
            }
        }
        // Actions on the selected files sit together on the leading edge
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                state.tagEditorPresentation = TagEditorPresentation(files: selectedTaggableFiles())
            } label: {
                Label("Selection.EditTags", systemImage: "tag")
            }
            .disabled(selectedTaggableFiles().isEmpty)
            Button {
                state.batchRenamePresentation = BatchRenamePresentation(files: selectedFiles())
            } label: {
                Label("Shared.Rename", systemImage: "pencil")
            }
            .disabled(selectedPaths.isEmpty)
            trimButton
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            if areAllSelectableFilesSelected {
                Button("Selection.DeselectAll") {
                    selectedPaths.removeAll()
                }
            } else {
                Button("Selection.SelectAll") {
                    selectedPaths = Set(selectableFiles().map(\.path))
                }
            }
        }
    }

    /// Opens the trimmer for one file. For several, offers to paste the copied trim, cut the same length from
    /// their starts and ends, or restore their originals.
    @ViewBuilder
    var trimButton: some View {
        let trimmableFiles = selectedFiles().filter(MediaTrimmer.canTrim)
        if trimmableFiles.count == 1, selectedPaths.count == 1, let file = trimmableFiles.first {
            Button {
                state.trimPresentation = TrimPresentation(file: file)
            } label: {
                Label("Trim.Action", systemImage: "timeline.selection")
            }
        } else {
            let restorableFiles = trimmableFiles.filter(MediaTrimmer.hasOriginal)
            Menu {
                Button {
                    state.pasteTrimFiles = trimmableFiles
                    state.isPasteTrimConfirmationPresented = true
                } label: {
                    Label("Trim.Paste", systemImage: "doc.on.clipboard")
                }
                .disabled(CopiedTrim.clipboard == nil)
                Button {
                    state.batchTrimPresentation = BatchTrimPresentation(files: trimmableFiles)
                } label: {
                    Label("Trim.Batch.Ellipsis", systemImage: "arrow.right.and.line.vertical.and.arrow.left")
                }
                Divider()
                Button(role: .destructive) {
                    state.restoreFiles = restorableFiles
                    state.isBatchRestoreConfirmationPresented = true
                } label: {
                    Label("Trim.Restore.Batch", systemImage: "arrow.uturn.backward")
                }
                .disabled(restorableFiles.isEmpty)
            } label: {
                Label("Trim.Action", systemImage: "timeline.selection")
            }
            .disabled(trimmableFiles.isEmpty)
        }
    }

    // MARK: Selection

    /// The files shown right now, which are the ones Select All picks.
    func selectableFiles() -> [FSFile] {
        if isSearching {
            return searchFileResults
        }
        return files.compactMap { $0 as? FSFile }
    }

    /// The selected files, in the order they're shown.
    func selectedFiles() -> [FSFile] {
        selectableFiles().filter { selectedPaths.contains($0.path) }
    }

    func selectedTaggableFiles() -> [FSFile] {
        selectedFiles().filter { $0.isTaggableAudio() }
    }

    var areAllSelectableFilesSelected: Bool {
        let paths = selectableFiles().map(\.path)
        return !paths.isEmpty && paths.allSatisfy { selectedPaths.contains($0) }
    }

    func toggleSelection(of item: any FilesystemObject) {
        guard item is FSFile else { return }
        if selectedPaths.contains(item.path) {
            selectedPaths.remove(item.path)
        } else {
            selectedPaths.insert(item.path)
        }
    }

    func startSelecting() {
        selectedPaths.removeAll()
        withAnimation(.default.speed(2)) {
            isSelecting = true
            // The selection actions take the place of the Now Playing bar at the bottom of the screen
            nowPlayingBarManager.isBarPresented = false
        }
    }

    func stopSelecting() {
        withAnimation(.default.speed(2)) {
            isSelecting = false
            selectedPaths.removeAll()
            nowPlayingBarManager.isBarPresented = true
        }
    }

    /// Drops selected paths that no longer exist, such as files that were renamed or deleted.
    func pruneSelection() {
        guard !selectedPaths.isEmpty else { return }
        let visiblePaths = Set(selectableFiles().map(\.path))
        selectedPaths.formIntersection(visiblePaths)
    }
}
