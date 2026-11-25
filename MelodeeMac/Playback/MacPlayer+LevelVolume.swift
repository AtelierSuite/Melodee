//
//  MacPlayer+LevelVolume.swift
//  Melodee
//

import AVFoundation
import SFBAudioEngine

extension MacPlayer {

    /// Sets the gain for an audio file before it plays, and measures the audio files queued after it ahead of time.
    func prepareLevelVolume(for file: FSFile, at index: Int) {
        let upcoming = queue.dropFirst(index + 1)
            .filter { $0.type != .video }
            .prefix(2)
            .map { URL(filePath: $0.path) }
        levelVolume.trackWillPlay(URL(filePath: file.path), isVideo: file.type == .video, upcoming: Array(upcoming))
    }

    /// Carries the level volume unit over to the new format when the audio player changes formats between files.
    nonisolated func audioPlayer(_ audioPlayer: AudioPlayer,
                                 reconfigureProcessingGraph engine: AVAudioEngine,
                                 with format: AVAudioFormat) -> AVAudioNode {
        levelVolume.reconnect(in: engine, with: format)
    }
}
