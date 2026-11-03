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
    }

    func playVideo(at url: URL) {
        let item = AVPlayerItem(url: url)
        videoSize = nil
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
        videoPlayer.replaceCurrentItem(with: item)
        videoPlayer.play()
    }

    func stopVideo() {
        videoPlayer.pause()
        videoPlayer.replaceCurrentItem(with: nil)
        videoItemObservations = []
        videoSize = nil
    }
}
