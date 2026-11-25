@preconcurrency import AVFAudio

extension MediaPlayerManager {

    func applyEqualizer(bands: [EQBand], isEnabled: Bool) {
        equalizer.bypass = !isEnabled
        for (parameters, band) in zip(equalizer.bands, bands) {
            parameters.filterType = switch band.kind {
            case .lowCut: .highPass
            case .lowShelf: .lowShelf
            case .bell: .parametric
            case .highShelf: .highShelf
            case .highCut: .lowPass
            }
            parameters.frequency = Float(band.frequency)
            parameters.gain = band.hasGain ? Float(band.gain) : 0.0
            parameters.bandwidth = Float(band.bandwidth)
            parameters.bypass = !band.isEnabled
        }
    }
}
