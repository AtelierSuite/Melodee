import Intents
import SFBAudioEngine
import UIKit

/// Gives iOS the tracks to suggest in Now Playing when headphones or a car connect.
/// Only files that can play straight away are suggested, so nothing waits on a download.
@MainActor
final class PlaybackSuggestions {

    private static let maximumSuggestionCount = 10
    private static let artworkSize = CGSize(width: 300, height: 300)

    private let mediaPlayer: MediaPlayerManager
    private var updateTask: Task<Void, Never>?

    init(mediaPlayer: MediaPlayerManager) {
        self.mediaPlayer = mediaPlayer
        INUpcomingMediaManager.shared.setPredictionMode(.onlyPredictSuggestedIntents, for: .music)
        mediaPlayer.onPlaybackStart = { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func update() {
        guard let stateStore = mediaPlayer.stateStore else { return }
        var candidates: [FSFile] = []
        if let current = mediaPlayer.currentlyPlayingFile(), current.type == .audio {
            candidates.append(current)
        }
        candidates += stateStore.recentlyPlayedFiles()
        var seenPaths = Set<String>()
        let suggestions = candidates
            .filter { seenPaths.insert(FilesystemManager.normalizedPath($0.path)).inserted }
            .filter { FileManager.default.fileExists(atPath: $0.path) && !$0.isEvicted() }
            .prefix(Self.maximumSuggestionCount)
            .compactMap { file in stateStore.identifier(for: file).map { (file, $0) } }

        updateTask?.cancel()
        updateTask = Task.detached(priority: .utility) {
            var intents: [INPlayMediaIntent] = []
            for (file, identifier) in suggestions {
                if Task.isCancelled { return }
                intents.append(await Self.intent(for: file, identifier: identifier))
            }
            guard !Task.isCancelled else { return }
            INUpcomingMediaManager.shared.setSuggestedMediaIntents(NSOrderedSet(array: intents))
        }
    }

    /// Plays a suggested file, or carries on with the queue when no file is given.
    func play(identifier: String?) -> Bool {
        guard let identifier else {
            guard mediaPlayer.canStartPlayback() else { return false }
            mediaPlayer.play()
            return true
        }
        guard let file = mediaPlayer.stateStore?.file(forIdentifier: identifier, type: .audio) else {
            return false
        }
        if let current = mediaPlayer.currentlyPlayingFile(),
           FilesystemManager.normalizedPath(current.path) == FilesystemManager.normalizedPath(file.path) {
            mediaPlayer.play()
        } else {
            mediaPlayer.playImmediately(file)
        }
        return true
    }

    private nonisolated static func intent(for file: FSFile, identifier: String) async -> INPlayMediaIntent {
        let audioFile = file.isTaggableAudio() ? AudioFile.read(for: file) : nil
        var artwork: INImage?
        if let image = audioFile?.coverImage,
           let thumbnail = await image.byPreparingThumbnail(ofSize: artworkSize),
           let data = thumbnail.jpegData(compressionQuality: 0.8) {
            artwork = INImage(imageData: data)
        }
        let title = audioFile?.title.flatMap { $0.isEmpty ? nil : $0 } ?? file.name
        let mediaItem = INMediaItem(identifier: identifier,
                                    title: title,
                                    type: .song,
                                    artwork: artwork,
                                    artist: audioFile?.artist)
        return INPlayMediaIntent(mediaItems: [mediaItem],
                                 mediaContainer: nil,
                                 playShuffled: nil,
                                 playbackRepeatMode: .unknown,
                                 resumePlayback: nil,
                                 playbackQueueLocation: .now,
                                 playbackSpeed: nil,
                                 mediaSearch: nil)
    }
}

/// Plays what iOS asks for when a playback suggestion is picked.
final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {

    func resolveMediaItems(for intent: INPlayMediaIntent) async -> [INPlayMediaMediaItemResolutionResult] {
        if let mediaItems = intent.mediaItems, !mediaItems.isEmpty {
            return INPlayMediaMediaItemResolutionResult.successes(with: mediaItems)
        }
        if intent.mediaSearch == nil {
            return [INPlayMediaMediaItemResolutionResult(mediaItemResolutionResult: .notRequired())]
        }
        return [INPlayMediaMediaItemResolutionResult.unsupported()]
    }

    func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
        let identifier = intent.mediaItems?.first?.identifier
        let isPlaying = await MainActor.run {
            AppServices.shared.playbackSuggestions?.play(identifier: identifier) ?? false
        }
        return INPlayMediaIntentResponse(code: isPlaying ? .success : .failure, userActivity: nil)
    }
}
