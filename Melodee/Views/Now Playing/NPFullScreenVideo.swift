import Combine
import SwiftUI
import UIKit

/// The playing video filling the screen. It grows out of the video in the Now Playing sheet, and shrinks back
/// into it when closed, either with the close button or by swiping down.
///
/// The video view itself is moved here rather than shown again, so playback carries on without a pause.
/// It is laid out at its full screen size throughout, and only scaled and moved to animate between the two,
/// so the video isn't laid out again on every frame.
struct NPFullScreenVideo: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// Where the video sits in the Now Playing sheet, on screen.
    var sourceFrame: NPScreenFrameReference
    /// Called once the video has shrunk back into the Now Playing sheet, to hand it back.
    var onClose: () -> Void

    /// Where this view is on screen, to place the video in the Now Playing sheet relative to it.
    @State private var screenFrame = NPScreenFrameReference()
    /// The video in the Now Playing sheet's frame in this view, read when growing out of it and shrinking back.
    @State private var sourceRect: CGRect?
    @State private var isExpanded: Bool = false
    /// Set once the video is handed back, so this view doesn't take it again while it's being dismissed.
    @State private var hasHandedBack: Bool = false
    @State private var isClosing: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    init(sourceFrame: NPScreenFrameReference, onClose: @escaping () -> Void) {
        self.sourceFrame = sourceFrame
        self.onClose = onClose
        // Known before the first frame, so the video starts exactly over the one in the sheet
        _sourceRect = State(initialValue: sourceFrame.frame)
    }

    private static let sourceCornerRadius: CGFloat = 16.0
    /// How far the video must be swiped down to close it when let go.
    private static let closeDistance: CGFloat = 120.0

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let videoRect = fittedVideoRect(in: geometry.size)
                let source = sourceRect ?? .zero
                let dragProgress = min(max(dragOffset.height, 0.0) / max(geometry.size.height, 1.0), 1.0)
                let placement = placement(of: videoRect, from: source, dragProgress: dragProgress)
                ZStack {
                    Color.black
                        .opacity(isExpanded ? max(1.0 - dragProgress * 2.0, 0.0) : 0.0)
                    surface
                        .frame(width: videoRect.width, height: videoRect.height)
                        .clipShape(RoundedRectangle(cornerRadius: placement.cornerRadius))
                        .scaleEffect(placement.scale)
                        .offset(placement.offset)
                        .position(x: videoRect.midX, y: videoRect.midY)
                }
                .background(NPScreenFrameReader(reference: screenFrame))
            }
            .ignoresSafeArea()
            NPVideoControlsOverlay(isEnabled: isExpanded && !isDragging && !isClosing,
                                   dimming: 0.4) { controls in
                ZStack {
                    // In the middle of the screen, as in the system's video player
                    NPFullScreenVideoTransportControls(controls: controls)
                    VStack(spacing: 0.0) {
                        HStack(alignment: .top) {
                            NPVideoOverlayButton(systemImage: "xmark",
                                                 accessibilityLabel: String(localized: "NowPlaying.ExitFullScreen"),
                                                 size: .navigationBar) {
                                close()
                            }
                            Spacer(minLength: 0.0)
                            if mediaPlayer.supportsVideoPictureInPicture {
                                NPVideoOverlayButton(systemImage: "pip.enter",
                                                     accessibilityLabel: String(localized: "NowPlaying.PictureInPicture"),
                                                     size: .navigationBar) {
                                    mediaPlayer.startVideoPictureInPicture()
                                    close()
                                }
                            }
                        }
                        Spacer(minLength: 0.0)
                        NPFullScreenVideoSeekBar(controls: controls)
                            .frame(maxWidth: 520.0)
                            .padding(.horizontal, 12.0)
                            .padding(.bottom, 4.0)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(swipeToClose)
        .environment(\.colorScheme, .dark)
        .statusBarHidden(isExpanded && !isClosing)
        .persistentSystemOverlays(.hidden)
        .presentationBackground(.clear)
        .accessibilityAction(.escape) {
            close()
        }
        .onDisappear {
            // Taken away without closing, such as when the Now Playing sheet goes away, so hand the video back
            if !hasHandedBack {
                hasHandedBack = true
                mediaPlayer.isVideoFullScreen = false
            }
        }
        .onAppear {
            sourceRect = currentSourceRect()
            withAnimation(transitionAnimation) {
                isExpanded = true
            }
        }
        .onChange(of: mediaPlayer.isCurrentlyPlayingVideo()) { _, isPlayingVideo in
            if !isPlayingVideo {
                close()
            }
        }
    }

    @ViewBuilder
    private var surface: some View {
        // Only while full screen, so this doesn't take the video back from Now Playing as it's dismissed
        if mediaPlayer.activeVideoEngine == .extended {
            NPExtendedVideoSurface(isActive: !hasHandedBack && mediaPlayer.isVideoFullScreen)
        } else {
            NPVideoSurface(isActive: !hasHandedBack && mediaPlayer.isVideoFullScreen)
        }
    }

    // MARK: Layout

    private struct Placement {
        var scale: CGFloat
        var offset: CGSize
        var cornerRadius: CGFloat
    }

    /// The video's full screen frame: as large as fits, in the middle of the screen.
    private func fittedVideoRect(in size: CGSize) -> CGRect {
        let aspectRatio = mediaPlayer.videoAspectRatio ?? 1.0
        guard size.width > 0, size.height > 0, aspectRatio > 0 else { return .zero }
        let fittedSize = if size.width / size.height > aspectRatio {
            CGSize(width: size.height * aspectRatio, height: size.height)
        } else {
            CGSize(width: size.width, height: size.width / aspectRatio)
        }
        return CGRect(x: (size.width - fittedSize.width) / 2, y: (size.height - fittedSize.height) / 2,
                      width: fittedSize.width, height: fittedSize.height)
    }

    /// How to scale and move the full screen video so it sits where it should be right now.
    private func placement(of videoRect: CGRect, from source: CGRect, dragProgress: CGFloat) -> Placement {
        guard videoRect.width > 0 else {
            return Placement(scale: 1.0, offset: .zero, cornerRadius: 0.0)
        }
        if isExpanded {
            // Shrinks and rounds off as it's swiped down, following the finger
            let scale = 1.0 - dragProgress * 0.5
            return Placement(scale: scale,
                             offset: dragOffset,
                             cornerRadius: min(dragProgress * 4.0, 1.0) * Self.sourceCornerRadius / scale)
        }
        guard source.width > 0 else {
            // The video's place in the sheet isn't known, so grow from the middle instead
            return Placement(scale: 0.5, offset: .zero, cornerRadius: Self.sourceCornerRadius * 2.0)
        }
        // Over the video in the Now Playing sheet, which has the same aspect ratio
        let scale = source.width / videoRect.width
        return Placement(scale: scale,
                         offset: CGSize(width: source.midX - videoRect.midX, height: source.midY - videoRect.midY),
                         cornerRadius: Self.sourceCornerRadius / scale)
    }

    // MARK: Closing

    private var swipeToClose: some Gesture {
        DragGesture(minimumDistance: 12.0)
            .onChanged { value in
                guard isExpanded, !isClosing else { return }
                isDragging = true
                dragOffset = value.translation
            }
            .onEnded { value in
                guard isDragging else { return }
                isDragging = false
                if value.translation.height > Self.closeDistance ||
                    value.predictedEndTranslation.height > Self.closeDistance * 3.0 {
                    close()
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    /// The video in the Now Playing sheet's frame, converted from the screen into this view.
    private func currentSourceRect() -> CGRect? {
        guard let source = sourceFrame.frame else { return nil }
        // This view fills the screen, so it starts at the screen's corner until it's on screen to measure
        let origin = screenFrame.frame?.origin ?? .zero
        return source.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private var transitionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.4)
    }

    /// Shrinks the video back into the Now Playing sheet, then hands it back.
    private func close() {
        guard !isClosing else { return }
        isClosing = true
        isDragging = false
        // The sheet may have moved, such as after rotating, so shrink back to where the video is now
        sourceRect = currentSourceRect()
        withAnimation(transitionAnimation) {
            isExpanded = false
            dragOffset = .zero
        } completion: {
            hasHandedBack = true
            onClose()
        }
    }
}

/// The previous, play or pause, and next buttons in the middle of the full screen video, each in a glass circle.
struct NPFullScreenVideoTransportControls: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    let controls: NPVideoControlsContext

    var body: some View {
        HStack(alignment: .center, spacing: 32.0) {
            // Holding these rewinds and fast forwards, as in the Now Playing sheet
            NPTransportButton(imageName: "Back", scrubDirection: .backward,
                              padding: 16.0, onHoldChanged: controls.setHeld) {
                guard mediaPlayer.canGoToPreviousTrack() else { return }
                controls.keepShowing()
                mediaPlayer.backToPreviousTrack()
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .disabled(!(mediaPlayer.isPlaybackActive &&
                        (mediaPlayer.canGoToPreviousTrack() || mediaPlayer.supportsSeeking())))
            Button {
                controls.keepShowing()
                if mediaPlayer.isPaused {
                    mediaPlayer.play()
                } else {
                    mediaPlayer.pause()
                }
            } label: {
                Image(mediaPlayer.isPaused ? "Play" : "Pause")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32.0, height: 32.0)
                    .padding(20.0)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.clear.interactive(), in: .circle)
            NPTransportButton(imageName: "Next", scrubDirection: .forward,
                              padding: 16.0, onHoldChanged: controls.setHeld) {
                guard mediaPlayer.canGoToNextTrack() else { return }
                controls.keepShowing()
                mediaPlayer.skipToNextTrack()
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .disabled(!(mediaPlayer.isPlaybackActive &&
                        (mediaPlayer.canGoToNextTrack() || mediaPlayer.supportsSeeking())))
        }
        .foregroundStyle(.white)
        .disabled(!mediaPlayer.canStartPlayback())
    }
}

/// The seek bar at the bottom of the full screen video.
struct NPFullScreenVideoSeekBar: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    let controls: NPVideoControlsContext

    @State private var currentDuration: TimeInterval = .zero
    @State private var totalDuration: TimeInterval = .zero
    @State private var isSeekbarSeeking: Bool = false

    private let updateTimer = Timer.publish(every: 0.25, on: .current, in: .common).autoconnect()

    var body: some View {
        // The times sit either side of the bar in one row, as in the system's video player
        HStack(alignment: .center, spacing: 12.0) {
            Text(verbatim: currentDuration.asTimeString(style: .positional))
            track
            Text(verbatim: "-" + max(totalDuration - currentDuration, 0.0).asTimeString(style: .positional))
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 20.0)
        .padding(.vertical, 14.0)
        .glassEffect(.regular, in: .capsule)
        // Taps around the seek bar keep the controls up instead of falling through to the video and hiding them
        .contentShape(.capsule)
        .onTapGesture {
            controls.keepShowing()
        }
        .onAppear(perform: updateTimes)
        .onReceive(updateTimer) { _ in
            updateTimes()
        }
    }

    /// The bar itself, which jumps to wherever it's touched and follows the finger, seeking once let go.
    private var track: some View {
        GeometryReader { geometry in
            let progress = totalDuration > 0 ? min(max(currentDuration / totalDuration, 0.0), 1.0) : 0.0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.3))
                Capsule()
                    .fill(.white)
                    .frame(width: geometry.size.width * progress)
            }
            .frame(height: isSeekbarSeeking ? 10.0 : 6.0)
            .frame(maxHeight: .infinity)
            .animation(.smooth(duration: 0.2), value: isSeekbarSeeking)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0.0)
                    .onChanged { value in
                        guard totalDuration > 0, geometry.size.width > 0 else { return }
                        if !isSeekbarSeeking {
                            isSeekbarSeeking = true
                            controls.setHeld(true)
                        }
                        let newProgress = min(max(value.location.x / geometry.size.width, 0.0), 1.0)
                        currentDuration = totalDuration * newProgress
                    }
                    .onEnded { _ in
                        guard isSeekbarSeeking else { return }
                        mediaPlayer.seekTo(currentDuration)
                        isSeekbarSeeking = false
                        controls.setHeld(false)
                    }
            )
        }
        .frame(height: 20.0)
    }

    private func updateTimes() {
        guard !isSeekbarSeeking else { return }
        if mediaPlayer.isPlaybackActive, let time = mediaPlayer.playbackTime() {
            currentDuration = time.currentTime
            totalDuration = time.totalTime
        } else {
            currentDuration = .zero
            totalDuration = .zero
        }
    }
}

/// Holds on to a view so its frame on screen can be read when needed, such as at the start of an animation.
/// It measures with UIKit, which, unlike SwiftUI's global coordinates, is the same across presentations.
final class NPScreenFrameReference {

    fileprivate weak var view: UIView?

    /// The view's frame in screen coordinates, or nil while it isn't on screen.
    @MainActor
    var frame: CGRect? {
        guard let view, let window = view.window else { return nil }
        return view.convert(view.bounds, to: window.screen.coordinateSpace)
    }
}

/// An invisible view that lets an `NPScreenFrameReference` measure where it is on screen.
struct NPScreenFrameReader: UIViewRepresentable {

    let reference: NPScreenFrameReference

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        reference.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        reference.view = uiView
    }
}
