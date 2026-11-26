@preconcurrency import AVFoundation
import AVKit
import CoreImage
import SwiftUI
import UIKit

/// Shows the visualizer for the playing audio in Picture in Picture, with the system's playback controls.
///
/// Picture in Picture only plays video, so the selected style is drawn into frames that are fed to a sample
/// buffer display layer. The layer sits behind the app's content, as it only has to be in a window to start.
@MainActor
@Observable
final class VisualizerPictureInPicture: NSObject {

    private(set) var isActive: Bool = false

    @ObservationIgnored private weak var mediaPlayer: MediaPlayerManager?
    @ObservationIgnored private let displayView = SampleBufferDisplayView()
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var timebase: CMTimebase?
    @ObservationIgnored private var renderTimer: Timer?
    @ObservationIgnored private var pixelBufferPool: CVPixelBufferPool?
    @ObservationIgnored private var formatDescription: CMVideoFormatDescription?
    @ObservationIgnored private let history = NPVisualizerHistory()
    @ObservationIgnored private var isAnalysing: Bool = false
    @ObservationIgnored private var wantsToStart: Bool = false
    @ObservationIgnored private var frameCount: Int = 0
    @ObservationIgnored private var artworkKey: String?
    @ObservationIgnored private var background: Image?
    @ObservationIgnored private var colors: NPVisualizerStyle.Colors = VisualizerPictureInPicture.accentColors
    /// Where the visualizer is on screen, in window coordinates, so Picture in Picture grows out of its middle.
    @ObservationIgnored var sourceFrame: CGRect = .zero {
        didSet { positionDisplayView() }
    }

    private static let pointSize = CGSize(width: 384.0, height: 216.0)
    private static let sourceSize = CGSize(width: 16.0, height: 9.0)
    private static let scale: CGFloat = 2.0
    private static let playingFrameInterval: TimeInterval = 1.0 / 30.0
    /// Frames are still drawn while paused so the bars settle, but far less often.
    private static let pausedFrameInterval: TimeInterval = 1.0 / 6.0
    private static let accentColors: NPVisualizerStyle.Colors =
        (Color.accentColor, Color.accentColor.mix(with: .white, by: 0.4))

    static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func attach(to mediaPlayer: MediaPlayerManager) {
        self.mediaPlayer = mediaPlayer
    }

    // MARK: Starting and Stopping

    func start() {
        guard Self.isSupported, let mediaPlayer, !mediaPlayer.isCurrentlyPlayingVideo() else { return }
        if controller == nil {
            setUpController()
        }
        guard let controller, installDisplayView() else { return }
        beginRendering()
        wantsToStart = true
        startWhenReady(controller)
    }

    /// A new controller and layer take a moment to get ready, and starting before then fails silently.
    private func startWhenReady(_ controller: AVPictureInPictureController) {
        Task {
            for _ in 0..<20 {
                guard wantsToStart, !isActive else { return }
                if controller.isPictureInPicturePossible {
                    controller.startPictureInPicture()
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
            wantsToStart = false
            if !isActive {
                endRendering()
            }
        }
    }

    func stop() {
        wantsToStart = false
        controller?.stopPictureInPicture()
    }

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    private func setUpController() {
        let layer = displayView.sampleBufferDisplayLayer
        layer.videoGravity = .resizeAspect
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(),
                                        timebaseOut: &timebase)
        if let timebase {
            layer.controlTimebase = timebase
            self.timebase = timebase
        }
        let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer,
                                                                       playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.requiresLinearPlayback = false
        self.controller = controller
    }

    /// Puts the display layer's view in the foreground window, behind everything else.
    private func installDisplayView() -> Bool {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window else { return displayView.window != nil }
        if displayView.superview !== window {
            displayView.removeFromSuperview()
            displayView.isUserInteractionEnabled = false
            window.insertSubview(displayView, at: 0)
        }
        positionDisplayView()
        return true
    }

    private func positionDisplayView() {
        guard displayView.superview != nil else { return }
        let size = Self.sourceSize
        let center = sourceFrame.isEmpty ? CGPoint(x: size.width / 2, y: size.height / 2) :
            CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        displayView.frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                   width: size.width, height: size.height)
    }

    // MARK: Playback State

    /// Updates the controls and progress shown in the Picture in Picture window.
    func playbackStateDidChange() {
        guard controller != nil, let mediaPlayer else { return }
        if isActive, mediaPlayer.isCurrentlyPlayingVideo() {
            stop()
            return
        }
        syncTimebase()
        controller?.invalidatePlaybackState()
    }

    private func syncTimebase() {
        guard let timebase, let mediaPlayer else { return }
        let time = mediaPlayer.playbackTime()?.currentTime ?? 0
        let rate = mediaPlayer.isPaused ? 0.0 : mediaPlayer.playbackSpeed
        CMTimebaseSetRateAndAnchorTime(timebase, rate: rate,
                                       anchorTime: CMTime(seconds: time, preferredTimescale: 600),
                                       immediateSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))
    }

    // MARK: Rendering

    private func beginRendering() {
        if !isAnalysing {
            isAnalysing = true
            mediaPlayer?.startSpectrumAnalysis()
        }
        syncTimebase()
        scheduleRenderTimer()
        renderFrame()
    }

    private func endRendering() {
        renderTimer?.invalidate()
        renderTimer = nil
        if isAnalysing {
            isAnalysing = false
            mediaPlayer?.stopSpectrumAnalysis()
        }
        displayView.sampleBufferDisplayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true)
        displayView.removeFromSuperview()
    }

    private func scheduleRenderTimer() {
        let interval = (mediaPlayer?.isPaused ?? true) ? Self.pausedFrameInterval : Self.playingFrameInterval
        if let renderTimer, renderTimer.timeInterval == interval { return }
        renderTimer?.invalidate()
        // A timer keeps firing in the background, where display links stop
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renderFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    private func renderFrame() {
        guard let mediaPlayer else { return }
        scheduleRenderTimer()
        updateArtworkIfNeeded()
        let time = ProcessInfo.processInfo.systemUptime
        let levels = mediaPlayer.spectrumAnalyzer.levels(at: time, isPlaying: !mediaPlayer.isPaused)
        history.record(levels.bands, at: time)
        let style = NPVisualizerStyle(
            rawValue: UserDefaults.standard.string(forKey: NPVisualizerStyle.storageKey) ?? ""
        ) ?? .bars
        let frame = NPVisualizerFrame(bands: levels.bands, time: time, colors: colors, history: history)
        let content = VisualizerPictureInPictureFrame(style: style, frame: frame, background: background)
            .frame(width: Self.pointSize.width, height: Self.pointSize.height)
        guard let pixelBuffer = draw(content), let sampleBuffer = makeSampleBuffer(from: pixelBuffer) else { return }
        let layer = displayView.sampleBufferDisplayLayer
        if layer.sampleBufferRenderer.status == .failed {
            layer.sampleBufferRenderer.flush()
        }
        layer.sampleBufferRenderer.enqueue(sampleBuffer)
    }

    private func draw(_ content: some View) -> CVPixelBuffer? {
        let pixelWidth = Int(Self.pointSize.width * Self.scale)
        let pixelHeight = Int(Self.pointSize.height * Self.scale)
        if pixelBufferPool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: pixelWidth,
                kCVPixelBufferHeightKey as String: pixelHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pixelBufferPool)
        }
        guard let pixelBufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // ImageRenderer flips to Core Graphics' bottom-up coordinates itself
        context.scaleBy(x: Self.scale, y: Self.scale)
        let renderer = ImageRenderer(content: content)
        renderer.render { _, render in
            render(context)
        }
        return pixelBuffer
    }

    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        if formatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                         formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return nil }
        frameCount += 1
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMTime(value: CMTimeValue(frameCount), timescale: 30),
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                 formatDescription: formatDescription, sampleTiming: &timing,
                                                 sampleBufferOut: &sampleBuffer)
        guard let sampleBuffer else { return nil }
        // The frames are drawn live, so show each one as soon as it arrives instead of following the timebase
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sampleBuffer
    }

    /// Prepares the blurred artwork behind the visualizer and the visualizer's colors when the track changes.
    private func updateArtworkIfNeeded() {
        guard let mediaPlayer else { return }
        let key = "\(mediaPlayer.currentlyPlayingID)|\(mediaPlayer.metadataRefreshTrigger)"
        guard key != artworkKey else { return }
        artworkKey = key
        let artwork = mediaPlayer.albumArt()
        background = Self.blurredBackground(from: artwork).map { Image(uiImage: $0) }
        if let cgImage = mediaPlayer.embeddedAlbumArt()?.cgImage {
            let palette = ImagePalette.prominentColors(in: cgImage, count: 2)
            switch palette.count {
            case 0: colors = Self.accentColors
            case 1: colors = (palette[0], palette[0].mix(with: .white, by: 0.4))
            default: colors = (palette[0], palette[1])
            }
        } else {
            colors = Self.accentColors
        }
    }

    /// Blurred once per track, as blurring every frame would cost too much.
    private static func blurredBackground(from image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let shortest = min(input.extent.width, input.extent.height)
        let side = shortest > 0 ? Self.pointSize.width / shortest : 1.0
        let scaled = input.transformed(by: CGAffineTransform(scaleX: side, y: side))
        let blurred = scaled.clampedToExtent().applyingGaussianBlur(sigma: 16.0).cropped(to: scaled.extent)
        guard let cgImage = CIContext().createCGImage(blurred, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Picture in Picture Delegates

extension VisualizerPictureInPicture: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.wantsToStart = false
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isActive = false
            self.endRendering()
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        debugPrint("Could not start Picture in Picture for the visualizer: \(error.localizedDescription)")
        Task { @MainActor in
            self.isActive = false
            self.endRendering()
        }
    }
}

extension VisualizerPictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        Task { @MainActor in
            guard let mediaPlayer = self.mediaPlayer else { return }
            if playing {
                if mediaPlayer.canStartPlayback() { mediaPlayer.play() }
            } else {
                mediaPlayer.pause()
            }
            self.playbackStateDidChange()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        MainActor.assumeIsolated {
            guard let totalTime = mediaPlayer?.playbackTime()?.totalTime, totalTime > 0 else {
                return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
            }
            return CMTimeRange(start: .zero, duration: CMTime(seconds: totalTime, preferredTimescale: 600))
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        MainActor.assumeIsolated {
            mediaPlayer?.isPaused ?? true
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) { }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping @Sendable () -> Void
    ) {
        Task { @MainActor in
            self.mediaPlayer?.skip(by: skipInterval.seconds)
            self.playbackStateDidChange()
            completionHandler()
        }
    }
}

// MARK: - Views

/// One frame of the Picture in Picture window: the selected style over the blurred artwork, as on the Now Playing card.
private struct VisualizerPictureInPictureFrame: View {

    let style: NPVisualizerStyle
    let frame: NPVisualizerFrame
    let background: Image?

    var body: some View {
        ZStack {
            Color.black
            if let background {
                background
                    .resizable()
                    .scaledToFill()
                    .opacity(0.45)
            }
            NPVisualizerCanvas(style: style, frame: frame)
        }
        .clipped()
    }
}

private final class SampleBufferDisplayView: UIView {

    override class var layerClass: AnyClass {
        AVSampleBufferDisplayLayer.self
    }

    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
        // swiftlint:disable:next force_cast
        layer as! AVSampleBufferDisplayLayer
    }
}
