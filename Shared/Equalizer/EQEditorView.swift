import SwiftUI

/// The equalizer's curve, with a switch for each band below it.
struct EQEditorView: View {

    @Binding var bands: [EQBand]
    var spectrum: [Float] = []

    @State private var selectedBandID: Int?

    init(bands: Binding<[EQBand]>, spectrum: [Float] = [], selectedBandID: Int? = nil) {
        _bands = bands
        self.spectrum = spectrum
        _selectedBandID = State(initialValue: selectedBandID)
    }

    var body: some View {
        VStack(spacing: 14.0) {
            EQCurveView(bands: $bands, selectedBandID: $selectedBandID, spectrum: spectrum)
                .aspectRatio(1.6, contentMode: .fit)
            GlassEffectContainer(spacing: 6.0) {
                HStack(spacing: 6.0) {
                    ForEach($bands) { $band in
                        EQBandToggle(band: $band, isSelected: band.id == selectedBandID) {
                            withAnimation(.spring(duration: 0.3)) {
                                selectedBandID = band.id
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A switch for one band, showing the shape of its filter in the band's colour.
struct EQBandToggle: View {

    @Binding var band: EQBand
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button {
            if isSelected { band.isEnabled.toggle() }
            onSelect()
        } label: {
            Canvas { context, size in
                let plot = EQPlot(rect: CGRect(origin: .zero, size: size).insetBy(dx: 1.0, dy: 2.0))
                var demo = band
                demo.isEnabled = true
                demo.gain = 18.0
                demo.bandwidth = 2.0
                demo.frequency = switch band.kind {
                case .lowCut: 300.0
                case .lowShelf: 250.0
                case .bell: 640.0
                case .highShelf: 1_600.0
                case .highCut: 1_400.0
                }
                var path = Path()
                for index in 0...40 {
                    let xPosition = plot.rect.minX + plot.rect.width * CGFloat(index) / 40.0
                    let decibels = EQResponse.decibels(of: demo, at: plot.frequency(for: xPosition))
                    let shown = demo.hasGain ? decibels - 9.0 : decibels + 12.0
                    let yPosition = plot.y(for: min(max(shown, -18.0), 18.0))
                    let point = CGPoint(x: xPosition, y: yPosition)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(band.isEnabled ? .white : band.color),
                               style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 16.0)
            .padding(.vertical, 9.0)
            .padding(.horizontal, 5.0)
            .frame(maxWidth: .infinity)
            .contentShape(.capsule)
            .glassEffect(band.isEnabled ? .regular.tint(band.color.opacity(0.8)).interactive() : .regular.interactive(),
                         in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(isSelected ? 0.85 : 0.0), lineWidth: 1.5)
            }
            .scaleEffect(isSelected ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(band.kind.localizedName))
        .accessibilityAddTraits(band.isEnabled ? .isSelected : [])
    }
}
