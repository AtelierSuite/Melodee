import SwiftUI

struct OnboardingStageLayout {
    struct Tile {
        var frame: CGRect
        var cornerRadius: CGFloat
        var tint: Color
        var symbol: String
        var symbolColor: Color
        var angle: Double
        var opacity: Double
    }

    struct Bar {
        var frame: CGRect
        var color: Color
        var opacity: Double
    }

    struct Row {
        var frame: CGRect
        var symbol: String
        var lineWidth: CGFloat
        var accessory: String?
        var delay: Double
    }

    struct Overlay {
        var frame: CGRect
        var scale: CGFloat
        var opacity: Double
    }

    static let barCount = 22
    static let rowCount = 3
    static let homeIconColumns = 4
    static let homeIconRows = 3

    private static let waveform: [CGFloat] = [
        0.12, 0.2, 0.32, 0.5, 0.78, 0.6, 0.92, 1.0, 0.7, 0.86, 0.52,
        0.95, 0.64, 0.82, 0.56, 0.74, 0.42, 0.6, 0.34, 0.24, 0.16, 0.1
    ]
    private static let trimmedBars = 4

    let size: CGSize
    let feature: OnboardingFeature
    let phase: Int
    let time: TimeInterval

    var isSettled: Bool { phase >= 1 }
    var isInPictureInPicture: Bool { feature == .video && phase >= 2 }
    private var midX: CGFloat { size.width / 2.0 }
    private var midY: CGFloat { size.height / 2.0 }

    var tile: Tile {
        switch feature {
        case .music:
            Tile(
                frame: CGRect(x: 24.0, y: midY - 52.0, width: 104.0, height: 104.0),
                cornerRadius: 22.0, tint: .clear, symbol: "music.note",
                symbolColor: .white, angle: 0.0, opacity: 1.0
            )
        case .video:
            Tile(
                frame: videoFrame,
                cornerRadius: isInPictureInPicture ? 14.0 : 20.0, tint: .black.opacity(0.35), symbol: "play.fill",
                symbolColor: .white, angle: 0.0, opacity: 1.0
            )
        case .tags:
            Tile(
                frame: CGRect(x: 24.0, y: midY - 50.0, width: 100.0, height: 100.0),
                cornerRadius: 22.0, tint: .clear, symbol: "music.note",
                symbolColor: .white, angle: 0.0, opacity: 1.0
            )
        case .trimming:
            Tile(
                frame: CGRect(x: midX - 26.0, y: -110.0, width: 52.0, height: 66.0),
                cornerRadius: 10.0, tint: .white.opacity(0.6), symbol: "music.note",
                symbolColor: OnboardingFeature.music.tint, angle: 0.0, opacity: 0.0
            )
        case .files:
            Tile(
                frame: CGRect(x: 24.0, y: midY - 50.0, width: 100.0, height: 100.0),
                cornerRadius: 22.0, tint: OnboardingFeature.files.tint.opacity(0.35), symbol: "folder.fill",
                symbolColor: .white, angle: 0.0, opacity: 1.0
            )
        }
    }

    private var videoFrame: CGRect {
        if isInPictureInPicture {
            let width = min(size.width * 0.46, 168.0)
            let height = width * 9.0 / 16.0
            return CGRect(x: size.width - 14.0 - width, y: size.height - 14.0 - height, width: width, height: height)
        }
        let width = min(size.width - 56.0, 300.0)
        let height = min(width * 9.0 / 16.0, size.height - 56.0)
        return CGRect(x: midX - width / 2.0, y: midY - height / 2.0, width: width, height: height)
    }

    func homeIcon(_ index: Int) -> Overlay {
        let iconSize = 50.0
        let columns = CGFloat(Self.homeIconColumns)
        let rows = CGFloat(Self.homeIconRows)
        let spacingX = (size.width - 56.0 - iconSize * columns) / (columns - 1.0)
        let spacingY = (size.height - 40.0 - iconSize * rows) / (rows - 1.0)
        let column = CGFloat(index % Self.homeIconColumns)
        let row = CGFloat(index / Self.homeIconColumns)
        let frame = CGRect(
            x: 28.0 + column * (iconSize + spacingX),
            y: 20.0 + row * (iconSize + spacingY),
            width: iconSize,
            height: iconSize
        )
        return Overlay(frame: frame, scale: isInPictureInPicture ? 1.0 : 0.6, opacity: isInPictureInPicture ? 1.0 : 0.0)
    }

    func bar(_ index: Int) -> Bar {
        let count = CGFloat(Self.barCount)
        switch feature {
        case .music:
            let visualizer = visualizerFrame
            let step = visualizer.width / count
            return Bar(
                frame: CGRect(x: visualizer.minX + step * CGFloat(index), y: midY - 1.0, width: step * 0.6, height: 2.0),
                color: .white, opacity: 0.0
            )
        case .video:
            let track = videoProgress.track
            let step = track.width / count
            return Bar(
                frame: CGRect(x: track.minX + step * CGFloat(index), y: track.minY, width: step, height: track.height),
                color: .white, opacity: 0.0
            )
        case .tags:
            let center = CGPoint(x: tile.frame.midX, y: tile.frame.midY)
            return Bar(frame: CGRect(origin: center, size: CGSize(width: 4.0, height: 4.0)), color: .white, opacity: 0.0)
        case .trimming:
            let frame = waveformBarFrame(index)
            let isKept = !isSettled || (index >= Self.trimmedBars && index < Self.barCount - Self.trimmedBars)
            return Bar(frame: frame, color: isKept ? .white : .white.opacity(0.35), opacity: 1.0)
        case .files:
            let center = CGPoint(x: tile.frame.midX, y: tile.frame.midY)
            return Bar(frame: CGRect(origin: center, size: CGSize(width: 4.0, height: 4.0)), color: .white, opacity: 0.0)
        }
    }

    private var waveformStep: CGFloat { (size.width - 80.0) / CGFloat(Self.barCount) }

    private func waveformBarFrame(_ index: Int) -> CGRect {
        let height = 14.0 + (size.height * 0.5) * Self.waveform[index]
        return CGRect(
            x: 40.0 + waveformStep * CGFloat(index) + waveformStep * 0.2,
            y: midY - height / 2.0,
            width: waveformStep * 0.6,
            height: height
        )
    }

    var visualizerFrame: CGRect {
        CGRect(x: 20.0, y: 20.0, width: size.width - 40.0, height: size.height - 40.0)
    }

    var visualizerBands: [Float] {
        (0..<SpectrumAnalyzer.bandCount).map { index in
            let phase = Double(index) * 0.8
            let level = 0.5 + 0.3 * sin(time * 3.1 + phase) + 0.2 * sin(time * 5.3 + phase * 1.7)
            let tilt = 1.0 - Double(index) / Double(SpectrumAnalyzer.bandCount) * 0.45
            return Float(min(1.0, max(0.05, level * tilt)))
        }
    }

    var showsRows: Bool { feature == .tags || feature == .files }

    func row(_ index: Int) -> Row {
        let rowHeight = 40.0
        let spacing = 10.0
        let minX = tile.frame.maxX + 20.0
        let width = size.width - 24.0 - minX
        let top = midY - (rowHeight * 3.0 + spacing * 2.0) / 2.0
        let expanded = CGRect(x: minX, y: top + CGFloat(index) * (rowHeight + spacing), width: width, height: rowHeight)
        let collapsed = CGRect(x: tile.frame.midX - 20.0, y: tile.frame.midY - 20.0, width: 40.0, height: 40.0)
        let frame = isSettled ? expanded : collapsed
        let delay = Double(index) * 0.08
        if feature == .tags {
            let symbols = ["textformat", "person.fill", "square.stack.fill"]
            let lineWidths: [CGFloat] = [0.85, 0.6, 0.72]
            return Row(
                frame: frame,
                symbol: symbols[index],
                lineWidth: isSettled ? lineWidths[index] : 0.0,
                accessory: index == 0 && isSettled ? "pencil" : nil,
                delay: delay
            )
        }
        let symbols = [UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone", "icloud.fill", "folder.badge.plus"]
        let lineWidths: [CGFloat] = [0.75, 0.6, 0.5]
        return Row(
            frame: frame,
            symbol: symbols[index],
            lineWidth: lineWidths[index],
            accessory: index == 0 && isSettled ? "checkmark" : nil,
            delay: delay
        )
    }

    var videoProgress: (track: CGRect, played: CGFloat, opacity: Double) {
        let video = videoFrame
        let inset = isInPictureInPicture ? 10.0 : 18.0
        let height = isInPictureInPicture ? 3.0 : 4.0
        let track = CGRect(x: video.minX + inset, y: video.maxY - inset, width: video.width - inset * 2.0, height: height)
        return (track, [0.25, 0.55, 0.75][min(phase, 2)], feature == .video ? 1.0 : 0.0)
    }

    var subtitle: Overlay {
        let video = videoFrame
        let width = video.width * 0.4
        let height = isInPictureInPicture ? 5.0 : 8.0
        let frame = CGRect(x: video.midX - width / 2.0, y: video.maxY - (isInPictureInPicture ? 24.0 : 40.0), width: width, height: height)
        let isShown = feature == .video && isSettled
        return Overlay(frame: frame, scale: isShown ? 1.0 : 0.0, opacity: isShown ? 1.0 : 0.0)
    }

    var trimFrame: Overlay {
        let first = isSettled ? Self.trimmedBars : 0
        let last = isSettled ? Self.barCount - 1 - Self.trimmedBars : Self.barCount - 1
        let minX = 40.0 + waveformStep * CGFloat(first) - 12.0
        let maxX = 40.0 + waveformStep * CGFloat(last + 1) + 12.0
        let height = size.height * 0.5 + 44.0
        let frame = CGRect(x: minX, y: midY - height / 2.0, width: maxX - minX, height: height)
        return Overlay(frame: frame, scale: 1.0, opacity: feature == .trimming ? 1.0 : 0.0)
    }
}
