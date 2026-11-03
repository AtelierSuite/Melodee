import AVFoundation
import SwiftUI
import UIKit

/// Shows the video AVPlayer is playing when the standard video engine is playing.
/// The video view has no controls of its own, so the Now Playing controls below it handle playback.
struct NPVideoSurface: UIViewRepresentable {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        attach(mediaPlayer.videoPlayerView, to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        // The same video view is shared, so take it back if another surface was shown since
        let videoView = mediaPlayer.videoPlayerView
        if videoView.superview !== container {
            attach(videoView, to: container)
        }
    }

    private func attach(_ videoView: UIView, to container: UIView) {
        videoView.removeFromSuperview()
        videoView.frame = container.bounds
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(videoView)
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
