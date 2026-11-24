//
//  MacPlayer+Video.swift
//  Melodee
//

import AVFoundation

extension MacPlayer {

    /// Keeps the play state in sync when the video is controlled from its own window,
    /// and moves on once a video finishes.
    func setUpVideoPlayer() {
        setUpExtendedVideoPlayer()
        subtitleController.onChange = { [weak self] in
            self?.notifyChange()
        }
        subtitleController.replacePlayerAsset = { [weak self] asset in
            self?.replaceVideoAsset(with: asset)
        }
        videoTimeControlObservation = videoPlayer.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isPlayingVideo, !self.isPlayingExtendedVideo else { return }
                self.notifyChange()
            }
        }
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, let item, item === self.videoPlayer.currentItem else { return }
                self.handleRenderingComplete()
            }
        }
    }

    /// Routes VLCKit's events into the same handling as AVPlayer's. VLCKit delivers them on the main queue.
    private func setUpExtendedVideoPlayer() {
        extendedVideoPlayer.onFinished = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPlayingExtendedVideo else { return }
                self.handleRenderingComplete()
            }
        }
        extendedVideoPlayer.onFailed = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPlayingExtendedVideo else { return }
                debugPrint("VLCKit failed to play video.")
                self.handlePlaybackFailure()
            }
        }
        extendedVideoPlayer.onPausedChanged = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlayingExtendedVideo else { return }
                self.notifyChange()
            }
        }
        extendedVideoPlayer.onVideoSizeChanged = { [weak self] size in
            MainActor.assumeIsolated {
                guard let self, self.isPlayingExtendedVideo, size != self.videoSize else { return }
                self.videoSize = size
                self.notifyChange()
            }
        }
        extendedVideoPlayer.onTextTracksChanged = { [weak self] tracks in
            MainActor.assumeIsolated {
                guard let self, self.isPlayingExtendedVideo else { return }
                self.subtitleController.updateExtendedTextTracks(tracks)
            }
        }
    }

    func playVideo(at url: URL) {
        let item = AVPlayerItem(url: url)
        videoSize = nil
        observeVideoItem(item)
        videoPlayer.replaceCurrentItem(with: item)
        subtitleController.loadForAVPlayer(videoURL: url, item: item)
        startSubtitleTimer()
        videoPlayer.play()
    }

    /// Plays `asset` in place of the current video's item from the same position, such as to add a subtitle track.
    func replaceVideoAsset(with asset: AVAsset) -> AVPlayerItem? {
        guard isPlayingVideo, !isPlayingExtendedVideo, let currentItem = videoPlayer.currentItem else { return nil }
        let time = currentItem.currentTime()
        let item = AVPlayerItem(asset: asset)
        observeVideoItem(item)
        videoPlayer.replaceCurrentItem(with: item)
        if time.isNumeric, time.seconds > 0 {
            videoPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        return item
    }

    private func observeVideoItem(_ item: AVPlayerItem) {
        videoItemObservations = [
            item.observe(\.status) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self, item === self.videoPlayer.currentItem else { return }
                    if item.status == .failed {
                        debugPrint("AVPlayer failed to load item: \(item.error?.localizedDescription ?? "unknown error")")
                        self.handlePlaybackFailure()
                    } else {
                        self.notifyChange()
                    }
                }
            },
            item.observe(\.presentationSize) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self, item === self.videoPlayer.currentItem else { return }
                    let size = item.presentationSize
                    guard size.width > 0, size.height > 0, size != self.videoSize else { return }
                    self.videoSize = size
                    self.notifyChange()
                }
            }
        ]
    }

    func stopVideo() {
        videoPlayer.pause()
        videoPlayer.replaceCurrentItem(with: nil)
        videoItemObservations = []
        videoSize = nil
    }

    func startSubtitleTimer() {
        stopSubtitleTimer()
        subtitleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlayingVideo, let time = self.playbackTime else { return }
                self.subtitleController.update(currentTime: time.currentTime)
            }
        }
    }

    func stopSubtitleTimer() {
        subtitleTimer?.invalidate()
        subtitleTimer = nil
    }

    /// Refreshes subtitles or reloads the playing video after edits in the subtitle & lyrics editor.
    func subtitlesDidChange(forPath path: String, videoFileChangedOnDisk: Bool) {
        guard let currentFile,
              FilesystemManager.normalizedPath(currentFile.path) == FilesystemManager.normalizedPath(path) else {
            return
        }
        if videoFileChangedOnDisk, let currentIndex {
            let resumeTime = playbackTime?.currentTime
            let wasPlaying = isPlaying
            play(at: currentIndex)
            if let resumeTime, resumeTime > 0 {
                seek(to: resumeTime)
            }
            if !wasPlaying {
                pause()
            }
        } else {
            subtitleController.reloadAfterEdit()
        }
    }
}
