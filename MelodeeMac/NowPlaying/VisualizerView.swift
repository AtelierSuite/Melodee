//
//  VisualizerView.swift
//  Melodee
//

import AppKit
import SwiftUI

/// What the visualizer window shows, kept up to date with the player by `VisualizerWindowController`.
@Observable
@MainActor
final class VisualizerModel {

    var artwork: NSImage?
    var title: String = ""
    var subtitle: String = ""
    var isPlaying: Bool = false
    /// Videos play outside the audio engine, so there's nothing to analyse while one plays.
    var isPlayingVideo: Bool = false
    /// Whether the window is on screen.
    var isShown: Bool = false
    /// Whether the visualizer is showing instead of the artwork.
    var showsVisualizer: Bool = false
    /// Whether the visualizer is showing every style to choose from.
    var isChoosingStyle: Bool = false

    /// Counts the mouse's movements over the window, which bring the buttons back.
    var mouseMoveCount: Int = 0

    /// Called when the close button is clicked.
    var onClose: () -> Void = { }
}

/// The album art filling the screen, which fades to the visualizer when clicked.
///
/// The close and style buttons show while the mouse moves, and hide along with the cursor once it rests.
struct VisualizerView: View {

    @Bindable var model: VisualizerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(NPVisualizerStyle.storageKey) private var style: NPVisualizerStyle = .bars
    @State private var palette: [Color] = []
    @State private var history = NPVisualizerHistory()
    @State private var isAnalysing: Bool = false
    @State private var showsControls: Bool = true
    @State private var hideControlsTask: Task<Void, Never>?

    private let player = MacServices.shared.player

    private var shouldAnalyse: Bool {
        model.isShown && model.showsVisualizer && !model.isPlayingVideo
    }

    private var artworkImage: Image {
        if let artwork = model.artwork {
            Image(nsImage: artwork)
        } else {
            Image("Album.Generic")
        }
    }

    var body: some View {
        ZStack {
            // Overlaid on the black, so the filled artwork can't make the window's content bigger than the screen
            Color.black
                .overlay {
                    artworkImage
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 60.0)
                        .opacity(model.showsVisualizer ? 0.45 : 0.6)
                }
                .clipped()
            if model.showsVisualizer {
                visualizer
                    .transition(.opacity)
            } else {
                artwork
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            closeButton
        }
        .overlay(alignment: .topTrailing) {
            if model.showsVisualizer {
                switchButton
                    .transition(.opacity)
            }
        }
        .onChange(of: model.mouseMoveCount) {
            revealControls()
        }
        .onChange(of: shouldAnalyse, initial: true) { _, newValue in
            setAnalysing(newValue)
        }
        .onChange(of: model.isShown) { _, isShown in
            if isShown {
                revealControls()
            }
        }
        .onDisappear {
            setAnalysing(false)
        }
        .task(id: model.artwork.map(ObjectIdentifier.init)) {
            await updatePalette()
        }
    }

    // MARK: Artwork

    private var artwork: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width * 0.6, geometry.size.height * 0.6)
            VStack(spacing: 28.0) {
                artworkImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: side, maxHeight: side)
                    .clipShape(RoundedRectangle(cornerRadius: 16.0))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16.0)
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 30.0, y: 12.0)
                    .contentShape(RoundedRectangle(cornerRadius: 16.0))
                    .onTapGesture {
                        setShowsVisualizer(true)
                    }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(String(localized: "NowPlaying.ShowVisualizer"))
                    .accessibilityAction {
                        setShowsVisualizer(true)
                    }
                VStack(spacing: 6.0) {
                    Text(verbatim: model.title)
                        .font(.system(size: 26.0, weight: .bold))
                    if !model.subtitle.isEmpty {
                        Text(verbatim: model.subtitle)
                            .font(.system(size: 18.0))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: side * 1.4)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: Visualizer

    private var visualizer: some View {
        let isPlaying = model.isPlaying
        let colors = barColors
        let style = style
        let history = history
        return TimelineView(.animation(paused: !shouldAnalyse)) { timeline in
            // Analysed once a frame, and shared by every style drawn in the frame
            let time = timeline.date.timeIntervalSinceReferenceDate
            let levels = player.spectrumAnalyzer.levels(at: time, isPlaying: isPlaying)
            let frame = NPVisualizerFrame(bands: levels.bands, time: time, colors: colors, history: history)
            let _ = history.record(levels.bands, at: time)
            if model.isChoosingStyle {
                NPVisualizerPicker(frame: frame, selection: style) { newStyle in
                    choose(newStyle)
                }
                .transition(.opacity.combined(with: .scale(scale: 1.15)))
            } else {
                NPVisualizerCanvas(style: style, frame: frame)
                    .padding(.horizontal, 48.0)
                    .padding(.vertical, 64.0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        setShowsVisualizer(false)
                    }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(String(localized: "NowPlaying.ShowArtwork"))
                    .accessibilityAction {
                        setShowsVisualizer(false)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
    }

    private func setShowsVisualizer(_ showsVisualizer: Bool) {
        withAnimation(.easeInOut(duration: 0.6)) {
            model.showsVisualizer = showsVisualizer
            if !showsVisualizer {
                model.isChoosingStyle = false
            }
        }
    }

    // MARK: Controls

    private var closeButton: some View {
        Button {
            model.onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16.0, weight: .semibold))
                .frame(width: 24.0, height: 24.0)
        }
        .modifier(OverlayButtonStyle(isVisible: showsControls))
        .help(MacText.string("Menu.Close"))
        .accessibilityLabel(MacText.string("Menu.Close"))
    }

    private var switchButton: some View {
        Button {
            withAnimation(switchAnimation) {
                model.isChoosingStyle.toggle()
            }
        } label: {
            Group {
                if model.isChoosingStyle {
                    Image(systemName: "chevron.backward")
                } else {
                    Image(systemName: "arrow.left.arrow.right")
                }
            }
            .font(.system(size: 16.0, weight: .semibold))
            .frame(width: 24.0, height: 24.0)
        }
        .modifier(OverlayButtonStyle(isVisible: showsControls || model.isChoosingStyle))
        .help(switchLabel)
        .accessibilityLabel(switchLabel)
    }

    private var switchLabel: String {
        model.isChoosingStyle ? String(localized: "Shared.Cancel") : String(localized: "NowPlaying.ChooseVisualizer")
    }

    private var switchAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.2)
    }

    private func choose(_ newStyle: NPVisualizerStyle) {
        style = newStyle
        withAnimation(switchAnimation) {
            model.isChoosingStyle = false
        }
    }

    /// Shows the buttons and cursor, and hides them again once the mouse rests for a few seconds.
    private func revealControls() {
        if !showsControls {
            withAnimation(.easeOut(duration: 0.2)) {
                showsControls = true
            }
        }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, model.isShown else { return }
            withAnimation(.easeIn(duration: 0.4)) {
                showsControls = false
            }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    // MARK: Colors

    /// The bottom and top colors of the bars: the artwork's most prominent colors, or the accent color.
    private var barColors: NPVisualizerStyle.Colors {
        switch palette.count {
        case 0: (Color.accentColor, Color.accentColor.mix(with: .white, by: 0.4))
        case 1: (palette[0], palette[0].mix(with: .white, by: 0.4))
        default: (palette[0], palette[1])
        }
    }

    private func updatePalette() async {
        guard let cgImage = model.artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
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
            player.startSpectrumAnalysis()
        } else {
            player.stopSpectrumAnalysis()
        }
    }
}

/// A round glass button floating over the artwork, which fades out while the mouse rests.
private struct OverlayButtonStyle: ViewModifier {

    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .buttonStyle(.glass(.clear))
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .foregroundStyle(.white)
            .padding(20.0)
            .opacity(isVisible ? 1.0 : 0.0)
            .allowsHitTesting(isVisible)
    }
}
