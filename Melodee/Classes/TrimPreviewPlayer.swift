@preconcurrency import AVFoundation
import Foundation
import SFBAudioEngine

/// Plays the part of a file being trimmed, separately from the main player so the queue is left alone.
/// Audio plays through SFBAudioEngine, like the main player, and video through AVPlayer.
@Observable
@MainActor
final class TrimPreviewPlayer {

    private(set) var isPlaying: Bool = false
    /// The playhead, in seconds from the start of the file.
    var currentTime: TimeInterval = 0

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let isVideo: Bool
    @ObservationIgnored private let audioPlayer = AudioPlayer()
    @ObservationIgnored private var videoPlayer: AVPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var endTime: TimeInterval = .infinity
    @ObservationIgnored private var playbackStartDate: Date = .distantPast

    init(url: URL, isVideo: Bool) {
        self.url = url
        self.isVideo = isVideo
    }

    /// Plays from the playhead until `end`, then stops there.
    func play(until end: TimeInterval) {
        endTime = end
        do {
            if isVideo {
                let player = videoPlayer ?? AVPlayer(url: url)
                videoPlayer = player
                player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
                player.play()
            } else {
                let decoder = try AudioDecoder(url: url)
                try decoder.open()
                let frame = AVAudioFramePosition(currentTime * decoder.processingFormat.sampleRate)
                if decoder.supportsSeeking, frame > 0, frame < decoder.length {
                    try decoder.seek(to: frame)
                }
                try audioPlayer.play(decoder)
            }
        } catch {
            debugPrint("Trim preview failed to play: \(error.localizedDescription)")
            return
        }
        isPlaying = true
        playbackStartDate = .now
        startTimer()
    }

    func pause() {
        audioPlayer.pause()
        videoPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    /// Moves the playhead. Playback, if any, continues from there.
    func seek(to time: TimeInterval) {
        currentTime = time
        guard isPlaying else { return }
        if isVideo {
            videoPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            audioPlayer.seek(time: time)
        }
    }

    func stop() {
        audioPlayer.stop()
        videoPlayer?.pause()
        videoPlayer = nil
        isPlaying = false
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let time: TimeInterval?
        if isVideo {
            time = videoPlayer.map { $0.currentTime().seconds }
        } else {
            time = audioPlayer.time?.currentTime
        }
        if let time, time.isFinite {
            currentTime = time
        }
        // The audio player takes a moment to start, so only treat it stopping as the end after that
        let hasAudioEnded = !isVideo && !audioPlayer.isPlaying && Date.now.timeIntervalSince(playbackStartDate) > 0.5
        if currentTime >= endTime || hasAudioEnded {
            currentTime = min(currentTime, endTime)
            pause()
        }
    }
}
