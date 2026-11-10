@preconcurrency import AVFAudio
import SFBAudioEngine

extension MediaPlayerManager {

    /// Places the time pitch unit between the audio player's source and its mixer, so audio can play faster or
    /// slower without changing its pitch.
    func insertTimePitch() {
        let timePitch = self.timePitch
        let sourceNode = audioPlayer.sourceNode
        audioPlayer.modifyProcessingGraph { engine in
            let format = sourceNode.outputFormat(forBus: 0)
            engine.attach(timePitch)
            engine.disconnectNodeOutput(sourceNode)
            engine.connect(sourceNode, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
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

    /// Carries the time pitch unit over to the new format when the audio player changes formats between files.
    func audioPlayer(_ audioPlayer: AudioPlayer,
                     reconfigureProcessingGraph engine: AVAudioEngine,
                     with format: AVAudioFormat) -> AVAudioNode {
        engine.disconnectNodeOutput(timePitch)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        return timePitch
    }
}
