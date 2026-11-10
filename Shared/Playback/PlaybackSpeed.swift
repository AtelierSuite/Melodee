import Foundation

/// How fast audio and video play, where 1 is normal speed.
enum PlaybackSpeed {

    static let storageKey = "PlaybackSpeed"
    static let normal: Double = 1.0
    static let options: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    static var current: Double {
        get {
            let speed = UserDefaults.standard.double(forKey: storageKey)
            return options.contains(speed) ? speed : normal
        }
        set {
            UserDefaults.standard.set(newValue, forKey: storageKey)
        }
    }

    /// The speed as people write it, such as 1.25×.
    static func label(for speed: Double) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}
