import Foundation

/// Calculates how much each band changes the loudness of a frequency, using the biquad filters
/// from the Audio EQ Cookbook that `AVAudioUnitEQ` is modelled on.
enum EQResponse {

    static let sampleRate: Double = 48_000.0

    private struct Coefficients {
        var num0, num1, num2, den0, den1, den2: Double
    }

    /// The band's change in loudness at `frequency`, in decibels.
    static func decibels(of band: EQBand, at frequency: Double) -> Double {
        guard band.isEnabled, let coefficients = coefficients(for: band) else { return 0.0 }
        let omega = 2.0 * .pi * frequency / sampleRate
        let cos1 = cos(omega), sin1 = sin(omega)
        let cos2 = cos(2.0 * omega), sin2 = sin(2.0 * omega)
        let numeratorReal = coefficients.num0 + coefficients.num1 * cos1 + coefficients.num2 * cos2
        let numeratorImaginary = -(coefficients.num1 * sin1 + coefficients.num2 * sin2)
        let denominatorReal = coefficients.den0 + coefficients.den1 * cos1 + coefficients.den2 * cos2
        let denominatorImaginary = -(coefficients.den1 * sin1 + coefficients.den2 * sin2)
        let numerator = numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary
        let denominator = denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary
        guard denominator > 0, numerator > 0 else { return -120.0 }
        return 10.0 * log10(numerator / denominator)
    }

    /// Every band's change in loudness at `frequency` added together, in decibels.
    static func decibels(of bands: [EQBand], at frequency: Double) -> Double {
        bands.reduce(0.0) { $0 + decibels(of: $1, at: frequency) }
    }

    private static func coefficients(for band: EQBand) -> Coefficients? {
        let frequency = min(band.frequency, sampleRate / 2.0 * 0.99)
        let omega = 2.0 * .pi * frequency / sampleRate
        let cosOmega = cos(omega), sinOmega = sin(omega)
        let amplitude = pow(10.0, band.gain / 40.0)
        switch band.kind {
        case .bell:
            let alpha = sinOmega * sinh(log(2.0) / 2.0 * band.bandwidth * omega / sinOmega)
            return Coefficients(num0: 1.0 + alpha * amplitude, num1: -2.0 * cosOmega,
                                num2: 1.0 - alpha * amplitude, den0: 1.0 + alpha / amplitude,
                                den1: -2.0 * cosOmega, den2: 1.0 - alpha / amplitude)
        case .lowShelf, .highShelf:
            let alpha = sinOmega / 2.0 * sqrt(2.0)
            let root = 2.0 * sqrt(amplitude) * alpha
            let plus = amplitude + 1.0, minus = amplitude - 1.0
            if band.kind == .lowShelf {
                return Coefficients(num0: amplitude * (plus - minus * cosOmega + root),
                                    num1: 2.0 * amplitude * (minus - plus * cosOmega),
                                    num2: amplitude * (plus - minus * cosOmega - root),
                                    den0: plus + minus * cosOmega + root,
                                    den1: -2.0 * (minus + plus * cosOmega),
                                    den2: plus + minus * cosOmega - root)
            }
            return Coefficients(num0: amplitude * (plus + minus * cosOmega + root),
                                num1: -2.0 * amplitude * (minus + plus * cosOmega),
                                num2: amplitude * (plus + minus * cosOmega - root),
                                den0: plus - minus * cosOmega + root,
                                den1: 2.0 * (minus - plus * cosOmega),
                                den2: plus - minus * cosOmega - root)
        case .lowCut, .highCut:
            let alpha = sinOmega / (2.0 * 0.707)
            if band.kind == .lowCut {
                return Coefficients(num0: (1.0 + cosOmega) / 2.0, num1: -(1.0 + cosOmega),
                                    num2: (1.0 + cosOmega) / 2.0, den0: 1.0 + alpha,
                                    den1: -2.0 * cosOmega, den2: 1.0 - alpha)
            }
            return Coefficients(num0: (1.0 - cosOmega) / 2.0, num1: 1.0 - cosOmega,
                                num2: (1.0 - cosOmega) / 2.0, den0: 1.0 + alpha,
                                den1: -2.0 * cosOmega, den2: 1.0 - alpha)
        }
    }
}
