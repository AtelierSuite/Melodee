import SwiftUI

struct OnboardingStage: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var stagePhase = StagePhase(feature: nil, step: 0)
    @State private var visualizerStyle: NPVisualizerStyle = .waves
    @State private var history = NPVisualizerHistory()
    let feature: OnboardingFeature

    private static let height: CGFloat = 240.0
    private static let visualizerTour: [NPVisualizerStyle] = [.radial, .mixer]

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: reducesMotion || feature != .music)) { timeline in
                OnboardingScene(
                    layout: OnboardingStageLayout(
                        size: proxy.size,
                        feature: feature,
                        phase: reducesMotion ? 1 : (stagePhase.feature == feature ? stagePhase.step : 0),
                        time: reducesMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
                    ),
                    visualizerStyle: visualizerStyle,
                    history: history
                )
            }
        }
        .frame(height: Self.height)
        .background(shape.fill(.white.opacity(0.12)))
        .overlay(shape.strokeBorder(.white.opacity(0.3), lineWidth: 1.0))
        .clipShape(shape)
        .animation(.spring(duration: 0.8, bounce: 0.2), value: feature)
        .animation(.spring(duration: 0.55, bounce: 0.35), value: stagePhase)
        .task(id: feature) { await play() }
        .accessibilityHidden(true)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 30.0)
    }

    private func play() async {
        guard !reducesMotion else {
            visualizerStyle = .mixer
            return
        }
        guard feature == .music else {
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            stagePhase = StagePhase(feature: feature, step: 1)
            guard feature == .video else { return }
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.8, bounce: 0.2)) {
                stagePhase = StagePhase(feature: feature, step: 2)
            }
            return
        }
        stagePhase = StagePhase(feature: feature, step: 1)
        visualizerStyle = .waves
        for style in Self.visualizerTour {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.6)) { visualizerStyle = style }
        }
    }
}

private struct StagePhase: Equatable {
    var feature: OnboardingFeature?
    var step: Int
}

private struct OnboardingScene: View {
    @Namespace private var glassNamespace
    let layout: OnboardingStageLayout
    let visualizerStyle: NPVisualizerStyle
    let history: NPVisualizerHistory

    var body: some View {
        GlassEffectContainer(spacing: 12.0) {
            ZStack(alignment: .topLeading) {
                visualizer
                ForEach(0..<OnboardingStageLayout.homeIconColumns * OnboardingStageLayout.homeIconRows, id: \.self) { index in
                    let icon = layout.homeIcon(index)
                    RoundedRectangle(cornerRadius: 13.0)
                        .fill(.white.opacity(0.22))
                        .placed(in: icon.frame, scale: CGSize(width: icon.scale, height: icon.scale))
                        .opacity(icon.opacity)
                        .animation(.spring(duration: 0.6, bounce: 0.3).delay(Double(index) * 0.03), value: icon.opacity)
                }
                if layout.feature != .music && layout.feature != .trimming {
                    tile
                        .id(layout.feature == .files ? "folder" : "tile")
                }
                if layout.showsRows {
                    ForEach(0..<OnboardingStageLayout.rowCount, id: \.self) { index in
                        row(layout.row(index), index: index)
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(0..<OnboardingStageLayout.barCount, id: \.self) { index in
                    let bar = layout.bar(index)
                    Capsule()
                        .fill(bar.color)
                        .placed(in: bar.frame)
                        .opacity(bar.opacity)
                }
                videoProgress
                subtitle
                trimFrame
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        }
    }

    private var visualizer: some View {
        let frame = layout.visualizerFrame
        return ZStack {
            NPVisualizerCanvas(
                style: visualizerStyle,
                frame: NPVisualizerFrame(
                    bands: layout.visualizerBands,
                    time: layout.time,
                    colors: (bottom: .white.opacity(0.6), top: .white),
                    history: history
                )
            )
            .id(visualizerStyle)
            .transition(.blurReplace)
        }
        .placed(in: frame)
        .opacity(layout.feature == .music ? 1.0 : 0.0)
        .scaleEffect(layout.feature == .music ? 1.0 : 0.6)
    }

    private var tile: some View {
        let tile = layout.tile
        let shape = RoundedRectangle(cornerRadius: tile.cornerRadius)
        return Image(systemName: tile.symbol)
            .font(.system(size: tile.frame.height * 0.38, weight: .semibold))
            .foregroundStyle(tile.symbolColor)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: tile.frame.width, height: tile.frame.height)
            .glassEffect(.regular.tint(tile.tint), in: shape)
            .glassEffectID("tile", in: glassNamespace)
            .placed(in: tile.frame, angle: tile.angle)
            .opacity(tile.opacity)
    }

    private func row(_ row: OnboardingStageLayout.Row, index: Int) -> some View {
        let isExpanded = row.frame.width > 60.0
        return HStack(spacing: 10.0) {
            Image(systemName: row.symbol)
                .font(.system(size: 15.0, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22.0)
            if isExpanded {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: max(proxy.size.width * row.lineWidth, 7.0), height: 7.0)
                        .frame(maxHeight: .infinity)
                        .animation(.easeOut(duration: 0.6).delay(row.delay + 0.3), value: row.lineWidth)
                }
                Image(systemName: row.accessory ?? "checkmark")
                    .font(.system(size: 13.0, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .opacity(row.accessory == nil ? 0.0 : 1.0)
                    .scaleEffect(row.accessory == nil ? 0.4 : 1.0)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, isExpanded ? 14.0 : 0.0)
        .frame(width: row.frame.width, height: row.frame.height)
        .glassEffect(row.accessory == nil ? .regular : .regular.tint(.white.opacity(0.3)), in: .capsule)
        .glassEffectID("row\(index)", in: glassNamespace)
        .placed(in: row.frame)
        .animation(.spring(duration: 0.6, bounce: 0.25).delay(row.delay), value: row.frame)
    }

    private var videoProgress: some View {
        let progress = layout.videoProgress
        return Capsule()
            .fill(.white.opacity(0.35))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white)
                    .frame(width: progress.track.width * progress.played)
            }
            .placed(in: progress.track)
            .opacity(progress.opacity)
    }

    private var subtitle: some View {
        let subtitle = layout.subtitle
        return Capsule()
            .fill(.white)
            .placed(in: subtitle.frame, scale: CGSize(width: subtitle.scale, height: 1.0))
            .opacity(subtitle.opacity)
    }

    private var trimFrame: some View {
        let trim = layout.trimFrame
        return RoundedRectangle(cornerRadius: 10.0)
            .strokeBorder(.yellow, lineWidth: 4.0)
            .overlay(alignment: .leading) { trimHandle(leading: true) }
            .overlay(alignment: .trailing) { trimHandle(leading: false) }
            .placed(in: trim.frame)
            .opacity(trim.opacity)
    }

    private func trimHandle(leading: Bool) -> some View {
        UnevenRoundedRectangle(cornerRadii: leading
            ? .init(topLeading: 10.0, bottomLeading: 10.0)
            : .init(bottomTrailing: 10.0, topTrailing: 10.0))
            .fill(.yellow)
            .frame(width: 14.0)
            .overlay {
                Capsule()
                    .fill(.black.opacity(0.45))
                    .frame(width: 3.0, height: 24.0)
            }
    }
}

private extension View {
    func placed(in frame: CGRect, angle: Double = 0.0, scale: CGSize = CGSize(width: 1.0, height: 1.0)) -> some View {
        self
            .frame(width: max(frame.width, 0.0), height: max(frame.height, 0.0))
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            .position(x: frame.midX, y: frame.midY)
    }
}
