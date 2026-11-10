import SwiftUI
import UIKit

/// Shows the video VLCKit is drawing when the Extended video engine is playing.
/// The Now Playing controls below it handle playback, as VLCKit has no built-in controls.
struct NPExtendedVideoSurface: UIViewRepresentable {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    /// Whether this surface shows the video. The video view can only be in one place at a time,
    /// so the inline surface lets go of it while the video is shown full screen.
    var isActive: Bool = true

    func makeUIView(context: Context) -> NPVideoSurfaceContainer {
        NPVideoSurfaceContainer(videoView: mediaPlayer.extendedVideoPlayer.videoView, isActive: isActive)
    }

    func updateUIView(_ container: NPVideoSurfaceContainer, context: Context) {
        container.isActive = isActive
    }

    static func dismantleUIView(_ container: NPVideoSurfaceContainer, coordinator: ()) {
        container.release()
    }
}
