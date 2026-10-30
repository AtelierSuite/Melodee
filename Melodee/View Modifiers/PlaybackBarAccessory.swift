import SwiftUI
import TipKit

enum PlaybackBar {
    static let contentInset: CGFloat = 80.0
}

extension EnvironmentValues {
    // False when Now Playing is shown in its own column instead of the floating bar.
    @Entry var isPlaybackBarVisible: Bool = true
}

struct PlaybackBarAccessory: ViewModifier {

    @Environment(NowPlayingBarManager.self) var nowPlayingBarManager: NowPlayingBarManager

    var isEnabled: Bool = true

    @State var isPopupPresented: Bool = false
    @Namespace var namespace

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isEnabled && !nowPlayingBarManager.isKeyboardShowing {
                    Button {
                        isPopupPresented.toggle()
                    } label: {
                        NowPlayingBar()
                            .matchedTransitionSource(id: "NowPlayingBar", in: namespace)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .popoverTip(NPQueueTip(), arrowEdge: .bottom)
                    .padding(.horizontal, 12.0)
                    .padding(.bottom, 8.0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: nowPlayingBarManager.isKeyboardShowing)
            .environment(\.isPlaybackBarVisible, isEnabled)
            .onChange(of: isEnabled) { _, isEnabled in
                // Now Playing moved into its own column, so the sheet is no longer needed.
                if !isEnabled {
                    isPopupPresented = false
                }
            }
            .sheet(isPresented: $isPopupPresented) {
                NowPlayingView()
                    .presentationSizing(NowPlayingSheetSizing())
                    .navigationTransition(
                        .zoom(sourceID: "NowPlayingBar", in: namespace)
                    )
            }
    }
}

// A form sheet with extra height, so more of Now Playing fits without scrolling on iPad.
// iPhone presents sheets at full height and is unaffected.
struct NowPlayingSheetSizing: PresentationSizing {

    static let heightMultiplier: CGFloat = 1.4

    func proposedSize(
        for root: PresentationSizingRoot,
        context: PresentationSizingContext
    ) -> ProposedViewSize {
        var size = FormPresentationSizing.form.proposedSize(for: root, context: context)
        if let height = size.height {
            size.height = height * Self.heightMultiplier
        }
        return size
    }
}

struct PlaybackBarContentInset: ViewModifier {

    @Environment(\.isPlaybackBarVisible) var isPlaybackBarVisible

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0.0) {
                Color.clear.frame(height: isPlaybackBarVisible ? PlaybackBar.contentInset : 0.0)
            }
    }
}

extension View {
    func playbackBarAccessory(isEnabled: Bool = true) -> some View {
        self.modifier(PlaybackBarAccessory(isEnabled: isEnabled))
    }

    func playbackBarContentInset() -> some View {
        self.modifier(PlaybackBarContentInset())
    }
}
