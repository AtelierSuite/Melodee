import Foundation

struct TagEditorPresentation: Identifiable {
    let id = UUID()
    let files: [FSFile]
}

struct TrimPresentation: Identifiable {
    let id = UUID()
    let file: FSFile
}

struct FBState {
    // State handling for display
    var isInitialLoadCompleted: Bool = false

    // State handling for tag editing
    var tagEditorPresentation: TagEditorPresentation?

    // State handling for file rename
    var isRenamingFile: Bool = false
    var fileBeingRenamed: FSFile?
    var newFileName: String = ""

    // State handling for batch rename
    var batchRenamePresentation: BatchRenamePresentation?

    // State handling for directory rename
    var isRenamingDirectory: Bool = false
    var directoryBeingRenamed: FSDirectory?
    var newDirectoryName: String = ""

    // State handling for deletion
    var isDeletingFileOrDirectory: Bool = false
    var fileOrDirectoryBeingDeleted: (any FilesystemObject)?

    // State handling for ZIP extraction
    var isExtractingZIP: Bool = false
    var extractionPercentage: Int = 0
    var isExtractionCancelling: Bool = false
    var isErrorAlertPresenting: Bool = false
    var errorText: String = ""

    // State handling for audio and video conversion
    var isConverting: Bool = false
    var conversionTitle: String = "Alert.ConvertingAudio.Title"
    var conversionProgress: Double = 0.0

    // State handling for trimming
    var trimPresentation: TrimPresentation?
    var pasteTrimFiles: [FSFile] = []
    var isPasteTrimConfirmationPresented: Bool = false
    var fileBeingRestored: FSFile?
    var isRestoreConfirmationPresented: Bool = false
    var trimAlertMessage: String?

    // State handling for sort
    var sortOption: SortOption = .fileName
    var sortOrder: SortOrder = .ascending
}
