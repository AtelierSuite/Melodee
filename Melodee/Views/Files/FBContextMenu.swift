import Audioglot
import SwiftUI
import Videoglot

struct FBContextMenu: View {

    @Environment(FilesystemManager.self) var fileManager
    @Environment(MediaPlayerManager.self) var mediaPlayer

    @Binding var state: FBState
    var file: any FilesystemObject
    var extractZIPAction: () -> Void
    var refreshFilesAction: () -> Void

    var body: some View {
        if let file = file as? FSFile {
            // Context menu items for files
            // File type specific actions
            if file.isPlayableMedia() {
                Button {
                    mediaPlayer.requestPlay(file)
                } label: {
                    Label("Shared.Play", systemImage: "play")
                }
                Button {
                    withAnimation(.default.speed(2)) {
                        mediaPlayer.queueNext(file: file)
                    }
                } label: {
                    Label("Shared.Play.Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button {
                    withAnimation(.default.speed(2)) {
                        mediaPlayer.queueLast(file: file)
                    }
                } label: {
                    Label("Shared.Play.Last", systemImage: "text.line.last.and.arrowtriangle.forward")
                }
                Divider()
            } else if file.type == .image {
                if let image = UIImage(contentsOfFile: file.path) {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    } label: {
                        Label("Shared.SaveToPhotos", systemImage: "square.and.arrow.down")
                    }
                }
                Divider()
            } else if file.type == .zip {
                Button {
                    extractZIPAction()
                } label: {
                    Label("Shared.Extract", systemImage: "archivebox")
                }
                Divider()
            }
            // Tag Editor menu items
            if file.isTaggableAudio() {
                Button {
                    state.tagEditorPresentation = TagEditorPresentation(files: [file])
                } label: {
                    Label("Shared.EditTag.Single", systemImage: "tag")
                }
                Divider()
            }
            // Trimming menu items
            if MediaTrimmer.canTrim(file) {
                Button {
                    state.trimPresentation = TrimPresentation(file: file)
                } label: {
                    Label("Trim.Ellipsis", systemImage: "timeline.selection")
                }
                if CopiedTrim.clipboard != nil {
                    Button {
                        state.pasteTrimFiles = [file]
                        state.isPasteTrimConfirmationPresented = true
                    } label: {
                        Label("Trim.Paste", systemImage: "doc.on.clipboard")
                    }
                }
                if MediaTrimmer.hasOriginal(file) {
                    Button {
                        state.fileBeingRestored = file
                        state.isRestoreConfirmationPresented = true
                    } label: {
                        Label("Trim.Restore", systemImage: "arrow.uturn.backward")
                    }
                }
                Divider()
            }
            // Conversion menu items
            let audioTargets = file.audioConversionTargets()
            let videoTargets = file.videoConversionTargets()
            if !audioTargets.isEmpty || !videoTargets.isEmpty {
                Menu {
                    ForEach(audioTargets) { format in
                        Button(format.displayName) {
                            convert(title: "Alert.ConvertingAudio.Title") { progress in
                                try await Audioglot.convert(URL(filePath: file.path), to: format, progress: progress)
                            }
                        }
                    }
                    ForEach(videoTargets) { format in
                        Button {
                            convert(title: "Alert.ConvertingVideo.Title") { progress in
                                try await Videoglot.convert(URL(filePath: file.path), to: format, progress: progress)
                            }
                        } label: {
                            if format.isAudioOnly {
                                Text("Shared.Convert.AudioOnly.\(format.displayName)")
                            } else {
                                Text(format.displayName)
                            }
                        }
                    }
                } label: {
                    Label("Shared.Convert", systemImage: "arrow.triangle.2.circlepath")
                }
                Divider()
            }
            // Default item for all files
            Button {
                state.fileBeingRenamed = file
                state.isRenamingFile = true
            } label: {
                Label("Shared.Rename", systemImage: "pencil")
            }
        } else if let directory = file as? FSDirectory {
            // Context menu items for directories
            if isDirectoryEligibleForQueue(directory) {
                Button {
                    mediaPlayer.stop()
                    addToQueue(directory: directory)
                    mediaPlayer.play()
                } label: {
                    Label("Shared.Play.Folder", systemImage: "play")
                }
            }
            if isDirectoryEligibleForQueueRecursively(directory) {
                Button {
                    mediaPlayer.stop()
                    addToQueue(directory: directory, recursively: true)
                    mediaPlayer.play()
                } label: {
                    Label("Shared.Play.Folder.Recursive", systemImage: "play")
                }
            }
            if isDirectoryEligibleForQueue(directory) || isDirectoryEligibleForQueueRecursively(directory) {
                Divider()
            }
            Button {
                state.directoryBeingRenamed = directory
                state.isRenamingDirectory = true
            } label: {
                Label("Shared.Rename", systemImage: "pencil")
            }
        }
        Button(role: .destructive) {
            state.fileOrDirectoryBeingDeleted = file
            state.isDeletingFileOrDirectory = true
        } label: {
            Label("Shared.Delete", systemImage: "trash")
        }
    }

    func isDirectoryEligibleForQueue(_ directory: FSDirectory) -> Bool {
        let url = URL(fileURLWithPath: directory.path)
        if FileManager.default.fileExists(atPath: directory.path) {
            let files = fileManager.files(in: url).filter({ $0 is FSFile })
            return files.contains(where: { file in
                if let file = file as? FSFile {
                    return file.isPlayableMedia()
                }
                return false
            })
        }
        return false
    }

    func isDirectoryEligibleForQueueRecursively(_ directory: FSDirectory) -> Bool {
        let url = URL(fileURLWithPath: directory.path)
        if FileManager.default.fileExists(atPath: directory.path) {
            let files = fileManager.files(in: url).filter({ $0 is FSDirectory })
            for file in files {
                if let directory = file as? FSDirectory {
                    let filesInDirectory = fileManager.files(in: url)
                    if filesInDirectory.contains(where: { file in
                        if let file = file as? FSFile {
                            return file.isPlayableMedia()
                        }
                        return false
                    }) {
                        return true
                    } else {
                        return isDirectoryEligibleForQueueRecursively(directory)
                    }
                }
            }
        }
        return false
    }

    func addToQueue(directory: FSDirectory, recursively isRecursiveAdd: Bool = false) {
        let url = URL(fileURLWithPath: directory.path)
        if FileManager.default.fileExists(atPath: directory.path) {
            let contents = fileManager.files(in: url).sorted { lhs, rhs in
                lhs.name < rhs.name
            }
            for content in contents {
                if let file = content as? FSFile, file.isPlayableMedia() {
                    mediaPlayer.queueLast(file: file)
                }
            }
            if isRecursiveAdd {
                for content in contents {
                    if let directory = content as? FSDirectory {
                        addToQueue(directory: directory, recursively: isRecursiveAdd)
                    }
                }
            }
        }
    }

    func convert(title: String, _ operation: @escaping (@escaping @Sendable (Double) -> Void) async throws -> URL) {
        state.conversionTitle = title
        state.conversionProgress = 0.0
        state.isConverting = true

        Task {
            do {
                _ = try await operation { progress in
                    Task { @MainActor in
                        state.conversionProgress = progress
                    }
                }
                state.isConverting = false
                refreshFilesAction()
            } catch {
                state.isConverting = false
                state.isErrorAlertPresenting = true
                state.errorText = error.localizedDescription
            }
        }
    }
}
