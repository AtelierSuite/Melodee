import AVFoundation
import SwiftUI
import UIKit

/// Shows the video AVPlayer is playing when the standard video engine is playing.
/// The video view has no controls of its own, so the Now Playing controls below it handle playback.
struct NPVideoSurface: UIViewRepresentable {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    /// Whether this surface shows the video. The video view can only be in one place at a time,
    /// so the inline surface lets go of it while the video is shown full screen.
    var isActive: Bool = true

    func makeUIView(context: Context) -> NPVideoSurfaceContainer {
        NPVideoSurfaceContainer(videoView: mediaPlayer.videoPlayerView, isActive: isActive)
    }

    func updateUIView(_ container: NPVideoSurfaceContainer, context: Context) {
        container.isActive = isActive
    }

    static func dismantleUIView(_ container: NPVideoSurfaceContainer, coordinator: ()) {
        container.release()
    }
}

/// Holds the shared video view for a video surface. The video view can only be in one place at a time, so
/// whichever surface is active takes it, and a surface that goes away while holding it hands it to another
/// surface that is still active, such as when the Now Playing sheet is dismissed beside the Now Playing column.
final class NPVideoSurfaceContainer: UIView {

    private static let releasedNotification = Notification.Name("NPVideoSurfaceContainer.Released")

    private let videoView: UIView

    var isActive: Bool {
        didSet { takeVideoIfActive() }
    }

    init(videoView: UIView, isActive: Bool) {
        self.videoView = videoView
        self.isActive = isActive
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        // Removed automatically when this view is deallocated
        NotificationCenter.default.addObserver(self, selector: #selector(videoReleased),
                                               name: Self.releasedNotification, object: videoView)
        takeVideoIfActive()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lets go of the video view as this surface goes away, so another surface can take it.
    func release() {
        isActive = false
        NotificationCenter.default.removeObserver(self, name: Self.releasedNotification, object: videoView)
        if videoView.superview === self {
            videoView.removeFromSuperview()
            NotificationCenter.default.post(name: Self.releasedNotification, object: videoView)
        }
    }

    @objc private func videoReleased() {
        takeVideoIfActive()
    }

    private func takeVideoIfActive() {
        guard isActive, videoView.superview !== self else { return }
        videoView.removeFromSuperview()
        videoView.frame = bounds
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(videoView)
    }
}

/// A view that draws an AVPlayer's video, with no controls or gestures.
final class VideoPlayerView: UIView {

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        isUserInteractionEnabled = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
