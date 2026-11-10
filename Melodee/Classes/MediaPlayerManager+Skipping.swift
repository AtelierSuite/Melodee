import Foundation

extension MediaPlayerManager {

    /// Whether the previous and next buttons skip back and forward within the current file instead of changing tracks.
    func skipsByInterval() -> Bool {
        return skipButtonMode.skipsByInterval(isSpokenWord: isCurrentFileSpokenWord)
    }

    func skipForward() {
        skip(by: SkipButtonMode.interval)
    }

    func skipBackward() {
        skip(by: -SkipButtonMode.interval)
    }

    private func skip(by offset: TimeInterval) {
        guard isPlaybackActive, !isScrubbing, supportsSeeking(), let time = playbackTime() else { return }
        // Stay just short of the end, so the file finishes playing normally
        let target = min(max(0, time.currentTime + offset), max(0, time.totalTime - 0.1))
        seekTo(target)
    }

    /// Works out whether the current file is spoken word, for the automatic skip button mode.
    func detectSpokenWord() {
        spokenWordDetectionTask?.cancel()
        guard let file = currentlyPlayingFile(), file.type == .audio else {
            isCurrentFileSpokenWord = false
            return
        }
        // Files still in iCloud are checked again once downloaded, when the metadata cache is invalidated.
        // Until then the previous answer is kept, so the buttons don't flicker between episodes.
        guard FileManager.default.fileExists(atPath: file.path), !file.isEvicted() else { return }
        let queueID = currentlyPlayingID
        let path = file.path
        nonisolated(unsafe) let managerRef = self
        spokenWordDetectionTask = Task { @MainActor in
            let isSpokenWord = await SpokenWordDetector.isSpokenWord(atPath: path)
            guard !Task.isCancelled, managerRef.currentlyPlayingID == queueID,
                  managerRef.isCurrentFileSpokenWord != isSpokenWord else { return }
            managerRef.isCurrentFileSpokenWord = isSpokenWord
            managerRef.setNowPlaying()
        }
    }
}
