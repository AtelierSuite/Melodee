//
//  MacPlayer+Skipping.swift
//  Melodee
//

import Foundation

extension MacPlayer {

    /// Whether the previous and next buttons skip back and forward within the current file instead of changing tracks.
    var skipsByInterval: Bool {
        skipButtonMode.skipsByInterval(isSpokenWord: isCurrentFileSpokenWord)
    }

    func skipForward() {
        skip(by: SkipButtonMode.interval)
    }

    func skipBackward() {
        skip(by: -SkipButtonMode.interval)
    }

    private func skip(by offset: TimeInterval) {
        guard supportsSeeking, let time = playbackTime else { return }
        // Stay just short of the end, so the file finishes playing normally
        seek(to: min(max(0, time.currentTime + offset), max(0, time.totalTime - 0.1)))
    }

    /// Works out whether the current file is spoken word, for the automatic skip button mode.
    func detectSpokenWord() {
        spokenWordDetectionTask?.cancel()
        guard let file = currentFile, file.type == .audio else {
            isCurrentFileSpokenWord = false
            return
        }
        let path = file.path
        spokenWordDetectionTask = Task { [weak self] in
            let isSpokenWord = await SpokenWordDetector.isSpokenWord(atPath: path)
            guard let self, !Task.isCancelled, self.currentFile?.path == path,
                  self.isCurrentFileSpokenWord != isSpokenWord else { return }
            self.isCurrentFileSpokenWord = isSpokenWord
            self.notifyChange()
        }
    }
}
