import AVFoundation
import SwiftUI

/// Cross-platform video surface used inside the subtitle & lyrics editor,
/// supporting both AVPlayer and VLCKit (`ExtendedVideoPlayer`) with a live cue preview overlay.
struct SubtitleEditorVideoPreview: View {

    var model: SubtitleEditorModel
    var isCompact: Bool = false

    var body: some View {
        ZStack {
            Color.black
            if model.usesExtendedEngine {
                EditorExtendedVideoLayer(videoView: model.extendedPlayer.videoView)
            } else {
                EditorAVPlayerLayer(player: model.avPlayer)
            }
            SubtitleOverlayView(
                text: model.activePreviewText,
                isLyrics: model.document.isLyrics,
                isCompact: isCompact,
                bottomPadding: isCompact ? 10.0 : 18.0
            )
        }
        .aspectRatio(model.videoAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12.0, style: .continuous))
    }
}

#if canImport(UIKit)
import UIKit

private struct EditorAVPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> VideoPlayerHostView {
        VideoPlayerHostView(player: player)
    }

    func updateUIView(_ uiView: VideoPlayerHostView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class VideoPlayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct EditorExtendedVideoLayer: UIViewRepresentable {
    let videoView: UIView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        videoView.removeFromSuperview()
        videoView.frame = container.bounds
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(videoView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if videoView.superview !== uiView {
            videoView.removeFromSuperview()
            videoView.frame = uiView.bounds
            videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            uiView.addSubview(videoView)
        }
    }
}

#else
import AppKit

private struct EditorAVPlayerLayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> EditorMacPlayerView {
        EditorMacPlayerView(player: player)
    }

    func updateNSView(_ nsView: EditorMacPlayerView, context: Context) {
        nsView.setPlayer(player)
    }
}

private final class EditorMacPlayerView: NSView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPlayer(_ player: AVPlayer) {
        if playerLayer.player !== player {
            playerLayer.player = player
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

private struct EditorExtendedVideoLayer: NSViewRepresentable {
    let videoView: NSView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        videoView.removeFromSuperview()
        videoView.frame = container.bounds
        videoView.autoresizingMask = [.width, .height]
        container.addSubview(videoView)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if videoView.superview !== nsView {
            videoView.removeFromSuperview()
            videoView.frame = nsView.bounds
            videoView.autoresizingMask = [.width, .height]
            nsView.addSubview(videoView)
        }
    }
}
#endif
