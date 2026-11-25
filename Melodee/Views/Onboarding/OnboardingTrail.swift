import SwiftUI

struct OnboardingTrail: View {
    let current: OnboardingFeature

    private static let features = OnboardingFeature.allCases
    private static let height: CGFloat = 64.0
    private static let inset: CGFloat = 30.0

    var body: some View {
        GeometryReader { proxy in
            let points = Self.points(in: proxy.size)
            ZStack(alignment: .topLeading) {
                TrailLine(points: points)
                    .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 7]))
                TrailLine(points: points)
                    .trim(from: 0.0, to: drawnFraction)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .shadow(color: .white.opacity(0.6), radius: 4.0)
                ForEach(Array(Self.features.enumerated()), id: \.element) { index, feature in
                    OnboardingBadge(feature: feature, state: state(at: index))
                        .position(points[index])
                }
            }
        }
        .frame(height: Self.height)
        .animation(.easeInOut(duration: 0.8), value: current)
        .accessibilityHidden(true)
    }

    private var currentIndex: Int {
        Self.features.firstIndex(of: current) ?? 0
    }

    private var drawnFraction: Double {
        Double(currentIndex) / Double(Self.features.count - 1)
    }

    private func state(at index: Int) -> OnboardingBadge.State {
        if index < currentIndex { return .completed }
        return index == currentIndex ? .current : .upcoming
    }

    private static func points(in size: CGSize) -> [CGPoint] {
        let stride = (size.width - inset * 2.0) / CGFloat(features.count - 1)
        return features.indices.map { index in
            CGPoint(x: inset + stride * CGFloat(index), y: size.height / 2.0)
        }
    }
}

private struct OnboardingBadge: View {
    enum State {
        case upcoming
        case current
        case completed
    }

    let feature: OnboardingFeature
    let state: State

    var body: some View {
        Image(systemName: feature.symbol)
            .font(.system(size: 16.0, weight: .semibold))
            .foregroundStyle(symbolStyle)
            .frame(width: 38.0, height: 38.0)
            .glassEffect(glass, in: .circle)
            .frame(width: 60.0, height: 60.0)
            .animation(.spring(duration: 0.55, bounce: 0.45), value: state)
    }

    private var symbolStyle: Color {
        switch state {
        case .upcoming: .white.opacity(0.8)
        case .current: feature.tint
        case .completed: .white
        }
    }

    private var glass: Glass {
        switch state {
        case .upcoming: .regular
        case .current: .regular.tint(.white)
        case .completed: .regular.tint(feature.tint.opacity(0.6))
        }
    }
}

private struct TrailLine: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}
