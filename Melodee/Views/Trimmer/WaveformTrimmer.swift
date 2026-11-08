import SwiftUI

enum TrimMode: Hashable {
    /// Dragging moves the playhead, so the selection can be listened to.
    case preview
    /// Dragging moves the start and end handles.
    case trim
}

/// A waveform with handles for the start and end of the part to keep, and a playhead.
/// Only one kind of drag is active at a time, chosen by `mode`, so handles and the playhead never compete.
struct WaveformTrimmer: View {

    var waveform: Waveform
    @Binding var range: ClosedRange<TimeInterval>
    var playhead: TimeInterval
    var mode: TrimMode
    /// Called with the time under the finger while scrubbing in preview mode, and whether the drag ended.
    var onScrub: (TimeInterval, Bool) -> Void

    @State private var draggedHandle: Handle?

    private enum Handle {
        case start
        case end
    }

    static let handleWidth: CGFloat = 16.0
    static let frameWidth: CGFloat = 3.0
    static let barWidth: CGFloat = 2.0
    static let barSpacing: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    drawWaveform(in: &context, size: canvasSize)
                }
                selectionFrame(size: size)
                if mode == .preview {
                    playheadLine(size: size)
                }
            }
            .contentShape(.rect)
            .gesture(dragGesture(size: size))
        }
        .sensoryFeedback(.selection, trigger: draggedHandle) { _, newValue in newValue != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Trim.Waveform"))
        .accessibilityValue(Text(verbatim: "\(TrimTime.string(range.lowerBound)) – \(TrimTime.string(range.upperBound))"))
    }

    // MARK: Geometry

    private func trackWidth(_ size: CGSize) -> CGFloat {
        max(size.width - Self.handleWidth * 2, 1)
    }

    private func xPosition(for time: TimeInterval, size: CGSize) -> CGFloat {
        guard waveform.duration > 0 else { return Self.handleWidth }
        return Self.handleWidth + CGFloat(time / waveform.duration) * trackWidth(size)
    }

    private func time(at x: CGFloat, size: CGSize) -> TimeInterval {
        let fraction = (x - Self.handleWidth) / trackWidth(size)
        return min(max(Double(fraction), 0), 1) * waveform.duration
    }

    // MARK: Drawing

    private func drawWaveform(in context: inout GraphicsContext, size: CGSize) {
        let peaks = waveform.peaks
        guard !peaks.isEmpty else { return }
        let width = trackWidth(size)
        let step = Self.barWidth + Self.barSpacing
        let barCount = max(Int(width / step), 1)
        let midY = size.height / 2
        let maxBarHeight = size.height - Self.frameWidth * 2 - 8.0
        let startX = xPosition(for: range.lowerBound, size: size)
        let endX = xPosition(for: range.upperBound, size: size)

        var selected = Path()
        var unselected = Path()
        for bar in 0..<barCount {
            let lower = bar * peaks.count / barCount
            let upper = max((bar + 1) * peaks.count / barCount, lower + 1)
            let peak = peaks[lower..<min(upper, peaks.count)].max() ?? 0
            let height = max(CGFloat(peak) * maxBarHeight, 1.5)
            let x = Self.handleWidth + CGFloat(bar) * step
            let rect = CGRect(x: x, y: midY - height / 2, width: Self.barWidth, height: height)
            if x + Self.barWidth / 2 >= startX && x + Self.barWidth / 2 <= endX {
                selected.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
            } else {
                unselected.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
            }
        }
        context.fill(unselected, with: .color(.secondary.opacity(0.35)))
        context.fill(selected, with: .color(.primary))
    }

    private func selectionFrame(size: CGSize) -> some View {
        let startX = xPosition(for: range.lowerBound, size: size)
        let endX = xPosition(for: range.upperBound, size: size)
        let isEditable = mode == .trim
        return ZStack(alignment: .topLeading) {
            // Top and bottom edges of the frame
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: max(endX - startX, 0), height: Self.frameWidth)
                .offset(x: startX)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: max(endX - startX, 0), height: Self.frameWidth)
                .offset(x: startX, y: size.height - Self.frameWidth)
            handle(systemImage: "chevron.compact.left", corners: .leading, isEditable: isEditable)
                .frame(width: Self.handleWidth, height: size.height)
                .offset(x: startX - Self.handleWidth)
            handle(systemImage: "chevron.compact.right", corners: .trailing, isEditable: isEditable)
                .frame(width: Self.handleWidth, height: size.height)
                .offset(x: endX)
        }
    }

    private func handle(systemImage: String, corners: HorizontalEdge, isEditable: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: corners == .leading ? 6 : 0,
            bottomLeadingRadius: corners == .leading ? 6 : 0,
            bottomTrailingRadius: corners == .trailing ? 6 : 0,
            topTrailingRadius: corners == .trailing ? 6 : 0
        )
        .fill(Color.accentColor.opacity(isEditable ? 1.0 : 0.5))
        .overlay {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .opacity(isEditable ? 1.0 : 0.0)
        }
    }

    private func playheadLine(size: CGSize) -> some View {
        let x = xPosition(for: min(max(playhead, range.lowerBound), range.upperBound), size: size)
        return Capsule()
            .fill(Color.primary)
            .frame(width: 2.0, height: size.height + 8.0)
            .shadow(color: .black.opacity(0.25), radius: 2)
            .offset(x: x - 1.0, y: -4.0)
    }

    // MARK: Dragging

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let time = time(at: value.location.x, size: size)
                switch mode {
                case .trim:
                    if draggedHandle == nil {
                        draggedHandle = nearestHandle(to: value.startLocation.x, size: size)
                    }
                    move(draggedHandle ?? .end, to: time)
                case .preview:
                    onScrub(min(max(time, range.lowerBound), range.upperBound), false)
                }
            }
            .onEnded { value in
                if mode == .preview {
                    let time = time(at: value.location.x, size: size)
                    onScrub(min(max(time, range.lowerBound), range.upperBound), true)
                }
                draggedHandle = nil
            }
    }

    private func nearestHandle(to x: CGFloat, size: CGSize) -> Handle {
        let startX = xPosition(for: range.lowerBound, size: size) - Self.handleWidth / 2
        let endX = xPosition(for: range.upperBound, size: size) + Self.handleWidth / 2
        return abs(x - startX) <= abs(x - endX) ? .start : .end
    }

    private func move(_ handle: Handle, to time: TimeInterval) {
        let minimumLength = min(MediaTrimmer.minimumLength, waveform.duration)
        switch handle {
        case .start:
            let start = min(max(time, 0), range.upperBound - minimumLength)
            range = start...range.upperBound
        case .end:
            let end = max(min(time, waveform.duration), range.lowerBound + minimumLength)
            range = range.lowerBound...end
        }
    }
}

/// Formats trim times as minutes, seconds and hundredths, such as 2:05.40.
enum TrimTime {
    static func string(_ time: TimeInterval) -> String {
        let hundredths = Int((max(time, 0) * 100).rounded())
        let seconds = hundredths / 100 % 60
        let minutes = hundredths / 6000 % 60
        let hours = hundredths / 360000
        let fraction = hundredths % 100
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, fraction)
        }
        return String(format: "%d:%02d.%02d", minutes, seconds, fraction)
    }
}
