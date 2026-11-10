import Foundation

/// What the previous and next buttons do.
enum SkipButtonMode: String, CaseIterable, Identifiable {
    /// Skip by ``SkipButtonMode/interval`` for podcasts and audiobooks, and change tracks for everything else.
    case automatic
    /// Always change tracks.
    case tracks
    /// Always skip back or forward by ``SkipButtonMode/interval``.
    case fifteenSeconds

    static let storageKey = "SkipButtonMode"

    /// How far the buttons skip back or forward when they don't change tracks.
    static let interval: TimeInterval = 15.0

    var id: String { rawValue }

    static var current: SkipButtonMode {
        get {
            UserDefaults.standard.string(forKey: storageKey).flatMap(SkipButtonMode.init(rawValue:)) ?? .automatic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    /// Whether the buttons skip by ``SkipButtonMode/interval``, given whether the file is spoken word.
    func skipsByInterval(isSpokenWord: Bool) -> Bool {
        switch self {
        case .automatic: return isSpokenWord
        case .tracks: return false
        case .fifteenSeconds: return true
        }
    }
}
