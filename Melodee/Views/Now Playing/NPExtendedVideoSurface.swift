import SwiftUI
import UIKit

/// Shows the video VLCKit is drawing when the Extended video engine is playing.
/// The Now Playing controls below it handle playback, as VLCKit has no built-in controls.
struct NPExtendedVideoSurface: UIViewRepresentable {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    /// Whether this surface shows the video. The video view can only be in one place at a time,
    /// so the inline surface lets go of it while the video is shown full screen.
    var isActive: Bool = true

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        if isActive {
            attach(mediaPlayer.extendedVideoPlayer.videoView, to: container)
        }
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        // The same video view is shared, so take it back if another surface was shown since
        let videoView = mediaPlayer.extendedVideoPlayer.videoView
        if isActive, videoView.superview !== container {
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
