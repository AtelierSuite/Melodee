@preconcurrency import AVFAudio
import AVKit
import Foundation
@preconcurrency import MediaPlayer
import SFBAudioEngine
import UIKit

@Observable
class MediaPlayerManager: NSObject, AudioPlayer.Delegate {

    @ObservationIgnored let notificationCenter = NotificationCenter.default
    @ObservationIgnored let audioSession = AVAudioSession.sharedInstance()
    @ObservationIgnored let remoteCommandCenter = MPRemoteCommandCenter.shared()
    @ObservationIgnored let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    @ObservationIgnored let audioPlayer: AudioPlayer
    /// Measures the audio player's output for the Now Playing visualizer while it is on screen.
    @ObservationIgnored let spectrumAnalyzer = SpectrumAnalyzer()
    @ObservationIgnored let videoPlayer: AVPlayer
    /// Draws the standard engine's video. It is reused by the Now Playing sheet so that
    /// Picture in Picture keeps running when the sheet is dismissed.
    @ObservationIgnored let videoPlayerView: VideoPlayerView
    @ObservationIgnored private let videoPictureInPictureController: AVPictureInPictureController?
    @ObservationIgnored let extendedVideoPlayer = ExtendedVideoPlayer()
    @ObservationIgnored var downloadManager: FileDownloadManager?
    @ObservationIgnored var stateStore: PlaybackStateStore? {
        didSet {
            stateStore?.onPlayTimesChange = { [weak self] in
                self?.playTimesRevision += 1
            }
        }
    }
    /// Changes whenever a saved play time changes, so views showing playback progress refresh.
    var playTimesRevision: Int = 0
    var isPlaybackActive: Bool = false
    var isPaused: Bool = true
    var repeatMode: RepeatMode = .none {
        didSet {
            if !isRestoringState { stateStore?.saveRepeatMode(repeatMode) }
            remoteCommandCenter.changeRepeatModeCommand.currentRepeatType = repeatMode.remoteRepeatType
        }
    }
    var queue: [FSFile] = [] {
        didSet { scheduleQueueSave() }
    }
    var currentlyPlayingID: String = "" {
        didSet {
            if currentlyPlayingID != oldValue {
                // The engine may still report the previous file's duration, so leave it out
                savePlaybackPosition(at: 0.0, includesTotalTime: false)
                detectSpokenWord()
            }
        }
    }
    var metadataRefreshTrigger: UUID = UUID()
    var videoAspectRatio: CGFloat?
    /// The engine playing the loaded video, chosen from the setting when the video was loaded.
    var activeVideoEngine: VideoEngine?
    /// Set when the user picks a file that was previously stopped partway through, to ask where to start.
    var resumePrompt: ResumePlaybackPrompt?
    /// What the previous and next buttons do.
    var skipButtonMode: SkipButtonMode = SkipButtonMode.current {
        didSet {
            SkipButtonMode.current = skipButtonMode
            setNowPlaying()
        }
    }
    /// Whether the current file looks like a podcast episode or an audiobook, for the automatic skip button mode.
    var isCurrentFileSpokenWord: Bool = false

    /// Where playback of a file starts.
    enum StartPosition {
        /// Continue from the saved play time only if the setting says to always continue.
        case automatic
        case beginning
        case time(TimeInterval)
    }

    @ObservationIgnored private var cachedMetadataID: String = ""
    @ObservationIgnored private var cachedTitle: String?
    @ObservationIgnored private var cachedArtist: String?
    @ObservationIgnored private var cachedAlbum: String?
    @ObservationIgnored private var cachedAlbumArt: UIImage?
    @ObservationIgnored private var videoItemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var videoTimeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var videoPresentationSizeObservation: NSKeyValueObservation?
    @ObservationIgnored var spokenWordDetectionTask: Task<Void, Never>?

    // Restored position that is applied once the engine loads the current file
    @ObservationIgnored private var pendingResumeTime: TimeInterval?
    @ObservationIgnored private var pendingTotalTime: TimeInterval?
    @ObservationIgnored private var isRestoringState: Bool = false
    @ObservationIgnored private var hasRestoredState: Bool = false
    @ObservationIgnored private var isQueueSaveScheduled: Bool = false
    @ObservationIgnored private var positionSaveTimer: Timer?
    // The file the engine has loaded, whose play time is tracked so it can be continued later
    @ObservationIgnored private var playTimeTrackedFile: FSFile?

    /// How many times normal speed playback moves at while the fast forward or rewind buttons are held.
    static let scrubRate: Double = 2.0
    /// How a held fast forward or rewind button moves through the current file.
    private enum ScrubMode {
        /// The audio is played sped up, or reversed, by the scrub audio player while the main player is paused.
        case audio
        /// The video engine itself plays faster, or backwards.
        case videoRate
        /// The position moves in steps, for files that can't be played sped up or backwards.
        case stepped
    }
    @ObservationIgnored private let scrubAudioPlayer = ScrubAudioPlayer()
    @ObservationIgnored private var scrubMode: ScrubMode?
    @ObservationIgnored private var scrubDirection: ScrubDirection = .forward
    @ObservationIgnored private var scrubTotalTime: TimeInterval = 0
    @ObservationIgnored private var scrubPosition: TimeInterval = 0
    @ObservationIgnored private var scrubResumesPlayback: Bool = false
    @ObservationIgnored private var scrubStepTimer: Timer?
    @ObservationIgnored private var scrubStepDate: Date = .distantPast

    override init() {
        // SFBAudioEngine prepares its audio engine as soon as the player is created, which in the
        // default non-mixable category interrupts audio from other apps when Melodee is opened.
        // Start out mixable, and take over the audio session only when playback starts.
        Self.configureAudioSessionForLaunch()
        self.audioPlayer = AudioPlayer()
        let videoPlayer = AVPlayer()
        self.videoPlayer = videoPlayer
        let videoPlayerView = MainActor.assumeIsolated {
            VideoPlayerView(player: videoPlayer)
        }
        self.videoPlayerView = videoPlayerView
        // Move the playing video into Picture in Picture when the app is backgrounded
        nonisolated(unsafe) var pictureInPictureController: AVPictureInPictureController?
        MainActor.assumeIsolated {
            if AVPictureInPictureController.isPictureInPictureSupported() {
                pictureInPictureController = AVPictureInPictureController(playerLayer: videoPlayerView.playerLayer)
                pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = true
            }
        }
        videoPictureInPictureController = pictureInPictureController
        super.init()
        audioPlayer.delegate = self
        // By default AVPlayer pauses a video when the app is backgrounded or the screen is
        // locked unless Picture in Picture is active, so keep its audio playing instead
        videoPlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        // Advance the queue when a video finishes playing
        notificationCenter.addObserver(self,
                                       selector: #selector(videoPlayerItemDidPlayToEnd(_:)),
                                       name: .AVPlayerItemDidPlayToEndTime,
                                       object: nil)
        // Keep isPaused in sync when the video is paused/resumed from the
        // Picture in Picture window or the system's Now Playing controls
        videoTimeControlObservation = videoPlayer.observe(\.timeControlStatus) { [weak self] player, _ in
            guard let self else { return }
            nonisolated(unsafe) let managerRef = self
            let isNowPaused = player.timeControlStatus == .paused
            Task { @MainActor in
                guard managerRef.isCurrentlyPlayingVideo(), managerRef.activeVideoEngine == .standard,
                      !managerRef.isScrubbing else { return }
                managerRef.isPaused = isNowPaused
                managerRef.setNowPlaying()
            }
        }
        setUpExtendedVideoPlayer()
        setUpRemoteCommands()
        // Pause when headphones are disconnected (e.g. AirPods removed or put back in the case)
        notificationCenter.addObserver(self,
                                       selector: #selector(audioSessionRouteDidChange(_:)),
                                       name: AVAudioSession.routeChangeNotification,
                                       object: audioSession)
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

    private func setUpExtendedVideoPlayer() {
        extendedVideoPlayer.onFinished = { [weak self] in
            debugPrint("VLCKit finished playing video.")
            guard let self else { return }
            nonisolated(unsafe) let managerRef = self
            MainActor.assumeIsolated { managerRef.handleRenderingComplete() }
        }
        extendedVideoPlayer.onFailed = { [weak self] in
            guard let self, self.isPlayingExtendedVideo() else { return }
            debugPrint("VLCKit failed to play video.")
            self.handlePlaybackFailure()
        }
        extendedVideoPlayer.onPausedChanged = { [weak self] isNowPaused in
            guard let self, self.isPlayingExtendedVideo(), !self.isScrubbing else { return }
            self.isPaused = isNowPaused
            self.setNowPlaying()
        }
        extendedVideoPlayer.onVideoSizeChanged = { [weak self] size in
            guard let self, self.isPlayingExtendedVideo() else { return }
            self.videoAspectRatio = size.width / size.height
        }
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
            // Always pause so the Now Playing state is corrected even if the engine already stopped
            self.pause()
            return .success
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
        // Only one of the track and skip command pairs is enabled at a time, following the skip button mode
        let skipIntervals = [NSNumber(value: SkipButtonMode.interval)]
        remoteCommandCenter.skipForwardCommand.preferredIntervals = skipIntervals
        remoteCommandCenter.skipBackwardCommand.preferredIntervals = skipIntervals
        remoteCommandCenter.skipForwardCommand.addTarget { _ in
            self.skipForward()
            return .success
        }
        remoteCommandCenter.skipBackwardCommand.addTarget { _ in
            self.skipBackward()
            return .success
        }
        remoteCommandCenter.changePlaybackPositionCommand.addTarget { event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self.seekTo(event.positionTime)
                return .success
            }
            return .commandFailed
        }
        remoteCommandCenter.changeRepeatModeCommand.addTarget { event in
            if let event = event as? MPChangeRepeatModeCommandEvent {
                self.repeatMode = RepeatMode(remoteRepeatType: event.repeatType)
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
        detectSpokenWord()
    }

    func currentlyPlayingFile() -> FSFile? {
        return queue.first(where: { $0.playbackQueueID == currentlyPlayingID })
    }

    func isCurrentlyPlayingVideo() -> Bool {
        return currentlyPlayingFile()?.type == .video
    }

    /// Whether the current file is a video loaded in VLCKit.
    private func isPlayingExtendedVideo() -> Bool {
        return isCurrentlyPlayingVideo() && activeVideoEngine == .extended
    }

    func isEnginePlaying() -> Bool {
        return audioPlayer.isPlaying || videoPlayer.timeControlStatus != .paused || extendedVideoPlayer.isPlaying
    }

    func supportsSeeking() -> Bool {
        if pendingResumeTime != nil {
            return true
        }
        if isPlayingExtendedVideo() {
            return extendedVideoPlayer.isSeekable
        }
        if isCurrentlyPlayingVideo() {
            return videoPlayer.currentItem != nil
        }
        return audioPlayer.supportsSeeking
    }

    func playbackTime() -> (currentTime: TimeInterval, totalTime: TimeInterval)? {
        if let scrubTime = scrubbingTime() {
            return (scrubTime, scrubTotalTime)
        }
        // The restored file isn't loaded until playback starts, so report the saved position
        if let pendingResumeTime {
            guard let pendingTotalTime, pendingTotalTime > 0 else { return nil }
            return (min(pendingResumeTime, pendingTotalTime), pendingTotalTime)
        }
        if isPlayingExtendedVideo() {
            return extendedVideoPlayer.playbackTime
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

    /// How far through the file playback last got, from 0 to 1, if it can be continued.
    func savedPlayProgress(for file: FSFile) -> Double? {
        _ = playTimesRevision
        guard file.type == .audio || file.type == .video else { return nil }
        return stateStore?.playProgress(for: file)
    }

    /// Plays a file the user picked, first asking where to start if it was previously stopped partway through.
    func requestPlay(_ file: FSFile,
                     addToQueue: Bool = true,
                     source: ResumePlaybackPrompt.Source = .fileBrowser) {
        // Save the current file's position first, in case it is the one being played again
        recordPlayTime()
        guard let playTime = stateStore?.playTime(for: file) else {
            playImmediately(file, addToQueue: addToQueue, startingAt: .beginning)
            return
        }
        switch ResumePlaybackBehavior.current {
        case .ask:
            resumePrompt = ResumePlaybackPrompt(file: file,
                                                addToQueue: addToQueue,
                                                playTime: playTime,
                                                source: source)
        case .startFromBeginning:
            playImmediately(file, addToQueue: addToQueue, startingAt: .beginning)
        case .continueFromLastPosition:
            playImmediately(file, addToQueue: addToQueue, startingAt: .time(playTime))
        }
    }

    /// Plays the file the resume prompt asked about, from where the user chose.
    func answerResumePrompt(continueFromLastPosition: Bool) {
        guard let prompt = resumePrompt else { return }
        resumePrompt = nil
        playImmediately(prompt.file,
                        addToQueue: prompt.addToQueue,
                        startingAt: continueFromLastPosition ? .time(prompt.playTime) : .beginning)
    }

    func playImmediately(_ file: FSFile, addToQueue: Bool = true, startingAt position: StartPosition = .automatic) {
        // Save how far the outgoing file got before stopping it
        recordPlayTime()
        playTimeTrackedFile = nil
        cancelScrubbing()
        let startTime = startTime(for: file, at: position)
        // Stop any playback that is in progress
        audioPlayer.stop()
        videoPlayer.pause()
        extendedVideoPlayer.pause()
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
                self?.loadAndPlay(file, from: startTime)
            }
            return
        }
        loadAndPlay(file, from: startTime)
    }

    private func startTime(for file: FSFile, at position: StartPosition) -> TimeInterval? {
        switch position {
        case .automatic:
            guard ResumePlaybackBehavior.current == .continueFromLastPosition else { return nil }
            return stateStore?.playTime(for: file)
        case .beginning:
            return nil
        case .time(let time):
            return time
        }
    }

    private func loadAndPlay(_ file: FSFile, from startTime: TimeInterval? = nil) {
        activateAudioSession()
        let url = URL(fileURLWithPath: file.path)
        let startTime = startTime.flatMap { $0 > 0 ? $0 : nil }
        if file.type == .video, VideoEngine.current == .extended {
            audioPlayer.stop()
            unloadStandardVideo()
            activeVideoEngine = .extended
            extendedVideoPlayer.play(url: url, from: startTime)
            playTimeTrackedFile = file
            isPlaybackActive = true
            isPaused = false
            setNowPlaying()
            return
        }
        extendedVideoPlayer.stop()
        if file.type == .video {
            audioPlayer.stop()
            activeVideoEngine = .standard
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
            playTimeTrackedFile = file
            isPlaybackActive = true
            isPaused = false
            setNowPlaying()
            return
        }
        unloadStandardVideo()
        activeVideoEngine = nil
        do {
            try playAudio(at: url, from: startTime)
            playTimeTrackedFile = file
            isPlaybackActive = true
            isPaused = false
            setNowPlaying()
        } catch {
            debugPrint("Failed to start playback: \(error.localizedDescription)")
            handlePlaybackFailure()
        }
    }

    private func unloadStandardVideo() {
        videoPlayer.replaceCurrentItem(with: nil)
        videoItemStatusObservation = nil
        videoPresentationSizeObservation = nil
        videoAspectRatio = nil
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

    private static func configureAudioSessionForLaunch() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
        } catch {
            debugPrint(error.localizedDescription)
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
        if isPlayingExtendedVideo(), extendedVideoPlayer.hasMedia {
            extendedVideoPlayer.resume()
            isPlaybackActive = true
            isPaused = false
            setNowPlaying()
            return
        }
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
        playTimeTrackedFile = nil
        // A position restored from the previous session takes precedence over the saved play time
        let resumeTime = pendingResumeTime ?? startTime(for: file, at: .automatic)
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
        extendedVideoPlayer.pause()
        isPaused = true
        setNowPlaying()
        savePlaybackPosition()
        recordPlayTime()
    }

    func stop() {
        cancelScrubbing()
        recordPlayTime()
        playTimeTrackedFile = nil
        audioPlayer.stop()
        unloadStandardVideo()
        extendedVideoPlayer.stop()
        activeVideoEngine = nil
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
        if isPlayingExtendedVideo() {
            extendedVideoPlayer.seek(to: time)
            setNowPlaying()
            savePlaybackPosition(at: time)
            recordPlayTime(at: time)
            return
        }
        if isCurrentlyPlayingVideo() {
            videoPlayer.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                             toleranceBefore: .zero,
                             toleranceAfter: .zero)
            setNowPlaying()
            savePlaybackPosition(at: time)
            recordPlayTime(at: time)
            return
        }
        guard audioPlayer.supportsSeeking else { return }
        audioPlayer.seek(time: time)
        setNowPlaying()
        savePlaybackPosition(at: time)
        recordPlayTime(at: time)
    }

    // MARK: - Scrubbing

    /// Whether a fast forward or rewind button is being held.
    var isScrubbing: Bool {
        return scrubMode != nil
    }

    /// Starts moving through the current file at `scrubRate` times normal speed, while a button is held.
    /// Audio is heard while doing so, played backwards when rewinding.
    func beginScrubbing(_ direction: ScrubDirection) {
        cancelScrubbing()
        guard isPlaybackActive, supportsSeeking(),
              let file = currentlyPlayingFile(), let time = playbackTime() else { return }
        scrubDirection = direction
        scrubTotalTime = time.totalTime
        scrubResumesPlayback = !isPaused
        activateAudioSession()
        let isFileLoaded = pendingResumeTime == nil
        if file.type == .video, isFileLoaded, beginVideoRateScrubbing(direction) {
            return
        }
        // Keep the engines paused where they are, without marking playback as paused
        audioPlayer.pause()
        videoPlayer.pause()
        extendedVideoPlayer.pause()
        if file.type != .video, !file.isEvicted() {
            do {
                try scrubAudioPlayer.start(url: URL(fileURLWithPath: file.path),
                                           at: time.currentTime,
                                           direction: direction,
                                           rate: Float(Self.scrubRate))
                scrubMode = .audio
                return
            } catch {
                debugPrint("Failed to play audio while scrubbing: \(error.localizedDescription)")
            }
        }
        scrubMode = .stepped
        scrubPosition = time.currentTime
        scrubStepDate = .now
        scrubStepTimer = Timer.scheduledTimer(timeInterval: 0.1,
                                              target: self,
                                              selector: #selector(scrubStepTimerFired(_:)),
                                              userInfo: nil,
                                              repeats: true)
    }

    /// Plays the loaded video faster, or backwards, if its engine can.
    private func beginVideoRateScrubbing(_ direction: ScrubDirection) -> Bool {
        let rate = Float(direction == .forward ? Self.scrubRate : -Self.scrubRate)
        if isPlayingExtendedVideo() {
            // VLCKit can't play backwards
            guard direction == .forward, extendedVideoPlayer.hasMedia else { return false }
            scrubMode = .videoRate
            extendedVideoPlayer.setRate(rate)
            extendedVideoPlayer.resume()
            return true
        }
        guard let item = videoPlayer.currentItem, item.status == .readyToPlay,
              direction == .forward ? item.canPlayFastForward : item.canPlayFastReverse else { return false }
        scrubMode = .videoRate
        videoPlayer.rate = rate
        return true
    }

    /// Stops scrubbing where it got to, and carries on playing from there if it was playing before.
    func endScrubbing() {
        guard let mode = scrubMode else { return }
        let position = scrubbingTime()
        stopScrubbing()
        switch mode {
        case .audio, .stepped:
            if let position {
                // Stay just short of the end, so the file finishes playing normally if playback resumes
                seekTo(min(position, max(0, scrubTotalTime - 0.1)))
            }
            if scrubResumesPlayback {
                play()
            } else {
                setNowPlaying()
            }
        case .videoRate:
            if isPlayingExtendedVideo() {
                extendedVideoPlayer.setRate(1.0)
                if !scrubResumesPlayback {
                    extendedVideoPlayer.pause()
                }
            } else if scrubResumesPlayback {
                videoPlayer.rate = 1.0
            } else {
                videoPlayer.pause()
            }
            isPaused = !scrubResumesPlayback
            setNowPlaying()
            savePlaybackPosition()
            recordPlayTime()
        }
    }

    /// Stops scrubbing without moving playback, as the file is being changed or stopped.
    private func cancelScrubbing() {
        guard scrubMode != nil else { return }
        if scrubMode == .videoRate {
            extendedVideoPlayer.setRate(1.0)
        }
        stopScrubbing()
    }

    private func stopScrubbing() {
        scrubMode = nil
        scrubStepTimer?.invalidate()
        scrubStepTimer = nil
        scrubAudioPlayer.stop()
    }

    /// The position scrubbing has reached, when it is tracked separately from the engines.
    private func scrubbingTime() -> TimeInterval? {
        switch scrubMode {
        case .audio: return scrubAudioPlayer.currentTime
        case .stepped: return scrubPosition
        case .videoRate, nil: return nil
        }
    }

    @objc private func scrubStepTimerFired(_ timer: Timer) {
        guard scrubMode == .stepped else { return }
        let now = Date.now
        let distance = now.timeIntervalSince(scrubStepDate) * Self.scrubRate
        scrubStepDate = now
        let target = scrubDirection == .forward ? scrubPosition + distance : scrubPosition - distance
        scrubPosition = min(max(0, target), scrubTotalTime)
        // Show the frame at the new position
        guard isCurrentlyPlayingVideo(), pendingResumeTime == nil else { return }
        if isPlayingExtendedVideo() {
            extendedVideoPlayer.seek(to: scrubPosition)
        } else {
            videoPlayer.seek(to: CMTime(seconds: scrubPosition, preferredTimescale: 600))
        }
    }

    /// Points queued files at their new locations after they have been renamed.
    /// `renamedPaths` maps normalized old paths to new paths.
    func updateQueuedFilePaths(_ renamedPaths: [String: String]) {
        stateStore?.movePlayTimes { renamedPaths[$0] }
        applyQueuedPathChanges(renamedPaths)
    }

    /// Points queued files at their new locations after files or folders have been moved.
    func updateQueuedFilePaths(afterMoving movedPaths: [String: String]) {
        stateStore?.movePlayTimes { FilesystemManager.movedPath(for: $0, in: movedPaths) }
        var renamedPaths: [String: String] = [:]
        for file in queue {
            if let newPath = FilesystemManager.movedPath(for: file.path, in: movedPaths) {
                renamedPaths[FilesystemManager.normalizedPath(file.path)] = newPath
            }
        }
        applyQueuedPathChanges(renamedPaths)
    }

    /// `renamedPaths` maps normalized old paths to new paths.
    private func applyQueuedPathChanges(_ renamedPaths: [String: String]) {
        if let trackedFile = playTimeTrackedFile,
           let newPath = renamedPaths[FilesystemManager.normalizedPath(trackedFile.path)] {
            playTimeTrackedFile?.path = newPath
        }
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
        let skipsByInterval = skipsByInterval()
        remoteCommandCenter.nextTrackCommand.isEnabled = !skipsByInterval && canGoToNextTrack()
        remoteCommandCenter.previousTrackCommand.isEnabled = !skipsByInterval && canGoToPreviousTrack()
        let canSkipByInterval = skipsByInterval && isPlaybackActive && supportsSeeking()
        remoteCommandCenter.skipForwardCommand.isEnabled = canSkipByInterval
        remoteCommandCenter.skipBackwardCommand.isEnabled = canSkipByInterval
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
        if !queue.isEmpty {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = currentlyPlayingIndex()
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count
        }
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

    /// The current file's embedded artwork, or nil if it has none.
    func embeddedAlbumArt() -> UIImage? {
        guard let file = currentlyPlayingFile() else { return nil }
        refreshMetadataCacheIfNeeded(for: file)
        return cachedAlbumArt
    }

    // MARK: - Visualizer

    /// Starts measuring the audio output for a visualizer that came on screen.
    /// Balance each call with ``stopSpectrumAnalysis()``.
    @MainActor
    func startSpectrumAnalysis() {
        spectrumAnalyzer.start(on: audioPlayer)
    }

    @MainActor
    func stopSpectrumAnalysis() {
        spectrumAnalyzer.stop(on: audioPlayer)
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

    /// Reloads the current file if it's the one at `path`, which was changed in place, for example by trimming.
    /// The player otherwise keeps playing the old contents. The queue is kept, the file starts again from the
    /// beginning, and playback carries on if it was playing.
    func fileDidChangeOnDisk(atPath path: String) {
        guard let file = currentlyPlayingFile(),
              FilesystemManager.normalizedPath(file.path) == FilesystemManager.normalizedPath(path) else { return }
        cancelScrubbing()
        let wasPlaying = isPlaybackActive && !isPaused
        recordPlayTime()
        playTimeTrackedFile = nil
        audioPlayer.stop()
        unloadStandardVideo()
        extendedVideoPlayer.stop()
        activeVideoEngine = nil
        // Start from the top, since a saved position may lie past the end of the trimmed file
        pendingResumeTime = 0
        pendingTotalTime = nil
        isPaused = true
        invalidateMetadataCache()
        setNowPlaying()
        if wasPlaying {
            play()
        }
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

    /// Remembers how far into the loaded file playback got, so it can be continued the next time it is played.
    private func recordPlayTime(at time: TimeInterval? = nil) {
        guard let file = playTimeTrackedFile, let stateStore,
              let playbackTime = playbackTime() else { return }
        stateStore.savePlayTime(time ?? playbackTime.currentTime, totalTime: playbackTime.totalTime, for: file)
    }

    @objc private func applicationWillSuspend(_ notification: Notification) {
        savePlaybackPosition()
        recordPlayTime()
    }

    @objc private func positionSaveTimerFired(_ timer: Timer) {
        if isEnginePlaying() {
            savePlaybackPosition()
            recordPlayTime()
        }
    }

    // MARK: - Audio session events

    @objc private func audioSessionRouteDidChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: reasonValue) == .oldDeviceUnavailable else {
            return
        }
        nonisolated(unsafe) let managerRef = self
        Task { @MainActor in
            guard managerRef.isPlaybackActive, !managerRef.isPaused else { return }
            debugPrint("Audio output device became unavailable, pausing playback.")
            managerRef.pause()
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
            guard !managerRef.isCurrentlyPlayingVideo(), !managerRef.isScrubbing else { return }
            managerRef.isPaused = isNowPaused
            if playbackState == .playing {
                managerRef.isPlaybackActive = true
            }
            managerRef.setNowPlaying()
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, audioEngineConfigurationChange userInfo: [AnyHashable: Any]?) {
        nonisolated(unsafe) let managerRef = self
        Task { @MainActor in
            guard !managerRef.isCurrentlyPlayingVideo() else { return }
            // The engine restores its previous state after a route change without reporting it,
            // which can undo a pause that arrived while it was reconfiguring
            if managerRef.isPaused, managerRef.audioPlayer.isPlaying {
                managerRef.audioPlayer.pause()
            }
            // The mixer's output format may have changed with the output hardware
            managerRef.spectrumAnalyzer.reconfigure(on: managerRef.audioPlayer)
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
        // The file played to the end, so the next time it is played it starts from the beginning
        if let finishedFile = playTimeTrackedFile {
            stateStore?.removePlayTime(for: finishedFile)
            playTimeTrackedFile = nil
        }
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
