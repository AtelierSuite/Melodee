//
//  MacPlayer+NowPlaying.swift
//  Melodee
//

import AppKit
@preconcurrency import MediaPlayer

extension MacPlayer {

    /// Lets the media keys, Control Center and headphones control playback.
    func setUpRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToNextTrack() }
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.backToPreviousTrack() }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
        commandCenter.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let repeatType = event.repeatType
            Task { @MainActor in self?.repeatMode = RepeatMode(remoteRepeatType: repeatType) }
            return .success
        }
    }

    func updateNowPlaying() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.isEnabled = canGoToNextTrack
        commandCenter.previousTrackCommand.isEnabled = canGoToPreviousTrack
        commandCenter.changePlaybackPositionCommand.isEnabled = supportsSeeking
        commandCenter.changeRepeatModeCommand.currentRepeatType = repeatMode.remoteRepeatType
        let infoCenter = MPNowPlayingInfoCenter.default()
        guard let metadata else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentIndex ?? 0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count
        ]
        info[MPMediaItemPropertyArtist] = metadata.artist
        info[MPMediaItemPropertyAlbumTitle] = metadata.album
        if let time = playbackTime {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time.currentTime
            info[MPMediaItemPropertyPlaybackDuration] = time.totalTime
        }
        if let artwork = metadata.artwork {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(from: artwork)
        }
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
    }

    /// Built outside the main actor, because Now Playing asks for the image on its own queue.
    nonisolated private static func makeArtwork(from image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
