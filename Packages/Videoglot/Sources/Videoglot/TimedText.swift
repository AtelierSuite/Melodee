import Foundation

/// A timed-text file format Melodee reads or writes beside a video.
public enum TimedTextFormat: String, CaseIterable, Sendable, Hashable, Identifiable, Codable {
    case srt
    case vtt
    case lrc
    case ass
    case ssa

    public var id: String { rawValue }

    public var fileExtension: String { rawValue }

    public var displayName: String { rawValue.uppercased() }

    /// Whether this format represents synced lyrics rather than subtitles.
    public var isLyrics: Bool { self == .lrc }

    /// Formats the editor can write as sidecar files.
    public var isWritableSidecar: Bool {
        switch self {
        case .srt, .vtt, .lrc: true
        case .ass, .ssa: false
        }
    }

    /// Writable sidecar formats in presentation order.
    public static let writableSidecarFormats: [TimedTextFormat] = [.srt, .vtt, .lrc]

    /// All sidecar file extensions recognized beside a video.
    public static let sidecarExtensions: Set<String> = Set(allCases.map(\.fileExtension))

    public init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }
}

/// A single timed subtitle or lyric line.
public struct TimedTextCue: Identifiable, Hashable, Sendable, Codable {

    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String

    public init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = id
        self.startTime = max(0, startTime)
        self.endTime = max(self.startTime, endTime)
        self.text = text
    }

    public var duration: TimeInterval {
        max(0, endTime - startTime)
    }

    /// Whether this cue should be displayed at `time`.
    public func isActive(at time: TimeInterval) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if endTime > startTime {
            return time >= startTime && time < endTime
        }
        return false
    }

    /// Returns a copy whose bounds are clamped to non-negative, non-inverted times.
    public func normalized() -> TimedTextCue {
        let clampedStart = max(0, startTime)
        let clampedEnd = max(clampedStart, endTime)
        return TimedTextCue(id: id, startTime: clampedStart, endTime: clampedEnd, text: text)
    }
}

/// An in-memory subtitle or synced-lyrics track that can be displayed during playback or edited and saved.
public struct TimedTextDocument: Hashable, Sendable, Codable {

    public var cues: [TimedTextCue]
    public var title: String?
    /// BCP-47 or ISO 639 language code (e.g. `"en"`, `"ja"`, `"zh-Hans"`).
    public var languageCode: String?
    public var artist: String?
    public var isLyrics: Bool
    /// Plain unsynced text when opened from unsynced lyrics metadata without timestamps.
    public var unsyncedText: String?

    public init(
        cues: [TimedTextCue] = [],
        title: String? = nil,
        languageCode: String? = nil,
        artist: String? = nil,
        isLyrics: Bool = false,
        unsyncedText: String? = nil
    ) {
        self.cues = cues
        self.title = title
        self.languageCode = languageCode
        self.artist = artist
        self.isLyrics = isLyrics
        self.unsyncedText = unsyncedText
    }

    /// Whether this document has any timed cues.
    public var hasTimedCues: Bool {
        !cues.isEmpty
    }

    /// Cues active at `time`, in chronological order.
    public func activeCues(at time: TimeInterval) -> [TimedTextCue] {
        guard !cues.isEmpty else { return [] }
        return cues.filter { $0.isActive(at: time) }
    }

    /// The combined display text active at `time`, or `nil` when no cue is active.
    public func activeText(at time: TimeInterval) -> String? {
        let active = activeCues(at: time)
        guard !active.isEmpty else { return nil }
        return active.map(\.text).joined(separator: "\n")
    }

    /// The cue whose time range contains `time`, or the last cue that started at or before `time`.
    public func currentCue(at time: TimeInterval) -> TimedTextCue? {
        if let active = activeCues(at: time).last {
            return active
        }
        return cues.last { $0.startTime <= time }
    }

    // MARK: - Editing operations

    /// Sorts cues chronologically by start time, then end time.
    public mutating func sortCues() {
        cues.sort { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            return lhs.endTime < rhs.endTime
        }
    }

    /// Adds a new cue and keeps the cue list sorted.
    @discardableResult
    public mutating func addCue(
        at startTime: TimeInterval,
        duration: TimeInterval = 3.0,
        text: String = ""
    ) -> TimedTextCue {
        let clampedStart = max(0, startTime)
        let cue = TimedTextCue(startTime: clampedStart, endTime: clampedStart + max(0.1, duration), text: text)
        cues.append(cue)
        sortCues()
        return cue
    }

    /// Deletes all cues whose IDs are in `ids`.
    public mutating func deleteCues(ids: Set<UUID>) {
        cues.removeAll { ids.contains($0.id) }
    }

    /// Splits a cue into two at `splitTime` (if strictly inside the cue) or at its midpoint.
    /// Returns the ID of the newly inserted second cue, or `nil` if the cue wasn't found or is too short to split.
    @discardableResult
    public mutating func splitCue(id: UUID, at splitTime: TimeInterval? = nil) -> UUID? {
        guard let index = cues.firstIndex(where: { $0.id == id }) else { return nil }
        let original = cues[index]
        guard original.duration >= 0.1 else { return nil }

        let targetSplit: TimeInterval
        if let splitTime, splitTime > original.startTime + 0.05, splitTime < original.endTime - 0.05 {
            targetSplit = splitTime
        } else {
            targetSplit = original.startTime + original.duration / 2.0
        }

        let (firstText, secondText) = Self.splitText(original.text)
        cues[index].endTime = targetSplit
        cues[index].text = firstText
        let secondCue = TimedTextCue(startTime: targetSplit, endTime: original.endTime, text: secondText)
        cues.insert(secondCue, at: index + 1)
        return secondCue.id
    }

    /// Merges the cue with `id` and the cue immediately following it.
    /// Returns `true` if a merge occurred.
    @discardableResult
    public mutating func mergeCueWithNext(id: UUID) -> Bool {
        guard let index = cues.firstIndex(where: { $0.id == id }), index + 1 < cues.count else {
            return false
        }
        let first = cues[index]
        let second = cues[index + 1]
        let combinedText = [first.text, second.text]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        cues[index] = TimedTextCue(
            id: first.id,
            startTime: min(first.startTime, second.startTime),
            endTime: max(first.endTime, second.endTime),
            text: combinedText
        )
        cues.remove(at: index + 1)
        return true
    }

    /// Shifts every cue's start and end time by `offset` seconds, clamping to `>= 0`.
    public mutating func shiftAll(by offset: TimeInterval) {
        guard offset != 0 else { return }
        for index in cues.indices {
            let newStart = max(0, cues[index].startTime + offset)
            let newEnd = max(newStart, cues[index].endTime + offset)
            cues[index].startTime = newStart
            cues[index].endTime = newEnd
        }
        sortCues()
    }

    /// Nudges a single cue's start and/or end time, clamping to valid bounds.
    public mutating func nudgeCue(id: UUID, startDelta: TimeInterval = 0, endDelta: TimeInterval = 0) {
        guard let index = cues.firstIndex(where: { $0.id == id }) else { return }
        var cue = cues[index]
        if startDelta != 0 {
            cue.startTime = max(0, cue.startTime + startDelta)
            if cue.endTime < cue.startTime + 0.1 {
                cue.endTime = cue.startTime + 0.1
            }
        }
        if endDelta != 0 {
            cue.endTime = max(cue.startTime + 0.1, cue.endTime + endDelta)
        }
        cues[index] = cue
        sortCues()
    }

    /// Returns the plain (unsynced) text of all cues, matching the format of the tag editor's lyrics field.
    public func plainText() -> String {
        if !cues.isEmpty {
            return cues.map(\.text).joined(separator: "\n")
        }
        return unsyncedText ?? ""
    }

    /// Creates a timed-text document from plain (unsynced) lyrics, evenly spacing lines across `totalDuration`
    /// so the user can adjust timings while playing the video.
    public static func fromPlainLyrics(
        _ plainText: String,
        totalDuration: TimeInterval,
        title: String? = nil,
        languageCode: String? = nil
    ) -> TimedTextDocument {
        let lines = plainText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return TimedTextDocument(cues: [], title: title, languageCode: languageCode, isLyrics: true)
        }
        let duration = totalDuration > 0 ? totalDuration : TimeInterval(lines.count) * 3.0
        let step = max(0.5, min(4.0, duration / TimeInterval(lines.count)))
        let cues = lines.enumerated().map { index, line in
            let start = TimeInterval(index) * step
            let end = min(start + step, max(duration, start + 0.5))
            return TimedTextCue(startTime: start, endTime: end, text: line)
        }
        return TimedTextDocument(cues: cues, title: title, languageCode: languageCode, isLyrics: true)
    }

    private static func splitText(_ text: String) -> (String, String) {
        let lines = text.components(separatedBy: "\n")
        if lines.count >= 2 {
            let mid = lines.count / 2
            return (
                lines[..<mid].joined(separator: "\n"),
                lines[mid...].joined(separator: "\n")
            )
        }
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        if words.count >= 2 {
            let mid = words.count / 2
            return (
                words[..<mid].joined(separator: " "),
                words[mid...].joined(separator: " ")
            )
        }
        return (text, "")
    }
}
