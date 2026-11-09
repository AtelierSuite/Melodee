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
        guard let cgImage = mediaPlayer.embeddedAlbumArt()?.cgImage else {
            withAnimation { palette = [] }
            return
        }
        let colors = await Task.detached(priority: .utility) {
            ImagePalette.prominentColors(in: cgImage, count: 2)
        }.value
        guard !Task.isCancelled else { return }
        withAnimation { palette = colors }
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
        // Keep the screen on while the visualizer is showing, and let it turn off again once it's hidden,
        // for example when the artwork is flipped back or the Now Playing sheet is closed
        UIApplication.shared.isIdleTimerDisabled = newValue
    }
}
