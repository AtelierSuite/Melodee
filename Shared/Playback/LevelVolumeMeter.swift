import SwiftUI

/// Shows how loud the playing track is, the level it's brought to, and the gain being applied as it eases in.
struct LevelVolumeMeter: View {

    var levelVolume: LevelVolume

    private var measurement: LevelVolume.Measurement? {
        if case .measured(let measurement) = levelVolume.status { return measurement }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4.0) {
            HStack(alignment: .firstTextBaseline, spacing: 4.0) {
                Text(Self.signed(levelVolume.appliedGain))
                    .font(.system(size: 52.0, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(levelVolume.appliedGain)))
                Text(verbatim: "dB")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .animation(.linear(duration: 0.05), value: levelVolume.appliedGain)
            if let caption {
                HStack(spacing: 6.0) {
                    if levelVolume.status == .measuring {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            LoudnessScale(trackLoudness: measurement?.loudness,
                          appliedGain: levelVolume.appliedGain,
                          isOn: levelVolume.isOn)
                .frame(height: 84.0)
                .padding(.top, 6.0)
        }
        .padding(18.0)
        .background(LinearGradient(colors: [Color(white: 0.14), Color(white: 0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 24.0, style: .continuous))
        .environment(\.colorScheme, .dark)
        .animation(.smooth, value: levelVolume.status)
    }

    /// Explains a meter that has nothing to show. A track being adjusted needs no words.
    private var caption: String? {
        switch levelVolume.status {
        case .idle:
            String(localized: "LevelVolume.Idle")
        case .video:
            String(localized: "LevelVolume.Video")
        case .notMeasured:
            levelVolume.isOn ? String(localized: "LevelVolume.CouldNotMeasure") : nil
        case .measuring:
            String(localized: "LevelVolume.Measuring")
        case .silent:
            String(localized: "LevelVolume.Silent")
        case .measured:
            nil
        }
    }

    static func signed(_ value: Float) -> String {
        let rounded = (Double(value) * 10.0).rounded() / 10.0
        return rounded.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
    }
}

/// A loudness scale from quiet to loud with the target, where the track was measured, and where it plays now.
struct LoudnessScale: View {

    var trackLoudness: Float?
    var appliedGain: Float
    var isOn: Bool

    private static let range: ClosedRange<Float> = -32.0...(-4.0)

    var body: some View {
        Canvas { context, size in
            let barY = size.height * 0.56
            let barRect = CGRect(x: 0.0, y: barY - 4.0, width: size.width, height: 8.0)
            let xFor: (Float) -> CGFloat = { value in
                let clamped = min(max(value, Self.range.lowerBound), Self.range.upperBound)
                let fraction = (clamped - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound)
                return CGFloat(fraction) * size.width
            }

            // Quiet to loud
            let gradient = Gradient(colors: [.blue, .cyan, .green, .yellow, .orange, .red])
            context.fill(Path(roundedRect: barRect, cornerRadius: 4.0),
                         with: .linearGradient(gradient, startPoint: CGPoint(x: 0.0, y: barY),
                                               endPoint: CGPoint(x: size.width, y: barY)))
            context.fill(Path(roundedRect: barRect, cornerRadius: 4.0), with: .color(.black.opacity(0.45)))

            var ticks = Path()
            for value in stride(from: Self.range.lowerBound, through: Self.range.upperBound, by: 2.0) {
                let xPosition = xFor(value)
                ticks.move(to: CGPoint(x: xPosition, y: barY + 8.0))
                ticks.addLine(to: CGPoint(x: xPosition, y: barY + 11.0))
            }
            context.stroke(ticks, with: .color(.white.opacity(0.25)), lineWidth: 1.0)
            context.draw(Text("LevelVolume.Quiet")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45)),
                         at: CGPoint(x: 0.0, y: barY + 24.0), anchor: .leading)
            context.draw(Text("LevelVolume.Loud")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45)),
                         at: CGPoint(x: size.width, y: barY + 24.0), anchor: .trailing)

            // Target
            let targetX = xFor(LevelVolume.targetLoudness)
            var target = Path()
            target.move(to: CGPoint(x: targetX, y: barY - 22.0))
            target.addLine(to: CGPoint(x: targetX, y: barY + 8.0))
            context.stroke(target, with: .color(.white.opacity(isOn ? 0.8 : 0.35)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3.0, 3.0]))
            context.draw(Text("LevelVolume.Target")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(isOn ? 0.8 : 0.4)),
                         at: CGPoint(x: targetX, y: barY - 30.0))

            guard let trackLoudness else { return }
            let originalX = xFor(trackLoudness)
            let nowX = xFor(trackLoudness + appliedGain)
            let tint: Color = appliedGain < 0 ? .orange : .cyan

            // The adjustment, from where the track was measured to where it plays now
            if abs(nowX - originalX) > 1.0 {
                let span = CGRect(x: min(originalX, nowX), y: barY - 4.0, width: abs(nowX - originalX), height: 8.0)
                context.fill(Path(roundedRect: span, cornerRadius: 4.0), with: .color(tint.opacity(0.7)))
            }

            let ring = CGRect(x: originalX - 7.0, y: barY - 7.0, width: 14.0, height: 14.0)
            context.fill(Path(ellipseIn: ring), with: .color(Color(white: 0.1)))
            context.stroke(Path(ellipseIn: ring), with: .color(.white.opacity(0.7)), lineWidth: 2.0)

            var glow = context
            glow.addFilter(.shadow(color: tint.opacity(0.9), radius: 6.0))
            let dot = CGRect(x: nowX - 8.0, y: barY - 8.0, width: 16.0, height: 16.0)
            glow.fill(Path(ellipseIn: dot), with: .color(.white))

            // Keep the original's label clear of the target's
            if abs(originalX - targetX) > 28.0 {
                context.draw(Text("LevelVolume.Original")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6)),
                             at: CGPoint(x: min(max(originalX, 24.0), size.width - 24.0), y: barY - 30.0))
            }
        }
        .accessibilityHidden(true)
    }
}
