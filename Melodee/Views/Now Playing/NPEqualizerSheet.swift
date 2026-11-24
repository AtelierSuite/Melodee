import SwiftUI

/// Tunes the sound with a graphic equalizer drawn over the live spectrum of the playing audio.
struct NPEqualizerSheet: View {

    static let isEnabledKey = "Equalizer.IsEnabled"

    @Environment(MediaPlayerManager.self) var mediaPlayer
    @Environment(\.dismiss) var dismiss

    @AppStorage(isEnabledKey) private var isEnabled: Bool = false
    @State private var bands: [EQBand] = EQBand.saved
    @State private var contentHeight: CGFloat = 420.0
    @State private var bottomInset: CGFloat = 0.0

    var body: some View {
        NavigationStack {
            TimelineView(.animation(paused: mediaPlayer.isPaused)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let levels = mediaPlayer.spectrumAnalyzer.levels(at: time, isPlaying: !mediaPlayer.isPaused)
                EQEditorView(bands: $bands, spectrum: levels.bands)
                    // Sized by its width alone, so it doesn't shrink with the sheet it sets the height of
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16.0)
            .padding(.top, 8.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            // Includes the navigation bar, which is in the content's top safe area
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height + proxy.safeAreaInsets.top
            } action: { newValue in
                contentHeight = newValue
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.bottom
            } action: { newValue in
                bottomInset = newValue
            }
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(EQPreset.allCases) { preset in
                            Button(preset.localizedName) {
                                withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                                    bands = preset.bands
                                    isEnabled = true
                                }
                            }
                        }
                    } label: {
                        Label("Equalizer.Presets", systemImage: "list.bullet")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $isEnabled.animation()) {
                        Label("Equalizer.On", systemImage: "power")
                    }
                    .tint(.green)
                }
            }
        }
        // Leaves the same margin below the graph as beside it, letting it reach into the home indicator's area
        .presentationDetents([.height(contentHeight + 16.0 - bottomInset)])
        .onChange(of: bands) { _, newValue in
            EQBand.saved = newValue
            if !isEnabled { isEnabled = true }
        }
        .onAppear {
            mediaPlayer.startSpectrumAnalysis()
        }
        .onDisappear {
            mediaPlayer.stopSpectrumAnalysis()
        }
    }
}
