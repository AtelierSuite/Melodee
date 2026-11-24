import Foundation

/// Ready-made band settings to start tuning from.
enum EQPreset: String, CaseIterable, Identifiable {
    case flat
    case bassBoost
    case vocal
    case trebleBoost
    case loudness

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .flat: String(localized: "Equalizer.Preset.Flat")
        case .bassBoost: String(localized: "Equalizer.Preset.BassBoost")
        case .vocal: String(localized: "Equalizer.Preset.Vocal")
        case .trebleBoost: String(localized: "Equalizer.Preset.TrebleBoost")
        case .loudness: String(localized: "Equalizer.Preset.Loudness")
        }
    }

    var bands: [EQBand] {
        var bands = EQBand.defaults
        // Gains for the low shelf, the four bells and the high shelf, in order
        let gains: [Double] = switch self {
        case .flat: [0, 0, 0, 0, 0, 0]
        case .bassBoost: [6, 3, 0, 0, 0, 0]
        case .vocal: [-2, -1.5, 1.5, 4, 2, 0]
        case .trebleBoost: [0, 0, 0, 1.5, 3.5, 5]
        case .loudness: [5, 1, -1.5, 0, 2, 4]
        }
        for (offset, gain) in gains.enumerated() {
            bands[offset + 1].gain = gain
        }
        if self == .vocal {
            bands[0].isEnabled = true
            bands[0].frequency = 90.0
        }
        return bands
    }
}

extension EQBand {

    private static let storageKey = "Equalizer.Bands"

    /// The bands the user last tuned.
    static var saved: [EQBand] {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey),
                  let bands = try? JSONDecoder().decode([EQBand].self, from: data),
                  bands.count == defaults.count else { return defaults }
            return bands
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: storageKey)
        }
    }
}
