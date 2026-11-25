import SwiftUI

struct OnboardingBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @Environment(\.colorScheme) private var colorScheme
    let feature: OnboardingFeature

    var body: some View {
        ZStack {
            OnboardingMesh(colors: colors, drifts: !reducesMotion)
                .id(feature)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.9), value: feature)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        let depth = colorScheme == .dark ? 0.28 : 0.0
        let base = feature.tint.mix(with: .black, by: depth)
        let partner = feature.partner.mix(with: .black, by: depth)
        let highlight = base.mix(with: .white, by: colorScheme == .dark ? 0.08 : 0.18)
        let shade = partner.mix(with: .black, by: 0.18)
        return [
            highlight, base, partner,
            base, highlight, base,
            partner, base, shade
        ]
    }
}

private struct OnboardingMesh: View {
    let colors: [Color]
    let drifts: Bool

    var body: some View {
        TimelineView(.animation(paused: !drifts)) { timeline in
            MeshGradient(
                width: 3,
                height: 3,
                points: points(at: drifts ? timeline.date.timeIntervalSinceReferenceDate : 0),
                colors: colors,
                smoothsColors: true
            )
        }
    }

    private func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let slowTime = Float(time.truncatingRemainder(dividingBy: 10_000)) * 0.35
        func wave(_ phase: Float, _ amplitude: Float) -> Float {
            sin(slowTime + phase) * amplitude
        }
        return [
            [0, 0], [0.5 + wave(0.4, 0.12), 0], [1, 0],
            [0, 0.5 + wave(1.3, 0.1)],
            [0.5 + wave(2.1, 0.16), 0.5 + wave(0.7, 0.14)],
            [1, 0.5 + wave(2.9, 0.1)],
            [0, 1], [0.5 + wave(3.6, 0.12), 1], [1, 1]
        ]
    }
}
