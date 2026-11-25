import SwiftUI

/// An interactive graph of the equalizer's curve, with a translucent fill for each band over the live spectrum.
///
/// Drag a band's handle to change its frequency and gain, pinch to change a bell's width,
/// and double tap a handle to flatten its band.
struct EQCurveView: View {

    @Binding var bands: [EQBand]
    @Binding var selectedBandID: Int?
    /// Levels from 0 to 1, lowest frequency first, spread between `spectrumFrequencies`.
    var spectrum: [Float] = []

    static let spectrumFrequencies: ClosedRange<Double> = 40.0...16_000.0
    private static let hitRadius: CGFloat = 30.0
    private static let sampleCount = 160
    private static let labelledFrequencies: [Double] = [20, 50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000]

    @State private var draggedBandID: Int?
    @State private var dragOffset: CGSize = .zero
    @State private var pinchStartBandwidth: Double?

    var body: some View {
        GeometryReader { geometry in
            let plot = EQPlot(rect: plotRect(in: geometry.size))
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(in: &context, plot: plot, size: size)
                    var clipped = context
                    clipped.clip(to: Path(plot.rect))
                    drawSpectrum(in: &clipped, plot: plot)
                    drawBandFills(in: &clipped, plot: plot)
                    drawTotalCurve(in: &clipped, plot: plot)
                }
                ForEach(bands) { band in
                    EQBandHandle(band: band,
                                 isSelected: band.id == selectedBandID,
                                 isDragged: band.id == draggedBandID)
                        .position(handleCenter(for: band, plot: plot))
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(plot: plot))
            .simultaneousGesture(pinchGesture)
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                if let id = band(near: value.location, plot: plot) { reset(id) }
            })
        }
        .background {
            RoundedRectangle(cornerRadius: 24.0, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.14), Color(white: 0.05)],
                                     startPoint: .top, endPoint: .bottom))
                .opacity(0.9)
        }
        .environment(\.colorScheme, .dark)
    }

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: 10.0, y: 12.0, width: max(size.width - 44.0, 1.0), height: max(size.height - 34.0, 1.0))
    }

    // MARK: Drawing

    private func drawGrid(in context: inout GraphicsContext, plot: EQPlot, size: CGSize) {
        var major = Path()
        for frequency in Self.labelledFrequencies {
            let xPosition = plot.x(for: frequency)
            major.move(to: CGPoint(x: xPosition, y: plot.rect.minY))
            major.addLine(to: CGPoint(x: xPosition, y: plot.rect.maxY))
            context.draw(Text(Self.shortLabel(for: frequency))
                            .font(.system(size: 9.0, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.45)),
                         at: CGPoint(x: min(max(xPosition, plot.rect.minX + 8.0), plot.rect.maxX - 8.0),
                                     y: plot.rect.maxY + 11.0))
        }
        for decibels in stride(from: -EQPlot.decibelRange, through: EQPlot.decibelRange, by: 6.0) where decibels != 0 {
            let yPosition = plot.y(for: decibels)
            major.move(to: CGPoint(x: plot.rect.minX, y: yPosition))
            major.addLine(to: CGPoint(x: plot.rect.maxX, y: yPosition))
        }
        context.stroke(major, with: .color(.white.opacity(0.08)), lineWidth: 1.0)

        var zero = Path()
        zero.move(to: CGPoint(x: plot.rect.minX, y: plot.y(for: 0)))
        zero.addLine(to: CGPoint(x: plot.rect.maxX, y: plot.y(for: 0)))
        context.stroke(zero, with: .color(.white.opacity(0.22)), lineWidth: 1.0)

        for decibels in stride(from: -EQPlot.decibelRange, through: EQPlot.decibelRange, by: 6.0) {
            let label = decibels > 0 ? "+\(Int(decibels))" : "\(Int(decibels))"
            context.draw(Text(label)
                            .font(.system(size: 9.0, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.45)),
                         at: CGPoint(x: plot.rect.maxX + 6.0, y: plot.y(for: decibels)),
                         anchor: .leading)
        }
    }

    private func drawSpectrum(in context: inout GraphicsContext, plot: EQPlot) {
        guard spectrum.count > 1 else { return }
        let low = log10(Self.spectrumFrequencies.lowerBound), high = log10(Self.spectrumFrequencies.upperBound)
        let points = spectrum.enumerated().map { index, level in
            let position = Double(index) / Double(spectrum.count - 1)
            let frequency = pow(10.0, low + (high - low) * position)
            return CGPoint(x: plot.x(for: frequency),
                           y: plot.rect.maxY - CGFloat(min(max(level, 0), 1)) * plot.rect.height * 0.9)
        }
        var path = Path()
        path.move(to: CGPoint(x: plot.rect.minX, y: plot.rect.maxY))
        path.addLine(to: CGPoint(x: plot.rect.minX, y: points[0].y))
        path.addLine(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1], point = points[index]
            let middle = CGPoint(x: (previous.x + point.x) / 2.0, y: (previous.y + point.y) / 2.0)
            path.addQuadCurve(to: middle, control: previous)
        }
        path.addLine(to: points[points.count - 1])
        path.addLine(to: CGPoint(x: plot.rect.maxX, y: points[points.count - 1].y))
        path.addLine(to: CGPoint(x: plot.rect.maxX, y: plot.rect.maxY))
        path.closeSubpath()
        context.fill(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.11), .white.opacity(0.02)]),
                                                 startPoint: CGPoint(x: 0, y: plot.rect.minY),
                                                 endPoint: CGPoint(x: 0, y: plot.rect.maxY)))
    }

    private func drawBandFills(in context: inout GraphicsContext, plot: EQPlot) {
        var layer = context
        layer.blendMode = .plusLighter
        let zeroY = plot.y(for: 0)
        for band in bands where band.isEnabled {
            let curve = curvePath(plot: plot) { EQResponse.decibels(of: band, at: $0) }
            var fill = curve
            fill.addLine(to: CGPoint(x: plot.rect.maxX, y: zeroY))
            fill.addLine(to: CGPoint(x: plot.rect.minX, y: zeroY))
            fill.closeSubpath()
            let strength = band.id == selectedBandID ? 1.0 : 0.7
            let gradient = Gradient(stops: [
                .init(color: band.color.opacity(0.75 * strength), location: 0.0),
                .init(color: band.color.opacity(0.22 * strength), location: 0.5),
                .init(color: band.color.opacity(0.75 * strength), location: 1.0)
            ])
            layer.fill(fill, with: .linearGradient(gradient,
                                                   startPoint: CGPoint(x: 0, y: plot.y(for: 8.0)),
                                                   endPoint: CGPoint(x: 0, y: plot.y(for: -8.0))))
            layer.stroke(curve, with: .color(band.color.opacity(0.9 * strength)), lineWidth: 1.0)
        }
    }

    private func drawTotalCurve(in context: inout GraphicsContext, plot: EQPlot) {
        let bands = bands
        let curve = curvePath(plot: plot) { EQResponse.decibels(of: bands, at: $0) }
        var glow = context
        glow.addFilter(.blur(radius: 4.0))
        glow.stroke(curve, with: .color(.white.opacity(0.45)), lineWidth: 3.0)
        context.stroke(curve, with: .color(.white), style: StrokeStyle(lineWidth: 1.75, lineJoin: .round))
    }

    private func curvePath(plot: EQPlot, decibels: (Double) -> Double) -> Path {
        var path = Path()
        for index in 0...Self.sampleCount {
            let xPosition = plot.rect.minX + plot.rect.width * CGFloat(index) / CGFloat(Self.sampleCount)
            let yPosition = plot.y(for: max(decibels(plot.frequency(for: xPosition)), -EQPlot.decibelRange * 3.0))
            if index == 0 {
                path.move(to: CGPoint(x: xPosition, y: yPosition))
            } else {
                path.addLine(to: CGPoint(x: xPosition, y: yPosition))
            }
        }
        return path
    }

    private func handleCenter(for band: EQBand, plot: EQPlot) -> CGPoint {
        CGPoint(x: plot.x(for: band.frequency), y: plot.y(for: band.hasGain ? band.gain : 0.0))
    }

    // MARK: Gestures

    private func band(near location: CGPoint, plot: EQPlot) -> Int? {
        let nearest = bands.map { band -> (Int, CGFloat) in
            let center = handleCenter(for: band, plot: plot)
            return (band.id, hypot(center.x - location.x, center.y - location.y))
        }
        .min { $0.1 < $1.1 }
        guard let nearest, nearest.1 <= Self.hitRadius else { return nil }
        return nearest.0
    }

    private func dragGesture(plot: EQPlot) -> some Gesture {
        DragGesture(minimumDistance: 0.0)
            .onChanged { value in
                if draggedBandID == nil {
                    guard let id = band(near: value.startLocation, plot: plot),
                          let band = bands.first(where: { $0.id == id }) else { return }
                    let center = handleCenter(for: band, plot: plot)
                    withAnimation(.spring(duration: 0.3, bounce: 0.35)) {
                        draggedBandID = id
                    }
                    dragOffset = CGSize(width: center.x - value.startLocation.x,
                                        height: center.y - value.startLocation.y)
                    selectedBandID = id
                }
                guard let id = draggedBandID, let index = bands.firstIndex(where: { $0.id == id }) else { return }
                let xPosition = min(max(value.location.x + dragOffset.width, plot.rect.minX), plot.rect.maxX)
                let yPosition = min(max(value.location.y + dragOffset.height, plot.rect.minY), plot.rect.maxY)
                bands[index].isEnabled = true
                bands[index].frequency = plot.frequency(for: xPosition)
                if bands[index].hasGain {
                    let gain = (plot.decibels(for: yPosition) * 2.0).rounded() / 2.0
                    bands[index].gain = min(max(gain, EQBand.gainRange.lowerBound), EQBand.gainRange.upperBound)
                }
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.35, bounce: 0.35)) {
                    draggedBandID = nil
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let id = selectedBandID, let index = bands.firstIndex(where: { $0.id == id }),
                      bands[index].kind == .bell else { return }
                let start = pinchStartBandwidth ?? bands[index].bandwidth
                pinchStartBandwidth = start
                let bandwidth = start / Double(value.magnification)
                bands[index].bandwidth = min(max(bandwidth, EQBand.bandwidthRange.lowerBound),
                                             EQBand.bandwidthRange.upperBound)
            }
            .onEnded { _ in
                pinchStartBandwidth = nil
            }
    }

    private func reset(_ id: Int) {
        guard let index = bands.firstIndex(where: { $0.id == id }) else { return }
        bands[index].gain = 0.0
        bands[index].bandwidth = 1.0
    }

    static func shortLabel(for frequency: Double) -> String {
        frequency >= 1_000 ? "\(Int(frequency / 1_000))k" : "\(Int(frequency))"
    }
}

/// A band's handle: a marble of glass tinted in the band's colour, which swells into a clear lens while dragged.
struct EQBandHandle: View {

    var band: EQBand
    var isSelected: Bool
    var isDragged: Bool

    var body: some View {
        let diameter: CGFloat = isDragged ? 40.0 : (isSelected ? 22.0 : 17.0)
        Circle()
            .fill(.clear)
            .frame(width: diameter, height: diameter)
            .glassEffect(glass, in: .circle)
            .overlay {
                Circle()
                    .strokeBorder(band.isEnabled ? .white.opacity(isSelected ? 0.9 : 0.35) : band.color,
                                  lineWidth: isSelected || !band.isEnabled ? 1.5 : 1.0)
            }
            .shadow(color: band.isEnabled ? band.color.opacity(isSelected ? 0.7 : 0.4) : .clear,
                    radius: isSelected ? 8.0 : 4.0)
            .allowsHitTesting(false)
    }

    private var glass: Glass {
        guard band.isEnabled else { return .regular }
        return .regular.tint(band.color.opacity(isDragged ? 0.3 : 0.9))
    }
}

/// Converts between frequencies and decibels and points in the graph, with frequency on a logarithmic scale.
struct EQPlot {

    static let decibelRange: Double = 18.0

    var rect: CGRect

    private static let lowLog = log10(EQBand.minimumFrequency)
    private static let highLog = log10(EQBand.maximumFrequency)

    func x(for frequency: Double) -> CGFloat {
        let position = (log10(frequency) - Self.lowLog) / (Self.highLog - Self.lowLog)
        return rect.minX + rect.width * CGFloat(position)
    }

    func frequency(for xPosition: CGFloat) -> Double {
        let position = Double((xPosition - rect.minX) / rect.width)
        return pow(10.0, Self.lowLog + (Self.highLog - Self.lowLog) * position)
    }

    func y(for decibels: Double) -> CGFloat {
        rect.midY - CGFloat(decibels / Self.decibelRange) * rect.height / 2.0
    }

    func decibels(for yPosition: CGFloat) -> Double {
        Double((rect.midY - yPosition) / (rect.height / 2.0)) * Self.decibelRange
    }
}
