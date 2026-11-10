import Foundation

extension MediaPlayerManager {

    /// Whether there are at least two tracks after the current one to shuffle.
    func canShuffleUpcomingTracks() -> Bool {
        guard isPlaybackActive else { return false }
        return queue.count - (currentlyPlayingIndex() + 1) >= 2
    }

    /// Shuffles the tracks after the current one, leaving the current track and those before it in place.
    func shuffleUpcomingTracks() {
        guard canShuffleUpcomingTracks() else { return }
        let upcomingStart = currentlyPlayingIndex() + 1
        var upcoming = Array(queue[upcomingStart...])
        let original = upcoming.map(\.playbackQueueID)
        // Make sure the order actually changes, so the button never seems to do nothing
        repeat {
            upcoming.shuffle()
        } while upcoming.map(\.playbackQueueID) == original
        queue.replaceSubrange(upcomingStart..., with: upcoming)
        setNowPlaying()
    }
}
