//
//  MacPlayer+Video.swift
//  Melodee
//

import AVFoundation

extension MacPlayer {

    /// Keeps the play state in sync when the video is controlled from its own window,
    /// and moves on once a video finishes.
    func setUpVideoPlayer() {
        videoTimeControlObservation = videoPlayer.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isPlayingVideo else { return }
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
