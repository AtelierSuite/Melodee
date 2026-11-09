import SwiftUI

/// The ways the visualizer can draw the spectrum.
///
/// Every style draws the same band levels, lowest frequency first, each from 0 to 1.
enum NPVisualizerStyle: String, CaseIterable, Identifiable {
    case bars
    case mirror
    case curve
    case radial
    case blob
    case waves
    case arcs
    case ridges
    case orbs
    case pulse
    case mixer

    static let storageKey = "NowPlaying.VisualizerStyle"

    typealias Colors = (bottom: Color, top: Color)

    var id: String { rawValue }

    var name: String {
        switch self {
        case .bars: "Bars"
        case .mirror: "Mirror"
        case .curve: "Curve"
        case .radial: "Radial"
        case .blob: "Blob"
        case .waves: "Waves"
        case .arcs: "Arcs"
        case .ridges: "Ridges"
        case .orbs: "Orbs"
        case .pulse: "Pulse"
        case .mixer: "Mixer"
        }
    }

    /// A custom SF Symbol that looks like the style, from the asset catalog.
    var icon: Image {
        Image("Visualizer/\(name)")
    }

    @MainActor
    func draw(_ bands: [Float],
              colors: Colors,
              time: TimeInterval,
              history: NPVisualizerHistory,
              in context: inout GraphicsContext,
              size: CGSize) {
        guard bands.count > 1, size.width > 0, size.height > 0 else { return }
        switch self {
        case .bars: Self.drawBars(bands, colors: colors, in: &context, size: size)
        case .mirror: Self.drawMirror(bands, colors: colors, in: &context, size: size)
        case .curve: Self.drawCurve(bands, colors: colors, in: &context, size: size)
        case .radial: Self.drawRadial(bands, colors: colors, in: &context, size: size)
        case .blob: Self.drawBlob(bands, colors: colors, time: time, in: &context, size: size)
        case .waves: Self.drawWaves(bands, colors: colors, time: time, in: &context, size: size)
        case .arcs: Self.drawArcs(bands, colors: colors, in: &context, size: size)
        case .ridges: Self.drawRidges(history, colors: colors, time: time, in: &context, size: size)
        case .orbs: Self.drawOrbs(bands, colors: colors, time: time, in: &context, size: size)
        case .pulse: Self.drawPulse(bands, history: history, colors: colors, time: time, in: &context, size: size)
        case .mixer: Self.drawMixer(bands, colors: colors, in: &context, size: size)
        }
    }

    // MARK: Bars

    /// Bars standing on the bottom edge, from bass on the left to treble on the right.
    private static func drawBars(_ bands: [Float], colors: Colors, in context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 2.0
        let cornerRadius: CGFloat = 3.0
        let barWidth = (size.width - spacing * CGFloat(bands.count - 1)) / CGFloat(bands.count)
        var bars = Path()
        for (index, level) in bands.enumerated() {
            let height = CGFloat(level) * size.height
            guard height > 0.5 else { continue }
            bars.addRoundedRect(in: CGRect(x: CGFloat(index) * (barWidth + spacing), y: size.height - height,
                                           width: barWidth, height: height),
                                cornerRadii: RectangleCornerRadii(topLeading: cornerRadius, topTrailing: cornerRadius))
        }
        // One gradient over the whole height, so a bar's color shows how loud it is
        context.fill(bars, with: .linearGradient(Gradient(colors: [colors.bottom, colors.top]),
                                                 startPoint: CGPoint(x: 0, y: size.height),
                                                 endPoint: .zero))
    }

    // MARK: Mirror

    /// Bars growing up and down from the middle, from bass on the left to treble on the right.
    private static func drawMirror(_ bands: [Float], colors: Colors, in context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 2.0
        let cornerRadius: CGFloat = 3.0
        let barWidth = (size.width - spacing * CGFloat(bands.count - 1)) / CGFloat(bands.count)
        let midY = size.height / 2
        var bars = Path()
        for (index, level) in bands.enumerated() {
            // Silent bands still show as a thin line along the middle
            let height = max(CGFloat(level) * size.height, 2.0)
            bars.addRoundedRect(in: CGRect(x: CGFloat(index) * (barWidth + spacing), y: midY - height / 2,
                                           width: barWidth, height: height),
                                cornerSize: CGSize(width: min(cornerRadius, height / 2), height: min(cornerRadius, height / 2)))
        }
        // The same gradient as Bars, reflected, so a bar's color shows how loud it is
        context.fill(bars, with: .linearGradient(Gradient(colors: [colors.top, colors.bottom, colors.top]),
                                                 startPoint: .zero,
                                                 endPoint: CGPoint(x: 0, y: size.height)))
    }

    // MARK: Curve

    /// A glowing line through the band levels, with the area under it filled.
    private static func drawCurve(_ bands: [Float], colors: Colors, in context: inout GraphicsContext, size: CGSize) {
        let points = bands.enumerated().map { index, level in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(bands.count - 1),
                    y: size.height - CGFloat(level) * size.height * 0.88)
        }
        let line = smoothPath(through: points, isClosed: false)
        var area = line
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()
        context.fill(area, with: .linearGradient(Gradient(colors: [colors.top.opacity(0.65), colors.bottom.opacity(0.08)]),
                                                 startPoint: .zero,
                                                 endPoint: CGPoint(x: 0, y: size.height)))
        var glow = context
        glow.addFilter(.shadow(color: colors.top, radius: 6))
        glow.stroke(line, with: .color(colors.top),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    // MARK: Radial

    /// Spokes around a disc that swells with the bass, with bass at the top and treble at the bottom.
    private static func drawRadial(_ bands: [Float], colors: Colors, in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let side = min(size.width, size.height)
        let bass = CGFloat(bands.prefix(3).reduce(0, +) / 3)
        let innerRadius = side * (0.2 + 0.05 * bass)
        let maximumLength = side / 2 - innerRadius - 10
        // Each side of the circle shows every band, so the picture is symmetrical
        let order = bands + bands.reversed()
        let spokeWidth = 2 * .pi * innerRadius / CGFloat(order.count) * 0.55
        var spokes = Path()
        for (index, level) in order.enumerated() {
            let angle = (CGFloat(index) + 0.5) / CGFloat(order.count) * 2 * .pi - .pi / 2
            let length = max(CGFloat(level) * maximumLength, spokeWidth)
            let spoke = Path(roundedRect: CGRect(x: innerRadius + 6, y: -spokeWidth / 2,
                                                 width: length, height: spokeWidth),
                             cornerRadius: spokeWidth / 2)
            spokes.addPath(spoke, transform: CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle))
        }
        context.fill(spokes, with: .radialGradient(Gradient(colors: [colors.bottom, colors.top]),
                                                   center: center,
                                                   startRadius: innerRadius,
                                                   endRadius: side / 2))
        let disc = Path(ellipseIn: CGRect(x: center.x - innerRadius, y: center.y - innerRadius,
                                          width: innerRadius * 2, height: innerRadius * 2))
        context.fill(disc, with: .radialGradient(Gradient(colors: [colors.top.opacity(0.15 + 0.5 * bass),
                                                                   colors.bottom.opacity(0.1)]),
                                                 center: center,
                                                 startRadius: 0,
                                                 endRadius: innerRadius))
        context.stroke(disc, with: .color(colors.top.opacity(0.6)), lineWidth: 1.5)
    }

    // MARK: Blob

    /// Three overlapping, slowly turning shapes whose outlines bulge with the band levels.
    private static func drawBlob(_ bands: [Float], colors: Colors, time: TimeInterval,
                                 in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let side = min(size.width, size.height)
        // Fewer, wider bands keep the outline soft
        let merged = stride(from: 0, to: bands.count - 1, by: 2).map { (bands[$0] + bands[$0 + 1]) / 2 }
        let outline = merged + merged.reversed()
        let layers: [(color: Color, spin: Double, scale: CGFloat, shift: Int)] = [
            (colors.bottom, 0.15, 1.0, 0),
            (colors.top, -0.11, 0.82, 4),
            (colors.bottom.mix(with: colors.top, by: 0.5), 0.07, 0.64, 9)
        ]
        var layerContext = context
        layerContext.blendMode = .plusLighter
        layerContext.opacity = 0.65
        for layer in layers {
            let baseRadius = side * 0.2 * layer.scale
            let reach = side * 0.26 * layer.scale
            let rotation = (time * layer.spin).truncatingRemainder(dividingBy: 2 * .pi)
            let points = outline.indices.map { index in
                let level = CGFloat(outline[(index + layer.shift) % outline.count])
                let angle = Double(index) / Double(outline.count) * 2 * .pi + rotation
                let radius = baseRadius + level * reach
                return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
            layerContext.fill(smoothPath(through: points, isClosed: true),
                              with: .radialGradient(Gradient(colors: [layer.color.opacity(0.15), layer.color]),
                                                    center: center,
                                                    startRadius: 0,
                                                    endRadius: baseRadius + reach))
        }
    }

    // MARK: Waves

    /// Glowing ribbons across the middle, one each for the bass, low mids, high mids and treble.
    /// Higher ranges ripple faster and more tightly.
    private static func drawWaves(_ bands: [Float], colors: Colors, time: TimeInterval,
                                  in context: inout GraphicsContext, size: CGSize) {
        let groupCount = 4
        let midY = size.height / 2
        let steps = 72
        var waveContext = context
        waveContext.blendMode = .plusLighter
        for group in 0..<groupCount {
            let lower = group * bands.count / groupCount
            let upper = (group + 1) * bands.count / groupCount
            let energy = CGFloat(bands[lower..<upper].max() ?? 0)
            let amplitude = size.height * 0.42 * energy
            let cycles = 1.0 + Double(group) * 0.6
            let speed = 1.2 + Double(group) * 0.7
            let phase = (time * speed).truncatingRemainder(dividingBy: 2 * .pi) + Double(group) * 1.3
            var wave = Path()
            for step in 0...steps {
                let progress = Double(step) / Double(steps)
                // Pinned to the middle at both edges
                let envelope = sin(progress * .pi)
                let point = CGPoint(x: size.width * progress,
                                    y: midY + amplitude * CGFloat(envelope * sin(progress * cycles * 2 * .pi + phase)))
                if step == 0 { wave.move(to: point) } else { wave.addLine(to: point) }
            }
            let color = colors.bottom.mix(with: colors.top, by: Double(group) / Double(groupCount - 1))
            var area = wave
            area.closeSubpath()
            waveContext.fill(area, with: .color(color.opacity(0.16)))
            var glow = waveContext
            glow.addFilter(.shadow(color: color, radius: 5))
            glow.stroke(wave, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Arcs

    /// Concentric rings like activity rings, each filling clockwise from the top with how loud its range is.
    /// Bass is the outermost ring, and treble the innermost.
    private static func drawArcs(_ bands: [Float], colors: Colors, in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let side = min(size.width, size.height)
        let ringCount = 6
        let lineWidth = side * 0.05
        let outerRadius = side * 0.42
        for ring in 0..<ringCount {
            let level = groupLevel(bands, group: ring, of: ringCount)
            let radius = outerRadius - CGFloat(ring) * lineWidth * 1.25
            let color = colors.bottom.mix(with: colors.top, by: Double(ring) / Double(ringCount - 1))
            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            context.stroke(track, with: .color(color.opacity(0.18)), lineWidth: lineWidth)
            guard level > 0.005 else { continue }
            var arc = Path()
            arc.addArc(center: center, radius: radius,
                       startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * Double(level)), clockwise: false)
            var glow = context
            glow.addFilter(.shadow(color: color.opacity(0.8), radius: 4))
            glow.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }

    // MARK: Ridges

    /// Recent spectra drawn as hills receding into the distance, the newest at the front.
    @MainActor
    private static func drawRidges(_ history: NPVisualizerHistory, colors: Colors, time: TimeInterval,
                                   in context: inout GraphicsContext, size: CGSize) {
        guard let newest = history.frames.last else { return }
        let stride = 4
        let lineCount = 16
        let fraction = history.fractionSinceLastRecord(at: time)
        let lines = history.frames.filter { $0.index % stride == 0 }.suffix(lineCount)
        // Draw from the back, so nearer hills hide the ones behind them
        for frame in lines {
            let age = (Double(newest.index - frame.index) + fraction) / Double(stride * lineCount)
            guard age <= 1 else { continue }
            let depth = CGFloat(age)
            let baseline = size.height * (0.9 - 0.72 * depth)
            let inset = size.width * 0.14 * depth
            let width = size.width - inset * 2
            let amplitude = size.height * 0.3 * (1 - 0.5 * depth)
            // Flat at both ends, with the spectrum in the middle
            var points = [CGPoint(x: inset, y: baseline), CGPoint(x: inset + width * 0.1, y: baseline)]
            for (index, level) in frame.bands.enumerated() {
                points.append(CGPoint(x: inset + width * (0.14 + 0.72 * CGFloat(index) / CGFloat(frame.bands.count - 1)),
                                      y: baseline - CGFloat(level) * amplitude))
            }
            points += [CGPoint(x: inset + width * 0.9, y: baseline), CGPoint(x: inset + width, y: baseline)]
            let line = smoothPath(through: points, isClosed: false)
            var area = line
            area.addLine(to: CGPoint(x: inset + width, y: size.height))
            area.addLine(to: CGPoint(x: inset, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(Color(white: 0.04).opacity(0.92)))
            let color = colors.bottom.mix(with: colors.top, by: Double(depth))
            context.stroke(line, with: .color(color.opacity(1 - 0.75 * Double(depth))),
                           style: StrokeStyle(lineWidth: 2 - depth, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Orbs

    /// Soft glowing orbs drifting around, one for each range, each swelling with how loud its range is.
    private static func drawOrbs(_ bands: [Float], colors: Colors, time: TimeInterval,
                                 in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let side = min(size.width, size.height)
        let orbCount = 6
        var orbContext = context
        orbContext.blendMode = .plusLighter
        for orb in 0..<orbCount {
            let level = CGFloat(groupLevel(bands, group: orb, of: orbCount))
            let horizontal = (time * (0.21 + 0.05 * Double(orb))).truncatingRemainder(dividingBy: 2 * .pi) + Double(orb) * 1.1
            let vertical = (time * (0.17 + 0.04 * Double(orb))).truncatingRemainder(dividingBy: 2 * .pi) + Double(orb) * 2.3
            let position = CGPoint(x: center.x + side * 0.24 * CGFloat(sin(horizontal)),
                                   y: center.y + side * 0.24 * CGFloat(cos(vertical)))
            let radius = side * (0.1 + 0.28 * level)
            let color = colors.bottom.mix(with: colors.top, by: Double(orb) / Double(orbCount - 1))
            orbContext.fill(Path(ellipseIn: CGRect(x: position.x - radius, y: position.y - radius,
                                                   width: radius * 2, height: radius * 2)),
                            with: .radialGradient(Gradient(colors: [color.opacity(0.3 + 0.6 * Double(level)),
                                                                    color.opacity(0)]),
                                                  center: position, startRadius: 0, endRadius: radius))
        }
    }

    // MARK: Pulse

    /// Rings sent out from the center by the bass, fading as they spread, around a core that beats with it.
    @MainActor
    private static func drawPulse(_ bands: [Float], history: NPVisualizerHistory, colors: Colors, time: TimeInterval,
                                  in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let side = min(size.width, size.height)
        let innerRadius = side * 0.1
        let outerRadius = hypot(size.width, size.height) / 2
        let fraction = history.fractionSinceLastRecord(at: time)
        if let newest = history.frames.last {
            for frame in history.frames where frame.index % 3 == 0 {
                let progress = (Double(newest.index - frame.index) + fraction) / Double(NPVisualizerHistory.capacity)
                guard progress <= 1 else { continue }
                // Loud bass makes a bright ring, so beats stand out from the steady parts
                let energy = Double(groupLevel(frame.bands, group: 0, of: 6))
                let opacity = pow(energy, 3) * 1.4 * (1 - progress)
                guard opacity > 0.02 else { continue }
                let radius = innerRadius + CGFloat(progress) * (outerRadius - innerRadius)
                let color = colors.bottom.mix(with: colors.top, by: progress)
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                      width: radius * 2, height: radius * 2)),
                               with: .color(color.opacity(min(opacity, 1))),
                               lineWidth: 1.5 + CGFloat(energy) * 4)
            }
        }
        let bass = CGFloat(groupLevel(bands, group: 0, of: 6))
        let coreRadius = innerRadius * (0.6 + 0.6 * bass)
        var glow = context
        glow.addFilter(.shadow(color: colors.top, radius: 10 * bass + 2))
        glow.fill(Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius,
                                         width: coreRadius * 2, height: coreRadius * 2)),
                  with: .radialGradient(Gradient(colors: [colors.top, colors.bottom]),
                                        center: center, startRadius: 0, endRadius: coreRadius))
    }

    // MARK: Mixer

    /// A mixing desk's level meters, one for each range with bass on the left, lit from the bottom.
    /// The top of each meter is lit in the second color, like the warning zone on a real desk.
    private static func drawMixer(_ bands: [Float], colors: Colors, in context: inout GraphicsContext, size: CGSize) {
        let channelCount = 12
        let segmentCount = 24
        let padding = min(size.width, size.height) * 0.06
        let channelSpacing: CGFloat = 5.0
        let segmentSpacing: CGFloat = 2.0
        let meterWidth = (size.width - padding * 2 - channelSpacing * CGFloat(channelCount - 1)) / CGFloat(channelCount)
        let segmentHeight = (size.height - padding * 2 - segmentSpacing * CGFloat(segmentCount - 1)) / CGFloat(segmentCount)
        let warmColor = colors.bottom.mix(with: colors.top, by: 0.5)

        var unlit = Path()
        var lit: [Path] = [Path(), Path(), Path()]
        for channel in 0..<channelCount {
            let level = groupLevel(bands, group: channel, of: channelCount)
            let litCount = Int((level * Float(segmentCount)).rounded())
            let x = padding + CGFloat(channel) * (meterWidth + channelSpacing)
            for segment in 0..<segmentCount {
                let rect = CGRect(x: x,
                                  y: size.height - padding - CGFloat(segment + 1) * segmentHeight - CGFloat(segment) * segmentSpacing,
                                  width: meterWidth,
                                  height: segmentHeight)
                guard segment < litCount else {
                    unlit.addRoundedRect(in: rect, cornerSize: CGSize(width: 1.5, height: 1.5))
                    continue
                }
                // The lower 70% is the normal zone, then a warm zone, and the top 15% is the hot zone
                let zone = segment < segmentCount * 70 / 100 ? 0 : (segment < segmentCount * 85 / 100 ? 1 : 2)
                lit[zone].addRoundedRect(in: rect, cornerSize: CGSize(width: 1.5, height: 1.5))
            }
        }
        context.fill(unlit, with: .color(.white.opacity(0.08)))
        var glow = context
        glow.addFilter(.shadow(color: colors.bottom.opacity(0.6), radius: 4))
        for (zone, color) in [colors.bottom, warmColor, colors.top].enumerated() {
            glow.fill(lit[zone], with: .color(color))
        }
    }

    /// The loudest band in one of `groupCount` equal ranges, counting from the bass.
    private static func groupLevel(_ bands: [Float], group: Int, of groupCount: Int) -> Float {
        let lower = group * bands.count / groupCount
        let upper = max((group + 1) * bands.count / groupCount, lower + 1)
        return bands[lower..<min(upper, bands.count)].max() ?? 0
    }

    // MARK: Paths

    /// A smooth Catmull-Rom curve through every point.
    private static func smoothPath(through points: [CGPoint], isClosed: Bool) -> Path {
        var path = Path()
        appendSmoothCurve(through: points, isClosed: isClosed, to: &path)
        return path
    }

    /// Adds a smooth Catmull-Rom curve through every point to `path`, joining it to the end of the path with
    /// a straight line if the path isn't empty.
    private static func appendSmoothCurve(through points: [CGPoint], isClosed: Bool = false, to path: inout Path) {
        let count = points.count
        guard count > 1 else { return }
        func point(_ index: Int) -> CGPoint {
            isClosed ? points[(index % count + count) % count] : points[min(max(index, 0), count - 1)]
        }
        if path.isEmpty {
            path.move(to: points[0])
        } else {
            path.addLine(to: points[0])
        }
        for index in 0..<(isClosed ? count : count - 1) {
            let previous = point(index - 1), start = point(index), end = point(index + 1), next = point(index + 2)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x + (end.x - previous.x) / 6, y: start.y + (end.y - previous.y) / 6),
                          control2: CGPoint(x: end.x - (next.x - start.x) / 6, y: end.y - (next.y - start.y) / 6))
        }
        if isClosed { path.closeSubpath() }
    }
}

/// Recent band levels, recorded at a steady rate, for the styles that show the past few seconds.
@MainActor
final class NPVisualizerHistory {

    struct Frame {
        /// Counts up by one for every recorded frame, so styles can pick every nth frame steadily.
        let index: Int
        let bands: [Float]
    }

    static let capacity = 72
    static let frameInterval: TimeInterval = 1.0 / 30.0

    /// Oldest first.
    private(set) var frames: [Frame] = []
    private var nextIndex = 0
    private var lastRecordedTime: TimeInterval?

    func record(_ bands: [Float], at time: TimeInterval) {
        if let lastRecordedTime {
            if time - lastRecordedTime > 0.5 {
                // The visualizer was paused, so the old frames would show as a jump
                frames.removeAll()
            } else if time - lastRecordedTime < Self.frameInterval * 0.9 {
                return
            }
        }
        lastRecordedTime = time
        frames.append(Frame(index: nextIndex, bands: bands))
        nextIndex += 1
        if frames.count > Self.capacity {
            frames.removeFirst(frames.count - Self.capacity)
        }
    }

    /// How far, from 0 to 1, `time` is towards the next recorded frame, for moving smoothly between frames.
    func fractionSinceLastRecord(at time: TimeInterval) -> Double {
        guard let lastRecordedTime else { return 0 }
        return min(max((time - lastRecordedTime) / Self.frameInterval, 0), 1)
    }
}
