import Foundation

/// A trim copied from one file, to apply to others of different lengths.
struct CopiedTrim: Codable, Equatable {

    /// Seconds cut from the start.
    var startCut: TimeInterval
    /// Seconds cut from the end.
    var endCut: TimeInterval
    /// Seconds kept, from the end of the start cut.
    var keptLength: TimeInterval

    /// How the end of a pasted trim is placed in files of a different length.
    enum Anchor {
        /// Cut the same amount from the end, e.g. to remove the same outro from every file.
        case endOfFile
        /// Keep the same length after the start cut, e.g. to keep the first 30 seconds of every file.
        case keptLength
    }

    init(range: ClosedRange<TimeInterval>, duration: TimeInterval) {
        startCut = range.lowerBound
        endCut = max(0, duration - range.upperBound)
        keptLength = range.upperBound - range.lowerBound
    }

    /// The range this trim selects in a file of `duration` seconds, or nil if the file is too short for it.
    func range(forDuration duration: TimeInterval, anchor: Anchor) -> ClosedRange<TimeInterval>? {
        let end = switch anchor {
        case .endOfFile: duration - endCut
        case .keptLength: startCut + keptLength
        }
        guard startCut >= 0, end <= duration + 0.001,
              end - startCut >= MediaTrimmer.minimumLength else { return nil }
        return startCut...min(end, duration)
    }

    // MARK: Clipboard

    private static let storageKey = "CopiedTrim"

    /// The trim most recently copied, kept across launches.
    static var clipboard: CopiedTrim? {
        get {
            UserDefaults.standard.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(CopiedTrim.self, from: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: storageKey)
        }
    }
}
