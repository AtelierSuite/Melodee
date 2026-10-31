import Foundation

/// Owns the managers shared by every scene, so they exist and are set up even when
/// the app is launched without the phone UI (e.g. from CarPlay).
@MainActor
final class AppServices {

    static let shared = AppServices()

    let fileManager = FilesystemManager()
    let mediaPlayerManager = MediaPlayerManager()
    let fileDownloadManager = FileDownloadManager()
    let externalFoldersManager = ExternalFoldersManager()

    private var hasStarted: Bool = false

    private init() { }

    /// Prepares the managers and restores the previous session. Safe to call more than once.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        debugPrint("Creating placeholder files")
        fileManager.createPlaceholders()
        mediaPlayerManager.downloadManager = fileDownloadManager
        mediaPlayerManager.stateStore = PlaybackStateStore(
            documentsDirectoryURL: fileManager.documentsDirectoryURL,
            cloudDocumentsDirectoryURL: fileManager.cloudDocumentsDirectoryURL,
            externalFolders: externalFoldersManager
        )
        mediaPlayerManager.restorePlaybackState()
    }
}
