import Foundation
import SwiftUI

/// One band of the equalizer, matching a band of `AVAudioUnitEQ`.
struct EQBand: Codable, Hashable, Identifiable, Sendable {

    enum Kind: String, Codable, Sendable {
        case lowCut
        case lowShelf
        case bell
        case highShelf
        case highCut

        var localizedName: String {
            switch self {
            case .lowCut: String(localized: "Equalizer.Band.LowCut")
            case .lowShelf: String(localized: "Equalizer.Band.LowShelf")
            case .bell: String(localized: "Equalizer.Band.Bell")
            case .highShelf: String(localized: "Equalizer.Band.HighShelf")
            case .highCut: String(localized: "Equalizer.Band.HighCut")
            }
        }
    }

    static let minimumFrequency: Double = 20.0
    static let maximumFrequency: Double = 20_000.0
    static let gainRange: ClosedRange<Double> = -18.0...18.0
    static let bandwidthRange: ClosedRange<Double> = 0.1...4.0

    var id: Int
    var kind: Kind
    var frequency: Double
    var gain: Double = 0.0
    /// The width of a bell in octaves.
    var bandwidth: Double = 1.0
    var isEnabled: Bool = true

    /// Whether dragging the band's handle up and down changes its gain.
    var hasGain: Bool {
        kind == .bell || kind == .lowShelf || kind == .highShelf
    }

    var color: Color {
        EQBand.colors[id % EQBand.colors.count]
    }

    static let colors: [Color] = [
        Color(red: 1.00, green: 0.23, blue: 0.27),
        Color(red: 1.00, green: 0.55, blue: 0.10),
        Color(red: 1.00, green: 0.85, blue: 0.10),
        Color(red: 0.30, green: 0.90, blue: 0.35),
        Color(red: 0.10, green: 0.85, blue: 0.85),
        Color(red: 0.20, green: 0.55, blue: 1.00),
        Color(red: 0.60, green: 0.40, blue: 1.00),
        Color(red: 0.95, green: 0.35, blue: 0.85)
    ]

    static let defaults: [EQBand] = [
        EQBand(id: 0, kind: .lowCut, frequency: 30.0, isEnabled: false),
        EQBand(id: 1, kind: .lowShelf, frequency: 80.0),
        EQBand(id: 2, kind: .bell, frequency: 200.0),
        EQBand(id: 3, kind: .bell, frequency: 600.0),
        EQBand(id: 4, kind: .bell, frequency: 2_000.0),
        EQBand(id: 5, kind: .bell, frequency: 5_000.0),
        EQBand(id: 6, kind: .highShelf, frequency: 10_000.0),
        EQBand(id: 7, kind: .highCut, frequency: 18_000.0, isEnabled: false)
    ]
}
