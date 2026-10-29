@preconcurrency import AVFAudio
import AVKit
import Foundation
@preconcurrency import MediaPlayer
import SFBAudioEngine
import UIKit

// swiftlint:disable type_body_length
@Observable
class MediaPlayerManager: NSObject, AudioPlayer.Delegate {

    @ObservationIgnored let notificationCenter = NotificationCenter.default
    @ObservationIgnored let audioSession = AVAudioSession.sharedInstance()
    @ObservationIgnored let remoteCommandCenter = MPRemoteCommandCenter.shared()
    @ObservationIgnored let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    @ObservationIgnored let audioPlayer = AudioPlayer()
    @ObservationIgnored let videoPlayer = AVPlayer()
    @ObservationIgnored let videoPlayerController: AVPlayerViewController
    @ObservationIgnored var downloadManager: FileDownloadManager?
    @ObservationIgnored var stateStore: PlaybackStateStore?
    var isPlaybackActive: Bool = false
    var isPaused: Bool = true
    var repeatMode: RepeatMode = .none {
        didSet { if !isRestoringState { stateStore?.saveRepeatMode(repeatMode) } }
    }
    var queue: [FSFile] = [] {
        didSet { scheduleQueueSave() }
    }
    var currentlyPlayingID: String = "" {
        didSet {
            if currentlyPlayingID != oldValue {
                // The engine may still report the previous file's duration, so leave it out
                savePlaybackPosition(at: 0.0, includesTotalTime: false)
            }
        }
    }
    var metadataRefreshTrigger: UUID = UUID()
    var videoAspectRatio: CGFloat?

    @ObservationIgnored private var cachedMetadataID: String = ""
    @ObservationIgnored private var cachedTitle: String?
    @ObservationIgnored private var cachedArtist: String?
    @ObservationIgnored private var cachedAlbum: String?
    @ObservationIgnored private var cachedAlbumArt: UIImage?
    @ObservationIgnored private var videoItemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var videoTimeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var videoPresentationSizeObservation: NSKeyValueObservation?

    // Restored position that is applied once the engine loads the current file
    @ObservationIgnored private var pendingResumeTime: TimeInterval?
    @ObservationIgnored private var pendingTotalTime: TimeInterval?
    @ObservationIgnored private var isRestoringState: Bool = false
    @ObservationIgnored private var hasRestoredState: Bool = false
    @ObservationIgnored private var isQueueSaveScheduled: Bool = false
    @ObservationIgnored private var positionSaveTimer: Timer?

    override init() {
        // The same controller instance is reused by the Now Playing sheet so that
        // Picture in Picture keeps running when the sheet is dismissed.
        videoPlayerController = MainActor.assumeIsolated {
            let controller = AVPlayerViewController()
            controller.allowsPictureInPicturePlayback = true
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            controller.updatesNowPlayingInfoCenter = false
            return controller
        }
        super.init()
        audioPlayer.delegate = self
        // Advance the queue when a video finishes playing
        notificationCenter.addObserver(self,
                                       selector: #selector(videoPlayerItemDidPlayToEnd(_:)),
                                       name: .AVPlayerItemDidPlayToEndTime,
                                       object: nil)
        // Keep isPaused in sync when the video is paused/resumed from the
        // native player controls, PiP window, or fullscreen presentation
        videoTimeControlObservation = videoPlayer.observe(\.timeControlStatus) { [weak self] player, _ in
            guard let self else { return }
            nonisolated(unsafe) let managerRef = self
            let isNowPaused = player.timeControlStatus == .paused
            Task { @MainActor in
                guard managerRef.isCurrentlyPlayingVideo() else { return }
                managerRef.isPaused = isNowPaused
                managerRef.setNowPlaying()
            }
        }
        setUpRemoteCommands()
        // Save the playback position when the app may be suspended or terminated
        notificationCenter.addObserver(self,
                                       selector: #selector(applicationWillSuspend(_:)),
                                       name: UIApplication.didEnterBackgroundNotification,
                                       object: nil)
        notificationCenter.addObserver(self,
                                       selector: #selector(applicationWillSuspend(_:)),
                                       name: UIApplication.willTerminateNotification,
                                       object: nil)
        // The app can be killed while playing in the background without notice, so save periodically
        positionSaveTimer = Timer.scheduledTimer(timeInterval: 5.0,
                                                 target: self,
                                                 selector: #selector(positionSaveTimerFired(_:)),
                                                 userInfo: nil,
                                                 repeats: true)
    }

    private func setUpRemoteCommands() {
        remoteCommandCenter.playCommand.addTarget { _ in
            if !self.isEnginePlaying(), self.canStartPlayback() {
                self.play()
                return .success
            }
            return .commandFailed
        }
        remoteCommandCenter.pauseCommand.addTarget { _ in
            if self.isEnginePlaying() {
                self.pause()
                return .success
            }
            return .commandFailed
        }
        remoteCommandCenter.togglePlayPauseCommand.addTarget { _ in
            if self.isEnginePlaying() {
                self.pause()
                return .success
            } else if self.canStartPlayback() {
                self.play()
                return .success
            }
            return .commandFailed
        }
        remoteCommandCenter.nextTrackCommand.addTarget { _ in
            self.skipToNextTrack()
            return .success
        }
        remoteCommandCenter.previousTrackCommand.addTarget { _ in
            self.backToPreviousTrack()
            return .success
        }
        remoteCommandCenter.changePlaybackPositionCommand.addTarget { event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self.seekTo(event.positionTime)
                return .success
            }
            return .commandFailed
        }
    }

    func currentlyPlayingTitle() -> String? {
        guard isPlaybackActive, let file = currentlyPlayingFile() else { return nil }
        refreshMetadataCacheIfNeeded(for: file)
        if let title = cachedTitle, !title.isEmpty {
            return title
        }
        return file.name
    }

    func currentlyPlayingArtistName() -> String? {
        guard isPlaybackActive, let file = currentlyPlayingFile() else { return nil }
        refreshMetadataCacheIfNeeded(for: file)
        if let artist = cachedArtist, !artist.isEmpty {
            return artist
        }
        return NSLocalizedString("Shared.UnknownArtist", comment: "")
    }

    func currentlyPlayingAlbumName() -> String? {
        guard isPlaybackActive, let file = currentlyPlayingFile() else { return nil }
        refreshMetadataCacheIfNeeded(for: file)
        if let album = cachedAlbum, !album.isEmpty {
            return album
        }
        return file.containingFolderName()
    }

    private func refreshMetadataCacheIfNeeded(for file: FSFile) {
        guard cachedMetadataID != currentlyPlayingID else { return }
        cachedTitle = nil
        cachedArtist = nil
        cachedAlbum = nil
        cachedAlbumArt = nil
        guard file.isTaggableAudio(),
              FileManager.default.fileExists(atPath: file.path),
              !file.isEvicted(),
              let metadata = AudioFile.read(for: file)?.metadata else {
            // Leave cachedMetadataID untouched so a later call can retry once the file is available.
            return
        }
        cachedMetadataID = currentlyPlayingID
        cachedTitle = metadata.title
        cachedArtist = metadata.artist
        cachedAlbum = metadata.albumTitle
        if let data = (metadata.attachedPictures(ofType: .frontCover).first
                        ?? metadata.attachedPictures.first)?.imageData {
            cachedAlbumArt = UIImage(data: data)
        }
    }

    private func invalidateMetadataCache() {
        cachedMetadataID = ""
        metadataRefreshTrigger = UUID()
    }

    func currentlyPlayingFile() -> FSFile? {
        return queue.first(where: { $0.playbackQueueID == currentlyPlayingID })
    }

    func isCurrentlyPlayingVideo() -> Bool {
        return currentlyPlayingFile()?.type == .video
    }

    func isEnginePlaying() -> Bool {
        return audioPlayer.isPlaying || videoPlayer.timeControlStatus != .paused
    }

    func supportsSeeking() -> Bool {
        if pendingResumeTime != nil {
            return true
        }
        if isCurrentlyPlayingVideo() {
            return videoPlayer.currentItem != nil
        }
        return audioPlayer.supportsSeeking
    }

    func playbackTime() -> (currentTime: TimeInterval, totalTime: TimeInterval)? {
        // The restored file isn't loaded until playback starts, so report the saved position
        if let pendingResumeTime {
            guard let pendingTotalTime, pendingTotalTime > 0 else { return nil }
            return (min(pendingResumeTime, pendingTotalTime), pendingTotalTime)
        }
        if isCurrentlyPlayingVideo() {
            guard let item = videoPlayer.currentItem else { return nil }
            let totalTime = item.duration.seconds
            guard totalTime.isFinite, totalTime > 0 else { return nil }
            return (item.currentTime().seconds, totalTime)
        }
        guard let time = audioPlayer.time else { return nil }
        return (time.currentTime, time.totalTime)
    }

    func currentlyPlayingIndex() -> Int {
        return queue.firstIndex(where: { $0.playbackQueueID == currentlyPlayingID }) ?? 0
    }

    func canStartPlayback() -> Bool {
        return !queue.isEmpty
    }

    func canGoToNextTrack() -> Bool {
        guard !queue.isEmpty else { return false }
        return currentlyPlayingIndex() < queue.count - 1
    }

    func canGoToPreviousTrack() -> Bool {
        guard !queue.isEmpty else { return false }
        return currentlyPlayingIndex() > 0
    }

    func playImmediately(_ file: FSFile, addToQueue: Bool = true) {
        // Stop any playback that is in progress
        audioPlayer.stop()
        videoPlayer.pause()
        clearPendingResume()
        // Queue and/or play new file
        let currentlyPlayingIndex = currentlyPlayingIndex()
        if addToQueue {
            queue.insert(file, at: currentlyPlayingIndex)
            setQueueIDs()
        }
        // Set the currently playing ID before attempting playback
        if file.playbackQueueID.isEmpty, currentlyPlayingIndex < queue.count {
            currentlyPlayingID = queue[currentlyPlayingIndex].playbackQueueID
        } else {
            currentlyPlayingID = file.playbackQueueID
        }
        // If the file is evicted from iCloud, download it first
        if file.isEvicted(), let downloadManager {
            isPlaybackActive = true
            isPaused = true
            downloadManager.startDownload(for: file) { [weak self] in
                self?.invalidateMetadataCache()
                self?.loadAndPlay(file)
            }
            return
        }
        loadAndPlay(file)
    }

    private func loadAndPlay(_ file: FSFile, from startTime: TimeInterval? = nil) {
        activateAudioSession()
        let url = URL(fileURLWithPath: file.path)
        let startTime = startTime.flatMap { $0 > 0 ? $0 : nil }
        if file.type == .video {
            audioPlayer.stop()
            let item = AVPlayerItem(url: url)
            videoAspectRatio = nil
            // Size the Now Playing video surface to the video's own aspect ratio
            videoPresentationSizeObservation = item.observe(
                \.presentationSize,
                 options: [.initial, .new]
            ) { [weak self] item, _ in
                let size = item.presentationSize
                guard size.width > 0, size.height > 0, let self else { return }
                nonisolated(unsafe) let managerRef = self
                Task { @MainActor in
                    managerRef.videoAspectRatio = size.width / size.height
                }
            }
            videoItemStatusObservation = item.observe(\.status) { [weak self] item, _ in
                guard item.status == .failed, let self else { return }
                debugPrint("AVPlayer failed to load item: \(item.error?.localizedDescription ?? "unknown error")")
                nonisolated(unsafe) let managerRef = self
                Task { @MainActor in
                    managerRef.handlePlaybackFailure()
                }
            }
            videoPlayer.replaceCurrentItem(with: item)
            if let startTime {
                videoPlayer.seek(to: CMTime(seconds: startTime, preferredTimescale: 600),
                                 toleranceBefore: .zero,
                                 toleranceAfter: .zero)
            }
            videoPlayer.play()
            isPlaybackActive = true
            isPaused = false
            setNowPlaying()
            return
        }
        videoPlayer.replaceCurrentItem(with: nil)
        videoPresentationSizeObservation = nil
        videoAspectRatio = nil
        do {
            try playAudio(at: url, from: startTime)
            isPlaybackActive = true
            isPaused = false
            setNowPlaying()
        } catch {
            debugPrint("Failed to start playback: \(error.localizedDescription)")
            handlePlaybackFailure()
        }
    }

    private func playAudio(at url: URL, from startTime: TimeInterval?) throws {
        if let startTime {
            try audioPlayer.play(try decoder(for: url, startingAt: startTime))
        } else {
            try audioPlayer.play(url)
        }
    }

    /// Opens a decoder positioned at the given time, so playback resumes there without an audible jump.
    private func decoder(for url: URL, startingAt startTime: TimeInterval) throws -> AudioDecoder {
        let decoder = try AudioDecoder(url: url)
        try decoder.open()
        let frame = AVAudioFramePosition(startTime * decoder.processingFormat.sampleRate)
        if decoder.supportsSeeking, frame > 0, frame < decoder.length {
            do {
                try decoder.seek(to: frame)
            } catch {
                debugPrint("Failed to seek restored file: \(error.localizedDescription)")
            }
        }
        return decoder
    }

    private func handlePlaybackFailure() {
        if canGoToNextTrack() {
            skipToNextTrack()
        } else {
            stop()
        }
    }

    private func activateAudioSession() {
        MainActor.assumeIsolated {
            UIApplication.shared.beginReceivingRemoteControlEvents()
        }
        do {
            try audioSession.setCategory(AVAudioSession.Category.playback)
            try audioSession.setActive(true)
        } catch {
            debugPrint(error.localizedDescription)
        }
    }

    func play() {
        activateAudioSession()
        if isCurrentlyPlayingVideo(), let item = videoPlayer.currentItem {
            // Restart from the top if the video previously played to the end
            if item.duration.isValid, !item.duration.isIndefinite, item.currentTime() >= item.duration {
                videoPlayer.seek(to: .zero)
            }
            videoPlayer.play()
            isPlaybackActive = true
            isPaused = false
            setNowPlaying()
            return
        }
        // A route change or audio session interruption (e.g. AirPods) can stop the engine
        // while keeping the current decoder, so resume it rather than reloading from the start.
        if audioPlayer.isPaused || (audioPlayer.isStopped && audioPlayer.nowPlaying != nil) {
            do {
                try audioPlayer.play()
                isPlaybackActive = true
                isPaused = false
                setNowPlaying()
                return
            } catch {
                debugPrint("Failed to resume playback: \(error.localizedDescription)")
            }
        }
        if audioPlayer.isPlaying {
            isPlaybackActive = true
            isPaused = false
            setNowPlaying()
            return
        }
        // Stopped — start from the queue.
        let index = currentlyPlayingIndex()
        guard !queue.isEmpty, index < queue.count else { return }
        let file = queue[index]
        currentlyPlayingID = file.playbackQueueID
        let resumeTime = pendingResumeTime
        clearPendingResume()
        if file.isEvicted(), let downloadManager {
            isPlaybackActive = true
            isPaused = true
            downloadManager.startDownload(for: file) { [weak self] in
                self?.invalidateMetadataCache()
                self?.loadAndPlay(file, from: resumeTime)
            }
        } else {
            loadAndPlay(file, from: resumeTime)
        }
    }

    func queueNext(file: FSFile) {
        queue.insert(file, at: min(queue.count, currentlyPlayingIndex() + 1))
        setQueueIDs()
        setNowPlaying()
    }

    func queueLast(file: FSFile) {
        queue.append(file)
        setQueueIDs()
        setNowPlaying()
    }

    func pause() {
        audioPlayer.pause()
        videoPlayer.pause()
        isPaused = true
        savePlaybackPosition()
    }

    func stop() {
        audioPlayer.stop()
        videoPlayer.replaceCurrentItem(with: nil)
        videoItemStatusObservation = nil
        videoPresentationSizeObservation = nil
        videoAspectRatio = nil
        clearPendingResume()
        queue.removeAll()
        currentlyPlayingID = ""
        nowPlayingInfoCenter.nowPlayingInfo = nil
        isPlaybackActive = false
        isPaused = true
    }

    func skipToNextTrack() {
        if canGoToNextTrack() {
            playImmediately(queue[currentlyPlayingIndex() + 1], addToQueue: false)
        } else {
            setNowPlaying()
        }
    }

    func backToPreviousTrack() {
        if canGoToPreviousTrack() {
            playImmediately(queue[currentlyPlayingIndex() - 1], addToQueue: false)
        } else {
            setNowPlaying()
        }
    }

    func seekTo(_ time: TimeInterval) {
        if pendingResumeTime != nil {
            pendingResumeTime = time
            savePlaybackPosition(at: time)
            return
        }
        if isCurrentlyPlayingVideo() {
            videoPlayer.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                             toleranceBefore: .zero,
                             toleranceAfter: .zero)
            setNowPlaying()
            savePlaybackPosition(at: time)
            return
        }
        guard audioPlayer.supportsSeeking else { return }
        audioPlayer.seek(time: time)
        setNowPlaying()
        savePlaybackPosition(at: time)
    }

    /// Points queued files at their new locations after they have been renamed.
    /// `renamedPaths` maps normalized old paths to new paths.
    func updateQueuedFilePaths(_ renamedPaths: [String: String]) {
        var updatedQueue = queue
        var isModified = false
        for index in updatedQueue.indices {
            let key = BatchRenamePlanner.normalizedPath(updatedQueue[index].path)
            guard let newPath = renamedPaths[key] else { continue }
            let newURL = URL(filePath: newPath)
            updatedQueue[index].path = newPath
            updatedQueue[index].name = newURL.deletingPathExtension().lastPathComponent
            isModified = true
        }
        if isModified {
            queue = updatedQueue
            invalidateMetadataCache()
            setNowPlaying()
        }
    }

    func setQueueIDs() {
        for index in 0..<queue.count where queue[index].playbackQueueID.isEmpty {
            queue[index].playbackQueueID = UUID().uuidString
        }
    }

    func setNowPlaying() {
        nonisolated(unsafe) let managerRef = self
        Task { @MainActor in
            await managerRef.setNowPlayingOnMain()
        }
    }

    @MainActor
    private func setNowPlayingOnMain() async {
        // Set remote command center command enable/disable
        let playing = isEnginePlaying()
        remoteCommandCenter.playCommand.isEnabled = canStartPlayback()
        remoteCommandCenter.pauseCommand.isEnabled = playing
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = playing || canStartPlayback()
        remoteCommandCenter.nextTrackCommand.isEnabled = canGoToNextTrack()
        remoteCommandCenter.previousTrackCommand.isEnabled = canGoToPreviousTrack()
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = playing && supportsSeeking()
        // Set now playing info
        let albumArt = albumArt()
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentlyPlayingTitle() ?? ""
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Melodee"
        // The artwork request handler is invoked by MPNowPlayingInfoCenter on its own
        // serial access queue. Build it from a nonisolated context so the closure is not
        // inferred as @MainActor — otherwise Swift's isolation check crashes the process
        // (dispatch_assert_queue) when jpegDataWithSize: calls back off the main actor.
        nowPlayingInfo[MPMediaItemPropertyArtwork] = Self.makeArtwork(from: albumArt)
        if let time = playbackTime() {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time.currentTime
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = time.totalTime
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
    }

    private static func makeArtwork(from image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    func albumArt() -> UIImage {
        if let file = currentlyPlayingFile() {
            refreshMetadataCacheIfNeeded(for: file)
            if let image = cachedAlbumArt {
                return image
            }
        }
        return UIImage(named: "Album.Generic") ?? UIImage()
    }

    // MARK: - State persistence

    /// Restores the queue and position saved in a previous session, paused at the saved time.
    func restorePlaybackState() {
        guard !hasRestoredState, let stateStore else { return }
        hasRestoredState = true
        isRestoringState = true
        repeatMode = stateStore.restoreRepeatMode()
        guard queue.isEmpty else {
            isRestoringState = false
            return
        }
        guard let state = stateStore.restore() else {
            isRestoringState = false
            stateStore.saveQueue([])
            stateStore.savePosition(nil)
            return
        }
        queue = state.queue
        currentlyPlayingID = state.currentlyPlayingID
        pendingResumeTime = state.currentTime ?? 0.0
        pendingTotalTime = state.totalTime
        isPlaybackActive = true
        isPaused = true
        isRestoringState = false
        // Files that are no longer available were dropped, so save the cleaned up queue
        stateStore.saveQueue(queue)
        savePlaybackPosition()
        invalidateMetadataCache()
        setNowPlaying()
    }

    private func clearPendingResume() {
        pendingResumeTime = nil
        pendingTotalTime = nil
    }

    private func scheduleQueueSave() {
        guard !isRestoringState, !isQueueSaveScheduled, stateStore != nil else { return }
        // Coalesce the many mutations made while editing the queue into a single write
        isQueueSaveScheduled = true
        nonisolated(unsafe) let managerRef = self
        Task { @MainActor in
            managerRef.isQueueSaveScheduled = false
            managerRef.stateStore?.saveQueue(managerRef.queue)
            managerRef.savePlaybackPosition()
        }
    }

    private func savePlaybackPosition(at time: TimeInterval? = nil, includesTotalTime: Bool = true) {
        guard !isRestoringState, let stateStore else { return }
        guard !queue.isEmpty, currentlyPlayingFile() != nil else {
            stateStore.savePosition(nil)
            return
        }
        let playbackTime = playbackTime()
        stateStore.savePosition(PersistedPlaybackPosition(
            currentlyPlayingID: currentlyPlayingID,
            currentTime: time ?? playbackTime?.currentTime ?? 0.0,
            totalTime: includesTotalTime ? (playbackTime?.totalTime ?? pendingTotalTime) : nil
        ))
    }

    @objc private func applicationWillSuspend(_ notification: Notification) {
        savePlaybackPosition()
    }

    @objc private func positionSaveTimerFired(_ timer: Timer) {
        if isEnginePlaying() {
            savePlaybackPosition()
        }
    }

    // MARK: - Video playback events

    @objc private func videoPlayerItemDidPlayToEnd(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem, item === videoPlayer.currentItem else { return }
        debugPrint("AVPlayer finished playing video.")
        nonisolated(unsafe) let managerRef = self
        Task { @MainActor in
            managerRef.handleRenderingComplete()
        }
    }

    // MARK: - AudioPlayerDelegate

    func audioPlayer(_ audioPlayer: AudioPlayer, renderingComplete decoder: PCMDecoding) {
        nonisolated(unsafe) let managerRef = self
        Task { @MainActor in
            managerRef.handleRenderingComplete()
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: PCMDecoding?) {
        nonisolated(unsafe) let managerRef = self
        Task { @MainActor in
            managerRef.setNowPlaying()
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
        nonisolated(unsafe) let managerRef = self
        let isNowPaused = playbackState != .playing
        Task { @MainActor in
            // A stale .stopped state may arrive after playback has moved on to a video
            guard !managerRef.isCurrentlyPlayingVideo() else { return }
            managerRef.isPaused = isNowPaused
            if playbackState == .playing {
                managerRef.isPlaybackActive = true
            }
            managerRef.setNowPlaying()
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        debugPrint("SFBAudioEngine error: \(error.localizedDescription)")
    }

    func audioPlayer(
        _ audioPlayer: AudioPlayer,
        audioSessionInterruption notification: Notification,
        userInfo: [AnyHashable: Any]
    ) {
        guard let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        nonisolated(unsafe) let managerRef = self
        switch type {
        case .began:
            Task { @MainActor in managerRef.isPaused = true }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                Task { @MainActor in managerRef.isPaused = false }
            }
        default: ()
        }
    }

    @MainActor
    private func handleRenderingComplete() {
        debugPrint("SFBAudioEngine finished rendering track.")
        let index = currentlyPlayingIndex()
        guard !queue.isEmpty, index < queue.count else {
            debugPrint("Queue is empty or index out of bounds, stopping playback.")
            stop()
            return
        }
        switch repeatMode {
        case .none:
            if index >= queue.count - 1 {
                debugPrint("Reached end of queue.")
                nowPlayingInfoCenter.nowPlayingInfo = nil
                isPlaybackActive = false
                isPaused = true
                savePlaybackPosition(at: 0.0)
            } else {
                debugPrint("Playing next file...")
                playImmediately(queue[index + 1], addToQueue: false)
            }
        case .single:
            debugPrint("Repeating current file...")
            playImmediately(queue[index], addToQueue: false)
        case .all:
            if index >= queue.count - 1 {
                debugPrint("Repeating queue...")
                playImmediately(queue[0], addToQueue: false)
            } else {
                debugPrint("Playing next file...")
                playImmediately(queue[index + 1], addToQueue: false)
            }
        }
    }
}
// swiftlint:enable type_body_length
