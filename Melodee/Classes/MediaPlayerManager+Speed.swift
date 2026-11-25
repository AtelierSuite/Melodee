@preconcurrency import AVFAudio
import SFBAudioEngine

extension MediaPlayerManager {

    /// Places the time pitch unit and the equalizer between the audio player's source and its mixer.
    func insertTimePitch() {
        let timePitch = self.timePitch
        let equalizer = self.equalizer
        let sourceNode = audioPlayer.sourceNode
        audioPlayer.modifyProcessingGraph { engine in
            let format = sourceNode.outputFormat(forBus: 0)
            engine.attach(timePitch)
            engine.attach(equalizer)
            engine.disconnectNodeOutput(sourceNode)
            engine.connect(sourceNode, to: timePitch, format: format)
            engine.connect(timePitch, to: equalizer, format: format)
            engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        }
    }

    /// Plays every engine at the chosen speed.
    func applyPlaybackSpeed() {
        let rate = Float(playbackSpeed)
        timePitch.rate = rate
        // Leave audio untouched at normal speed
        timePitch.bypass = playbackSpeed == PlaybackSpeed.normal
        videoPlayer.defaultRate = rate
        if !isScrubbing {
            if videoPlayer.rate != 0 {
                videoPlayer.rate = rate
            }
            extendedVideoPlayer.defaultRate = rate
        }
        setNowPlaying()
    }

    // MARK: - AudioPlayerDelegate

    /// Carries the time pitch, equalizer and level volume units over to the new format when the audio player changes
    /// formats between files.
    func audioPlayer(_ audioPlayer: AudioPlayer,
                     reconfigureProcessingGraph engine: AVAudioEngine,
                     with format: AVAudioFormat) -> AVAudioNode {
        engine.disconnectNodeOutput(timePitch)
        engine.connect(timePitch, to: equalizer, format: format)
        _ = levelVolume.reconnect(in: engine, after: equalizer, with: format)
        return timePitch
    }
}
