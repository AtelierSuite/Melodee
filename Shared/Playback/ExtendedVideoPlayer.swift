import Foundation
import VLCKit

#if canImport(UIKit)
import UIKit
typealias ExtendedVideoPlatformView = ExtendedVideoView
#else
import AppKit
typealias ExtendedVideoPlatformView = NSView
#endif

/// Plays video files through VLCKit (the Extended video engine), which decodes formats AVPlayer
/// can't and deinterlaces interlaced video.
///
/// A new `VLCMediaPlayer` is created for every file so that late events from the previous file
/// (VLC reports both a file ending and an explicit stop as "stopped") can't be mistaken for the new one.
/// All callbacks are delivered on the main queue.
final class ExtendedVideoPlayer: NSObject {

    /// The view VLC draws video into. It is reused across files so it can stay in the view hierarchy.
    /// The player is created on the main thread along with the rest of the app's playback managers.
    let videoView: ExtendedVideoPlatformView = MainActor.assumeIsolated {
        let view = ExtendedVideoPlatformView()
        #if canImport(UIKit)
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        #else
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        #endif
        return view
    }

    /// An embedded text/subtitle track reported by VLCKit.
    struct TextTrack: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let language: String?
    }

    /// Called when the file plays to the end.
    var onFinished: (() -> Void)?
    /// Called when VLC can't open or decode the file.
    var onFailed: (() -> Void)?
    /// Called with whether playback is now paused, when VLC starts, pauses or resumes.
    var onPausedChanged: ((Bool) -> Void)?
    /// Called with the video's size in pixels once it is known.
    var onVideoSizeChanged: ((CGSize) -> Void)?
    /// Called when VLC discovers, updates, or removes embedded subtitle tracks.
    var onTextTracksChanged: (([TextTrack]) -> Void)?

    /// The VLC instance every player and the parser run on.
    nonisolated(unsafe) private static let library: VLCLibrary = {
        #if canImport(UIKit)
        return VLCLibrary.shared()
        #else
        // VLCKit draws video with OpenGL on the Mac by default, which is deprecated and unavailable
        // in some environments such as virtual machines, so draw it with AVSampleBufferDisplayLayer as on iOS
        return VLCLibrary(options: ["--vout=samplebufferdisplay"])
        #endif
    }()

    /// Reads each file's codecs before playback, to choose between hardware and software decoding.
    private lazy var parser: VLCMediaParser = {
        let parser = VLCMediaParser(library: Self.library, timeout: 3000)
        parser.delegate = self
        return parser
    }()

    private var player: VLCMediaPlayer?
    #if canImport(UIKit)
    /// Lets Picture in Picture control playback, and is told when its state changes.
    private lazy var pictureInPictureMediaController = ExtendedVideoPictureInPictureMediaController(player: self)
    #endif
    /// The file being parsed before playback starts.
    private var pendingMedia: VLCMedia?
    /// Whether playback should start once parsing finishes, which a pause in the meantime turns off.
    private var playsWhenReady = true
    private var hasReportedVideoSize = false
    private var hasStartedPlaying = false
    private var isStopRequested = false
    private var hasEnded = false

    var hasMedia: Bool { player != nil }

    var isPlaying: Bool { player?.isPlaying ?? false }

    var isSeekable: Bool { player?.isSeekable ?? false }

    /// The playback position and the file's length in seconds, once the length is known.
    var playbackTime: (currentTime: TimeInterval, totalTime: TimeInterval)? {
        guard let player else { return nil }
        if hasFinished {
            return knownLength.map { ($0, $0) }
        }
        guard let lengthMs = player.media?.length.value?.doubleValue, lengthMs > 0 else {
            return nil
        }
        knownLength = lengthMs / 1000
        let currentMs = player.time.value?.doubleValue ?? 0
        return (min(max(0, currentMs) / 1000, lengthMs / 1000), lengthMs / 1000)
    }

    /// Whether playback reached the end of the file and stopped.
    private(set) var hasFinished = false
    /// The file's length in seconds, kept once known because VLC resets its clock when playback ends.
    private var knownLength: TimeInterval?

    /// Loads a file and starts playing it, optionally from a time in seconds.
    func play(url: URL, from startTime: TimeInterval?) {
        tearDownPlayer()
        guard let media = VLCMedia(url: url) else {
            onFailed?()
            return
        }
        if let startTime, startTime > 0 {
            media.addOption(":start-time=\(startTime)")
        }
        let player = VLCMediaPlayer(library: Self.library)
        player.delegate = self
        #if canImport(UIKit)
        let view = videoView
        nonisolated(unsafe) let mediaController = pictureInPictureMediaController
        MainActor.assumeIsolated {
            view.pictureInPictureMediaController = mediaController
        }
        #endif
        player.drawable = videoView
        // Deinterlace the streams VLC detects as interlaced, as desktop VLC does
        player.setDeinterlace(.auto, withFilter: "yadif2x")
        self.player = player
        hasReportedVideoSize = false
        hasStartedPlaying = false
        isStopRequested = false
        hasEnded = false
        hasFinished = false
        knownLength = nil
        playsWhenReady = true
        pendingMedia = media
        if parser.queue(media, options: .parse) != 0 {
            start(media, decodesInSoftware: true)
        }
    }

    /// Resumes playback, restarting from the beginning if the file previously played to the end.
    func resume() {
        guard let player else { return }
        if hasFinished, let url = player.media?.url {
            play(url: url, from: nil)
            return
        }
        playsWhenReady = true
        if pendingMedia == nil {
            player.play()
        }
    }

    func pause() {
        playsWhenReady = false
        guard let player, player.canPause else { return }
        player.pause()
    }

    /// The speed files play at, where 1 is normal speed, kept for each file loaded.
    var defaultRate: Float = 1.0 {
        didSet {
            player?.rate = defaultRate
        }
    }

    /// Sets the playback speed for now, where 1 is normal speed, such as while seeking.
    func setRate(_ rate: Float) {
        player?.rate = rate
    }

    func seek(to time: TimeInterval) {
        guard let player, player.isSeekable else { return }
        player.time = VLCTime(number: NSNumber(value: Int64(time * 1000)))
        invalidatePictureInPicturePlaybackState()
    }

    /// Tells Picture in Picture to refresh its play state and progress.
    private func invalidatePictureInPicturePlaybackState() {
        #if canImport(UIKit)
        let view = videoView
        MainActor.assumeIsolated {
            view.pictureInPictureWindowController?.invalidatePlaybackState()
        }
        #endif
    }

    /// Stops playback and unloads the file.
    func stop() {
        tearDownPlayer()
    }

    /// Embedded subtitle tracks currently reported by VLC for the playing video.
    var textTracks: [TextTrack] {
        guard let player else { return [] }
        return player.textTracks.map { track in
            let title = track.trackName.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = track.trackDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = !title.isEmpty ? title : (desc?.isEmpty == false ? desc! : track.trackId)
            return TextTrack(id: track.trackId, name: name, language: track.language)
        }
    }

    /// Selects one of VLC's embedded subtitle tracks by ID, or disables all embedded subtitles when `nil`.
    func selectTextTrack(id: String?) {
        guard let player else { return }
        guard let id else {
            player.deselectAllTextTracks()
            return
        }
        if let track = player.textTracks.first(where: { $0.trackId == id }) {
            player.selectTextTracks([track])
        } else {
            player.deselectAllTextTracks()
        }
    }

    private func tearDownPlayer() {
        #if canImport(UIKit)
        if player != nil {
            let view = videoView
            MainActor.assumeIsolated {
                view.pictureInPictureWindowController?.stopPictureInPicture()
                view.pictureInPictureWindowController = nil
            }
        }
        #endif
        if let pendingMedia {
            parser.cancelParsing(for: pendingMedia)
            self.pendingMedia = nil
        }
        guard let player else { return }
        isStopRequested = true
        player.delegate = nil
        player.stop()
        player.drawable = nil
        self.player = nil
    }

    /// Hands the parsed file to the player and starts it, unless it was paused while parsing.
    private func start(_ media: VLCMedia, decodesInSoftware: Bool) {
        guard let player, media === pendingMedia else { return }
        pendingMedia = nil
        if decodesInSoftware {
            // VLC's deinterlacer can't process frames the hardware decoder keeps on the GPU,
            // so decode in software, as VLC for iOS does when hardware decoding is turned off
            media.addOption(":codec=avcodec,all")
            media.addOption(":avcodec-hw=none")
        }
        player.media = media
        player.rate = defaultRate
        if playsWhenReady {
            player.play()
        }
    }

    /// Whether to decode in software so interlaced video can be deinterlaced. VP9 and AV1 can't be
    /// interlaced and interlaced HEVC is very rare, so those keep hardware decoding, which matters
    /// for the high resolution video they're mostly used for. Everything else (H.264, MPEG-2, VC-1,
    /// DV and so on) is regularly interlaced.
    private static func decodesInSoftware(_ media: VLCMedia) -> Bool {
        let hardwareCodecs: Set<UInt32> = [fourCC("hevc"), fourCC("VP90"), fourCC("av01")]
        guard let videoTrack = media.tracksInformation.first(where: { $0.type == .video }) else {
            return true
        }
        return !hardwareCodecs.contains(videoTrack.codec)
    }

    /// VLC's codec identifiers, which store the first character in the lowest byte.
    private static func fourCC(_ code: String) -> UInt32 {
        code.utf8.reversed().reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func reportVideoSizeIfNeeded(for player: VLCMediaPlayer) {
        guard !hasReportedVideoSize else { return }
        let size = player.videoSize
        guard size.width > 0, size.height > 0 else { return }
        hasReportedVideoSize = true
        onVideoSizeChanged?(size)
    }
}

extension ExtendedVideoPlayer: VLCMediaParserDelegate {

    func mediaFinishedParsing(_ media: VLCMedia, with status: VLCMediaParsedStatus) {
        nonisolated(unsafe) weak let playerRef = self
        nonisolated(unsafe) let parsedMedia = media
        DispatchQueue.main.async {
            guard let self = playerRef else { return }
            // If parsing failed VLC can still try to play the file, so decode in software to be safe
            let decodesInSoftware = status != .done || Self.decodesInSoftware(parsedMedia)
            debugPrint("VLCKit parsed media (status \(status.rawValue)), decoding in \(decodesInSoftware ? "software" : "hardware").")
            self.start(parsedMedia, decodesInSoftware: decodesInSoftware)
        }
    }
}

extension ExtendedVideoPlayer: VLCMediaPlayerDelegate {

    // VLCKit calls the delegate on its own threads, so every event hops to the main queue and
    // is dropped if the player it came from has since been replaced.

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        nonisolated(unsafe) weak let playerRef = self
        DispatchQueue.main.async {
            guard let self = playerRef, let player = self.player, !self.isStopRequested, !self.hasEnded else { return }
            switch newState {
            case .playing:
                self.hasStartedPlaying = true
                self.invalidatePictureInPicturePlaybackState()
                self.onPausedChanged?(false)
                self.reportVideoSizeIfNeeded(for: player)
                self.onTextTracksChanged?(self.textTracks)
            case .paused:
                self.invalidatePictureInPicturePlaybackState()
                self.onPausedChanged?(true)
            case .stopped:
                // An explicit stop tears the player down first, so a stop here means the file ended
                self.hasEnded = true
                if self.hasStartedPlaying {
                    if let lengthMs = player.media?.length.value?.doubleValue, lengthMs > 0 {
                        self.knownLength = lengthMs / 1000
                    }
                    self.hasFinished = true
                    self.onFinished?()
                } else {
                    self.onFailed?()
                }
            case .error:
                self.hasEnded = true
                self.onFailed?()
            default:
                break
            }
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        nonisolated(unsafe) weak let playerRef = self
        DispatchQueue.main.async {
            guard let self = playerRef, let player = self.player, !self.isStopRequested else { return }
            self.reportVideoSizeIfNeeded(for: player)
        }
    }

    func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
        notifyTextTracksIfNeeded(trackType)
    }

    func mediaPlayerTrackRemoved(_ trackId: String, with trackType: VLCMedia.TrackType) {
        notifyTextTracksIfNeeded(trackType)
    }

    func mediaPlayerTrackUpdated(_ trackId: String, with trackType: VLCMedia.TrackType) {
        notifyTextTracksIfNeeded(trackType)
    }

    private func notifyTextTracksIfNeeded(_ trackType: VLCMedia.TrackType) {
        guard trackType == .text else { return }
        nonisolated(unsafe) weak let playerRef = self
        DispatchQueue.main.async {
            guard let self = playerRef, self.player != nil, !self.isStopRequested else { return }
            self.onTextTracksChanged?(self.textTracks)
        }
    }
}

#if canImport(UIKit)
/// The view VLC draws video into on iOS. It has no controls or gestures, and lets VLC move the video
/// into Picture in Picture, which starts automatically when the app is backgrounded during playback.
final class ExtendedVideoView: UIView, @preconcurrency VLCPictureInPictureDrawable {

    /// Handles playback requests from the Picture in Picture window.
    var pictureInPictureMediaController: ExtendedVideoPictureInPictureMediaController?
    /// Controls the Picture in Picture window of the current video, once VLC has set it up.
    var pictureInPictureWindowController: (any VLCPictureInPictureWindowControlling)?

    func mediaController() -> any VLCPictureInPictureMediaControlling {
        pictureInPictureMediaController ?? ExtendedVideoPictureInPictureMediaController(player: nil)
    }

    func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)? {
        return { [weak self] windowController in
            guard let readyWindowController = windowController else { return }
            nonisolated(unsafe) let windowController = readyWindowController
            let update: @Sendable () -> Void = {
                MainActor.assumeIsolated {
                    self?.pictureInPictureWindowController = windowController
                }
            }
            if Thread.isMainThread {
                update()
            } else {
                DispatchQueue.main.async(execute: update)
            }
        }
    }
}

/// Answers the Picture in Picture window's playback requests for the Extended video engine.
/// Times are in milliseconds.
final class ExtendedVideoPictureInPictureMediaController: NSObject, VLCPictureInPictureMediaControlling {

    private weak var player: ExtendedVideoPlayer?

    init(player: ExtendedVideoPlayer?) {
        self.player = player
    }

    func play() {
        player?.resume()
    }

    func pause() {
        player?.pause()
    }

    func seek(by offset: Int64, completion: @escaping () -> Void) {
        if let player, let playbackTime = player.playbackTime {
            let target = playbackTime.currentTime + TimeInterval(offset) / 1000
            player.seek(to: min(max(0, target), playbackTime.totalTime))
        }
        completion()
    }

    func mediaLength() -> Int64 {
        Int64((player?.playbackTime?.totalTime ?? 0) * 1000)
    }

    func mediaTime() -> Int64 {
        Int64((player?.playbackTime?.currentTime ?? 0) * 1000)
    }

    func isMediaSeekable() -> Bool {
        player?.isSeekable ?? false
    }

    func isMediaPlaying() -> Bool {
        player?.isPlaying ?? false
    }
}
#endif
