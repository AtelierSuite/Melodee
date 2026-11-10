//
//  MacPlayer.swift
//  Melodee
//

import AppKit
import AVFoundation
import SFBAudioEngine

/// Plays a queue of audio and video files and reports its state through `didChangeNotification`.
/// Audio goes through SFBAudioEngine, and video through AVPlayer or VLCKit (the Extended video engine),
/// which `VideoWindowController` shows.
@MainActor
final class MacPlayer: NSObject {

    static let didChangeNotification = Notification.Name("MacPlayerDidChange")

    let audioPlayer = AudioPlayer()
    let videoPlayer = AVPlayer()
    let extendedVideoPlayer = ExtendedVideoPlayer()
    /// Measures the audio player's output for the visualizer while it is on screen.
    let spectrumAnalyzer = SpectrumAnalyzer()
    /// The engine playing the loaded video, chosen from the setting when the video started.
    private(set) var activeVideoEngine: VideoEngine?
    /// The natural size of the playing video, once the video engine knows it.
    var videoSize: CGSize?
    private(set) var queue: [FSFile] = []
    private(set) var currentIndex: Int?
    private(set) var metadata: TrackMetadata?
    var repeatMode: RepeatMode = Preferences.repeatMode {
        didSet {
            Preferences.repeatMode = repeatMode
            notifyChange()
        }
    }

    /// What the previous and next buttons do.
    var skipButtonMode: SkipButtonMode = SkipButtonMode.current {
        didSet {
            SkipButtonMode.current = skipButtonMode
            notifyChange()
        }
    }
    /// Whether the current file looks like a podcast episode or an audiobook, for the automatic skip button mode.
    var isCurrentFileSpokenWord: Bool = false
    var spokenWordDetectionTask: Task<Void, Never>?

    /// Going back within this many seconds of a track starting moves to the previous track instead of restarting.
    private static let restartThreshold: TimeInterval = 3.0

    var videoTimeControlObservation: NSKeyValueObservation?
    var videoItemObservations: [NSKeyValueObservation] = []
    var videoEndObserver: NSObjectProtocol?

    override init() {
        super.init()
        audioPlayer.delegate = self
        setUpVideoPlayer()
        setUpRemoteCommands()
    }

    var currentFile: FSFile? {
        currentIndex.flatMap { queue.indices.contains($0) ? queue[$0] : nil }
    }

    var isPlayingVideo: Bool {
        currentFile?.type == .video
    }

    /// Whether the current file is a video loaded in VLCKit.
    var isPlayingExtendedVideo: Bool {
        isPlayingVideo && activeVideoEngine == .extended
    }

    var isPlaying: Bool {
        if isPlayingExtendedVideo { return extendedVideoPlayer.isPlaying }
        return isPlayingVideo ? videoPlayer.timeControlStatus != .paused : audioPlayer.isPlaying
    }

    var canPlay: Bool {
        !queue.isEmpty
    }

    var canGoToNextTrack: Bool {
        guard let currentIndex else { return false }
        return currentIndex < queue.count - 1 || (repeatMode == .all && !queue.isEmpty)
    }

    var canGoToPreviousTrack: Bool {
        currentIndex != nil
    }

    var playbackTime: (currentTime: TimeInterval, totalTime: TimeInterval)? {
        guard currentFile != nil else { return nil }
        if isPlayingExtendedVideo {
            return extendedVideoPlayer.playbackTime
        }
        if isPlayingVideo {
            guard let item = videoPlayer.currentItem else { return nil }
            let totalTime = item.duration.seconds
            guard totalTime.isFinite, totalTime > 0 else { return nil }
            return (min(max(item.currentTime().seconds, 0), totalTime), totalTime)
        }
        guard let time = audioPlayer.time, time.totalTime.isFinite, time.totalTime > 0 else { return nil }
        return (time.currentTime, time.totalTime)
    }

    var supportsSeeking: Bool {
        if isPlayingExtendedVideo { return extendedVideoPlayer.isSeekable }
        return isPlayingVideo ? videoPlayer.currentItem?.status == .readyToPlay : audioPlayer.supportsSeeking
    }

    // MARK: - Queue

    /// Replaces the queue with the given files and starts playing at `index`.
    func play(_ files: [FSFile], startingAt index: Int = 0) {
        guard files.indices.contains(index) else { return }
        queue = files
        play(at: index)
    }

    func playNext(_ files: [FSFile]) {
        guard currentIndex != nil else {
            play(files)
            return
        }
        let insertionIndex = (currentIndex ?? -1) + 1
        queue.insert(contentsOf: files, at: min(insertionIndex, queue.count))
        notifyChange()
    }

    func playLast(_ files: [FSFile]) {
        guard currentIndex != nil else {
            play(files)
            return
        }
        queue.append(contentsOf: files)
        notifyChange()
    }

    func removeFromQueue(at indexes: IndexSet) {
        let removesCurrent = currentIndex.map(indexes.contains) ?? false
        let removedBeforeCurrent = indexes.count(in: 0..<(currentIndex ?? 0))
        queue.remove(atOffsets: indexes)
        if removesCurrent {
            stop()
        } else if let currentIndex {
            self.currentIndex = currentIndex - removedBeforeCurrent
            notifyChange()
        }
    }

    /// Moves tracks to a new place in the queue, keeping the playing track playing.
    func moveQueueItems(at indexes: IndexSet, to destination: Int) {
        var entries = Array(queue.enumerated())
        let moved = indexes.sorted().map { entries[$0] }
        let insertionIndex = destination - indexes.count(in: 0..<destination)
        entries.remove(atOffsets: indexes)
        entries.insert(contentsOf: moved, at: min(insertionIndex, entries.count))
        queue = entries.map(\.element)
        if let currentIndex {
            self.currentIndex = entries.firstIndex { $0.offset == currentIndex }
        }
        notifyChange()
    }

    /// Points queued tracks at their new locations after files or folders have been moved.
    func updateQueuedPaths(afterMoving movedPaths: [String: String]) {
        guard !movedPaths.isEmpty else { return }
        for index in queue.indices {
            if let newPath = FilesystemManager.movedPath(for: queue[index].path, in: movedPaths) {
                queue[index].path = newPath
                queue[index].name = URL(filePath: newPath).deletingPathExtension().lastPathComponent
            }
        }
        notifyChange()
    }

    /// Reads the playing track's tags again if they were just edited.
    func refreshMetadata(forPaths paths: Set<String>) {
        guard let currentFile, paths.contains(currentFile.path) else { return }
        metadata = TrackMetadata(file: currentFile)
        detectSpokenWord()
        notifyChange()
    }

    func clearQueue() {
        stop()
    }

    // MARK: - Transport

    func play(at index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        let file = queue[index]
        metadata = TrackMetadata(file: file)
        detectSpokenWord()
        if file.type == .video {
            audioPlayer.stop()
            if VideoEngine.current == .extended {
                stopVideo()
                activeVideoEngine = .extended
                videoSize = nil
                extendedVideoPlayer.play(url: URL(filePath: file.path), from: nil)
            } else {
                extendedVideoPlayer.stop()
                activeVideoEngine = .standard
                playVideo(at: URL(filePath: file.path))
            }
            notifyChange()
            return
        }
        stopVideo()
        extendedVideoPlayer.stop()
        activeVideoEngine = nil
        do {
            try audioPlayer.play(URL(filePath: file.path))
        } catch {
            debugPrint("Failed to start playback: \(error.localizedDescription)")
            handlePlaybackFailure()
            return
        }
        notifyChange()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        if isPlayingExtendedVideo, extendedVideoPlayer.hasMedia {
            extendedVideoPlayer.resume()
        } else if isPlayingVideo, let item = videoPlayer.currentItem {
            // Start over if the video already played to the end
            if item.duration.isNumeric, item.currentTime() >= item.duration {
                videoPlayer.seek(to: .zero)
            }
            videoPlayer.play()
        } else if audioPlayer.isPaused {
            audioPlayer.resume()
        } else if let currentIndex {
            play(at: currentIndex)
        } else if !queue.isEmpty {
            play(at: 0)
        }
        notifyChange()
    }

    func pause() {
        audioPlayer.pause()
        videoPlayer.pause()
        extendedVideoPlayer.pause()
        notifyChange()
    }

    func stop() {
        audioPlayer.stop()
        stopVideo()
        extendedVideoPlayer.stop()
        activeVideoEngine = nil
        queue.removeAll()
        currentIndex = nil
        metadata = nil
        detectSpokenWord()
        notifyChange()
    }

    func skipToNextTrack() {
        guard let currentIndex else { return }
        if currentIndex < queue.count - 1 {
            play(at: currentIndex + 1)
        } else if repeatMode == .all, !queue.isEmpty {
            play(at: 0)
        }
    }

    func backToPreviousTrack() {
        guard let currentIndex else { return }
        if let time = playbackTime, time.currentTime > Self.restartThreshold || currentIndex == 0 {
            seek(to: 0)
        } else {
            play(at: currentIndex - 1)
        }
    }

    func seek(to time: TimeInterval) {
        guard supportsSeeking else { return }
        if isPlayingExtendedVideo {
            extendedVideoPlayer.seek(to: time)
        } else if isPlayingVideo {
            videoPlayer.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                             toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in self?.notifyChange() }
            }
        } else {
            audioPlayer.seek(time: time)
        }
        notifyChange()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .none: repeatMode = .all
        case .all: repeatMode = .single
        case .single: repeatMode = .none
        }
    }

    func handlePlaybackFailure() {
        if let currentIndex, currentIndex < queue.count - 1 {
            play(at: currentIndex + 1)
        } else {
            stop()
        }
    }

    /// Moves on once a track finishes, following the repeat mode.
    func handleRenderingComplete() {
        guard let currentIndex else { return }
        switch repeatMode {
        case .single:
            play(at: currentIndex)
        case .all:
            play(at: currentIndex < queue.count - 1 ? currentIndex + 1 : 0)
        case .none:
            if currentIndex < queue.count - 1 {
                play(at: currentIndex + 1)
            } else {
                notifyChange()
            }
        }
    }

    // MARK: - Visualizer

    /// Starts measuring the audio output for a visualizer that came on screen.
    /// Balance each call with ``stopSpectrumAnalysis()``.
    func startSpectrumAnalysis() {
        spectrumAnalyzer.start(on: audioPlayer)
    }

    func stopSpectrumAnalysis() {
        spectrumAnalyzer.stop(on: audioPlayer)
    }

    func notifyChange() {
        updateNowPlaying()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

extension MacPlayer: AudioPlayer.Delegate {

    nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, renderingComplete decoder: PCMDecoding) {
        Task { @MainActor in
            self.handleRenderingComplete()
        }
    }

    nonisolated func audioPlayer(
        _ audioPlayer: AudioPlayer,
        playbackStateChanged playbackState: AudioPlayer.PlaybackState
    ) {
        Task { @MainActor in
            self.notifyChange()
        }
    }

    nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, audioEngineConfigurationChange userInfo: [AnyHashable: Any]?) {
        Task { @MainActor in
            // The mixer's output format may have changed with the output device
            self.spectrumAnalyzer.reconfigure(on: self.audioPlayer)
        }
    }

    nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        debugPrint("SFBAudioEngine error: \(error.localizedDescription)")
    }
}
