import Foundation

struct TagEditorPresentation: Identifiable {
    let id = UUID()
    let files: [FSFile]
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

    // State handling for audio conversion
    var isConvertingAudio: Bool = false
    var fileBeingConverted: FSFile?
    var conversionProgress: Double = 0.0
    var targetConversionFormat: String = ""

    // State handling for sort
    var sortOption: SortOption = .fileName
    var sortOrder: SortOrder = .ascending
}
