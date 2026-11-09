import SwiftUI

/// A graphic equalizer style display of the playing audio, shown on the back of the Now Playing artwork.
///
/// A glass button in the corner switches to a carousel of every style, each drawn live, to choose from.
struct NPVisualizer: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var albumArt: Image
    /// Whether this face of the artwork is turned towards the user.
    var isFaceUp: Bool
    @Binding var isChoosingStyle: Bool

    @AppStorage(NPVisualizerStyle.storageKey) private var style: NPVisualizerStyle = .bars
    @State private var palette: [Color] = []
    @State private var history = NPVisualizerHistory()
    @State private var isAnalysing: Bool = false

    private var shouldAnalyse: Bool {
        isFaceUp && scenePhase == .active && !mediaPlayer.isCurrentlyPlayingVideo()
    }

    var body: some View {
        let isPlaying = !mediaPlayer.isPaused
        let colors = barColors
        let style = style
        let history = history
        ZStack {
            Color.black
            albumArt
                .resizable()
                .scaledToFill()
                .blur(radius: 32.0)
                .opacity(0.45)
            TimelineView(.animation(paused: !shouldAnalyse)) { timeline in
                // Analysed once a frame, and shared by every style drawn in the frame
                let time = timeline.date.timeIntervalSinceReferenceDate
                let levels = mediaPlayer.spectrumAnalyzer.levels(at: time, isPlaying: isPlaying)
                let frame = NPVisualizerFrame(bands: levels.bands, time: time, colors: colors, history: history)
                let _ = history.record(levels.bands, at: time)
                if isChoosingStyle {
                    NPVisualizerPicker(frame: frame, selection: style) { newStyle in
                        choose(newStyle)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.15)))
                } else {
                    NPVisualizerCanvas(style: style, frame: frame)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            switchButton
        }
        .onChange(of: shouldAnalyse, initial: true) { _, newValue in
            setAnalysing(newValue)
        }
        .onDisappear {
            setAnalysing(false)
        }
        .task(id: paletteKey) {
            await updatePalette()
        }
    }

    // MARK: Choosing a Style

    private var switchButton: some View {
        Button {
            withAnimation(switchAnimation) {
                isChoosingStyle.toggle()
            }
        } label: {
            Group {
                if isChoosingStyle {
                    Image(systemName: "xmark")
                } else {
                    Image(systemName: "arrow.left.arrow.right")
                }
            }
            .font(.system(size: 16.0, weight: .semibold))
            .frame(width: 24.0, height: 24.0)
        }
        .buttonStyle(.glass(.clear))
        .buttonBorderShape(.circle)
        .foregroundStyle(.white)
        .padding(10.0)
        .accessibilityLabel(
            isChoosingStyle ?
            String(localized: "Shared.Cancel") :
            String(localized: "NowPlaying.ChooseVisualizer")
        )
    }

    private var switchAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.2)
    }

    private func choose(_ newStyle: NPVisualizerStyle) {
        style = newStyle
        withAnimation(switchAnimation) {
            isChoosingStyle = false
        }
    }

    // MARK: Colors

    private var paletteKey: String {
        "\(mediaPlayer.currentlyPlayingID)|\(mediaPlayer.metadataRefreshTrigger)"
    }

    /// The bottom and top colors of the bars: the artwork's most prominent colors, or the accent color.
    private var barColors: NPVisualizerStyle.Colors {
        switch palette.count {
        case 0: (Color.accentColor, Color.accentColor.mix(with: .white, by: 0.4))
        case 1: (palette[0], palette[0].mix(with: .white, by: 0.4))
        default: (palette[0], palette[1])
        }
    }

    private func updatePalette() async {
        guard let image = mediaPlayer.embeddedAlbumArt() else {
            withAnimation { palette = [] }
            return
        }
        let colors = await Task.detached(priority: .utility) {
            image.prominentColors(count: 2)
        }.value
        guard !Task.isCancelled else { return }
        withAnimation { palette = colors.map(Color.init(uiColor:)) }
    }

    // MARK: Analysis

    private func setAnalysing(_ newValue: Bool) {
        guard newValue != isAnalysing else { return }
        isAnalysing = newValue
        if newValue {
            mediaPlayer.startSpectrumAnalysis()
        } else {
            mediaPlayer.stopSpectrumAnalysis()
        }
    }
}

/// Everything a style needs to draw one frame.
struct NPVisualizerFrame {
    let bands: [Float]
    let time: TimeInterval
    let colors: NPVisualizerStyle.Colors
    let history: NPVisualizerHistory
}

/// One style, drawn for a frame.
struct NPVisualizerCanvas: View {

    let style: NPVisualizerStyle
    let frame: NPVisualizerFrame

    var body: some View {
        // The canvas redraws because the frame it captures changes every time
        Canvas { context, size in
            style.draw(frame.bands, colors: frame.colors, time: frame.time, history: frame.history,
                       in: &context, size: size)
        }
    }
}

/// A carousel of every style, each drawn live, to choose the one to use.
struct NPVisualizerPicker: View {

    let frame: NPVisualizerFrame
    let selection: NPVisualizerStyle
    let onChoose: (NPVisualizerStyle) -> Void

    @State private var centeredStyle: NPVisualizerStyle?

    var body: some View {
        GeometryReader { geometry in
            let previewSide = min(geometry.size.width, geometry.size.height) * 0.58
            VStack(spacing: 0.0) {
                Spacer(minLength: 0.0)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14.0) {
                        ForEach(NPVisualizerStyle.allCases) { style in
                            preview(of: style, side: previewSide)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (geometry.size.width - previewSide) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $centeredStyle, anchor: .center)
                .scrollClipDisabled()
                Spacer(minLength: 0.0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            centeredStyle = selection
        }
    }

    private func preview(of style: NPVisualizerStyle, side: CGFloat) -> some View {
        let isSelected = style == selection
        return Button {
            onChoose(style)
        } label: {
            NPVisualizerCanvas(style: style, frame: frame)
                .frame(width: side, height: side)
                .background(.black.opacity(0.35))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 5.0) {
                        style.icon
                        Text(verbatim: style.name)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3.0)
                    .padding(10.0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12.0))
                .overlay {
                    RoundedRectangle(cornerRadius: 12.0)
                        .strokeBorder(.white.opacity(isSelected ? 0.9 : 0.2), lineWidth: isSelected ? 2.0 : 0.5)
                }
        }
        .buttonStyle(.plain)
        .scrollTransition(axis: .horizontal) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1.0 : 0.82)
                .opacity(phase.isIdentity ? 1.0 : 0.55)
        }
        .accessibilityLabel(Text(verbatim: style.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(style)
    }
}
