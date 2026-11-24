@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Prelude
import Videoglot

/// Identifies what track is currently open in the subtitle & lyrics editor.
enum SubtitleEditorSource: Identifiable, Hashable, Sendable {
    case newSubtitles
    case newLyrics
    case sidecar(SidecarTimedTextFile)
    case embeddedTrack(EmbeddedSubtitleTrackInfo)
    case embeddedLyrics

    var id: String {
        switch self {
        case .newSubtitles: "new-subtitles"
        case .newLyrics: "new-lyrics"
        case .sidecar(let file): "sidecar:\(file.id)"
        case .embeddedTrack(let track): "embedded:\(track.trackID)"
        case .embeddedLyrics: "embedded-lyrics"
        }
    }

    var displayName: String {
        switch self {
        case .newSubtitles: String(localized: "SubtitleEditor.Source.NewSubtitles")
        case .newLyrics: String(localized: "SubtitleEditor.Source.NewLyrics")
        case .sidecar(let file): file.displayName
        case .embeddedTrack(let track): "\(track.displayName) (\(String(localized: "SubtitleEditor.Source.Embedded")))"
        case .embeddedLyrics: String(localized: "Subtitles.EmbeddedLyrics")
        }
    }
}

/// Where the editor writes the edited track.
enum SubtitleSaveDestination: Hashable, Sendable {
    case sidecar(TimedTextFormat)
    case embedInVideo(replaceExisting: Bool)
    case lyricsTag
}

/// Shared state and video preview controller for the Lyrics & Subtitle Editor on iOS, iPadOS, and macOS.
@Observable
@MainActor
final class SubtitleEditorModel {

    let videoURL: URL
    let videoName: String

    // Discovered sources
    private(set) var sidecarFiles: [SidecarTimedTextFile] = []
    private(set) var embeddedTracks: [EmbeddedSubtitleTrackInfo] = []
    private(set) var hasEmbeddedLyrics: Bool = false
    private(set) var isLoading: Bool = true

    // Active track & cues
    private(set) var activeSource: SubtitleEditorSource = .newSubtitles
    var document: TimedTextDocument = TimedTextDocument() {
        didSet {
            if !isApplyingLoad {
                hasUnsavedChanges = true
            }
        }
    }
    var selectedCueID: UUID?
    var hasUnsavedChanges: Bool = false

    // Save options & state
    var preferredSidecarFormat: TimedTextFormat = .srt
    private(set) var isSaving: Bool = false
    private(set) var saveProgress: Double = 0
    var errorMessage: String?
    var savedNotice: String?

    // Preview player state
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var totalDuration: TimeInterval = 0
    private(set) var videoAspectRatio: CGFloat = 16.0 / 9.0
    private(set) var usesExtendedEngine: Bool = false
    var previewRate: Float = 1.0 {
        didSet {
            applyPreviewRate()
        }
    }

    @ObservationIgnored let avPlayer = AVPlayer()
    @ObservationIgnored let extendedPlayer = ExtendedVideoPlayer()
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var isApplyingLoad = false
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    var canEmbedInVideo: Bool {
        VideoSubtitleSaver.canEmbed(into: videoURL)
    }

    var canSaveLyricsTag: Bool {
        VideoSubtitleSaver.canSaveLyricsTag(to: videoURL)
    }

    var editingEmbeddedTrackID: CMPersistentTrackID? {
        if case .embeddedTrack(let info) = activeSource {
            return info.trackID
        }
        return nil
    }

    var activePreviewText: String? {
        document.activeText(at: currentTime)
    }

    var allSources: [SubtitleEditorSource] {
        var list: [SubtitleEditorSource] = []
        list.append(contentsOf: embeddedTracks.map { .embeddedTrack($0) })
        list.append(contentsOf: sidecarFiles.map { .sidecar($0) })
        if hasEmbeddedLyrics {
            list.append(.embeddedLyrics)
        }
        list.append(.newSubtitles)
        list.append(.newLyrics)
        return list
    }

    var selectedCueIndex: Int? {
        guard let selectedCueID else { return nil }
        return document.cues.firstIndex { $0.id == selectedCueID }
    }

    var canMergeSelectedWithNext: Bool {
        guard let index = selectedCueIndex else { return false }
        return index + 1 < document.cues.count
    }

    init(videoURL: URL) {
        self.videoURL = videoURL
        self.videoName = videoURL.deletingPathExtension().lastPathComponent
        setUpPreviewObservers()
    }

    // MARK: - Lifecycle

    func load(preferring preferredSource: VideoSubtitleSource? = nil) async {
        isLoading = true
        await configurePreviewPlayer()
        await discoverTracks()
        if let preferred = editorSource(matching: preferredSource) {
            await openSource(preferred)
        } else if let firstSidecar = sidecarFiles.first {
            await openSource(.sidecar(firstSidecar))
        } else if let firstEmbedded = embeddedTracks.first {
            await openSource(.embeddedTrack(firstEmbedded))
        } else if hasEmbeddedLyrics {
            await openSource(.embeddedLyrics)
        } else {
            await openSource(.newSubtitles)
        }
        isLoading = false
    }

    private func editorSource(matching source: VideoSubtitleSource?) -> SubtitleEditorSource? {
        switch source {
        case .sidecar(let file):
            sidecarFiles.first { $0.url.standardizedFileURL == file.url.standardizedFileURL }.map { .sidecar($0) }
        case .avMediaOption, .vlcTextTrack:
            embeddedTracks.first.map { .embeddedTrack($0) }
        case .embeddedLyrics:
            hasEmbeddedLyrics ? .embeddedLyrics : nil
        case nil:
            nil
        }
    }

    func tearDown() {
        stopTickTimer()
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        extendedPlayer.stop()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    func discoverTracks() async {
        let url = videoURL
        let foundSidecars = await Task.detached(priority: .userInitiated) {
            SidecarTimedTextFile.discover(for: url)
        }.value
        let foundEmbedded = (try? await Videoglot.embeddedSubtitleTracks(in: url)) ?? []
        let foundLyrics = await Self.readEmbeddedLyricsString(from: url)

        sidecarFiles = foundSidecars
        embeddedTracks = foundEmbedded
        hasEmbeddedLyrics = foundLyrics != nil
    }

    func openSource(_ source: SubtitleEditorSource) async {
        isApplyingLoad = true
        defer { isApplyingLoad = false }

        activeSource = source
        savedNotice = nil

        switch source {
        case .newSubtitles:
            document = TimedTextDocument(cues: [], title: nil, languageCode: nil, isLyrics: false)
            preferredSidecarFormat = .srt
        case .newLyrics:
            document = TimedTextDocument(cues: [], title: videoName, languageCode: nil, isLyrics: true)
            preferredSidecarFormat = .lrc
        case .sidecar(let sidecar):
            do {
                var parsed = try TimedTextCodec.parse(contentsOf: sidecar.url)
                if parsed.languageCode == nil {
                    parsed.languageCode = sidecar.languageCode
                }
                if parsed.title == nil, let label = sidecar.variantLabel {
                    parsed.title = label
                }
                document = parsed
                preferredSidecarFormat = sidecar.format.isWritableSidecar ? sidecar.format : .srt
            } catch {
                errorMessage = error.localizedDescription
                document = TimedTextDocument()
            }
        case .embeddedTrack(let info):
            do {
                document = try await Videoglot.extractEmbeddedSubtitles(from: videoURL, trackID: info.trackID)
                preferredSidecarFormat = .srt
            } catch {
                errorMessage = error.localizedDescription
                document = TimedTextDocument(title: info.title, languageCode: info.effectiveLanguageCode, isLyrics: false)
            }
        case .embeddedLyrics:
            if let raw = await Self.readEmbeddedLyricsString(from: videoURL) {
                let parsed = TimedTextCodec.parseEmbeddedLyrics(raw)
                if parsed.hasTimedCues {
                    document = parsed
                } else if let plain = parsed.unsyncedText {
                    document = TimedTextDocument.fromPlainLyrics(
                        plain,
                        totalDuration: totalDuration,
                        title: videoName
                    )
                } else {
                    document = TimedTextDocument(title: videoName, isLyrics: true)
                }
            } else {
                document = TimedTextDocument(title: videoName, isLyrics: true)
            }
            preferredSidecarFormat = .lrc
        }

        selectedCueID = document.cues.first?.id
        hasUnsavedChanges = false
    }

    // MARK: - Preview Playback

    private func setUpPreviewObservers() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, let item, item === self.avPlayer.currentItem else { return }
                self.isPlaying = false
                self.stopTickTimer()
            }
        }

        extendedPlayer.onPausedChanged = { [weak self] paused in
            MainActor.assumeIsolated {
                guard let self, self.usesExtendedEngine else { return }
                self.isPlaying = !paused
                if paused {
                    self.stopTickTimer()
                } else {
                    self.startTickTimer()
                }
            }
        }
        extendedPlayer.onFinished = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.usesExtendedEngine else { return }
                self.isPlaying = false
                self.stopTickTimer()
            }
        }
        extendedPlayer.onVideoSizeChanged = { [weak self] size in
            MainActor.assumeIsolated {
                guard let self, size.width > 0, size.height > 0 else { return }
                self.videoAspectRatio = size.width / size.height
            }
        }
    }

    private func configurePreviewPlayer() async {
        let ext = videoURL.pathExtension.lowercased()
        let canUseAV = FilesystemManager.videoExtensions.contains(ext)
        if canUseAV {
            let asset = AVURLAsset(url: videoURL)
            if let isPlayable = try? await asset.load(.isPlayable), isPlayable {
                usesExtendedEngine = false
                let duration = (try? await asset.load(.duration)) ?? .zero
                if duration.isNumeric, duration.seconds > 0 {
                    totalDuration = duration.seconds
                }
                if let track = try? await asset.loadTracks(withMediaType: .video).first,
                   let naturalSize = try? await track.load(.naturalSize),
                   let transform = try? await track.load(.preferredTransform) {
                    let transformed = naturalSize.applying(transform)
                    if abs(transformed.width) > 0, abs(transformed.height) > 0 {
                        videoAspectRatio = abs(transformed.width) / abs(transformed.height)
                    }
                }
                let item = AVPlayerItem(asset: asset)
                // Keep embedded subtitles hidden on the preview player so our live overlay renders the edited cues.
                if let legible = try? await asset.loadMediaSelectionGroup(for: .legible) {
                    item.select(nil, in: legible)
                }
                avPlayer.replaceCurrentItem(with: item)
                return
            }
        }

        // Fall back to VLCKit for MKV, AVI, WebM, etc.
        usesExtendedEngine = true
        extendedPlayer.play(url: videoURL, from: nil)
        extendedPlayer.pause()
        extendedPlayer.selectTextTrack(id: nil)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        if usesExtendedEngine {
            extendedPlayer.selectTextTrack(id: nil)
            extendedPlayer.defaultRate = previewRate
            extendedPlayer.resume()
            isPlaying = true
            startTickTimer()
        } else {
            if totalDuration > 0, currentTime >= totalDuration - 0.05 {
                seek(to: 0)
            }
            avPlayer.playImmediately(atRate: previewRate)
            isPlaying = true
            startTickTimer()
        }
    }

    func pause() {
        if usesExtendedEngine {
            extendedPlayer.pause()
        } else {
            avPlayer.pause()
        }
        isPlaying = false
        stopTickTimer()
    }

    func seek(to time: TimeInterval) {
        let upper = totalDuration > 0 ? totalDuration : max(time, 0)
        let clamped = min(max(0, time), upper)
        currentTime = clamped
        if usesExtendedEngine {
            extendedPlayer.seek(to: clamped)
        } else {
            avPlayer.seek(
                to: CMTime(seconds: clamped, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }

    func step(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    private func applyPreviewRate() {
        if usesExtendedEngine {
            extendedPlayer.defaultRate = previewRate
        } else if isPlaying {
            avPlayer.rate = previewRate
        }
    }

    private func startTickTimer() {
        stopTickTimer()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        if usesExtendedEngine {
            if let time = extendedPlayer.playbackTime {
                currentTime = time.currentTime
                if time.totalTime > 0 {
                    totalDuration = time.totalTime
                }
            }
        } else if let item = avPlayer.currentItem {
            let seconds = item.currentTime().seconds
            if seconds.isFinite, seconds >= 0 {
                currentTime = seconds
            }
            let duration = item.duration.seconds
            if duration.isFinite, duration > 0 {
                totalDuration = duration
            }
        }
    }

    // MARK: - Cue Editing

    @discardableResult
    func addCueAtPlayhead(text: String = "") -> TimedTextCue {
        let defaultDuration = totalDuration > 0
            ? min(3.0, max(0.5, totalDuration - currentTime))
            : 3.0
        let cue = document.addCue(at: currentTime, duration: defaultDuration, text: text)
        selectedCueID = cue.id
        return cue
    }

    func deleteCue(id: UUID) {
        let oldIndex = document.cues.firstIndex { $0.id == id }
        document.deleteCues(ids: [id])
        if selectedCueID == id {
            if let oldIndex, !document.cues.isEmpty {
                selectedCueID = document.cues[min(oldIndex, document.cues.count - 1)].id
            } else {
                selectedCueID = nil
            }
        }
    }

    func splitCue(id: UUID) {
        if let secondID = document.splitCue(id: id, at: currentTime) {
            selectedCueID = secondID
        }
    }

    func mergeCueWithNext(id: UUID) {
        _ = document.mergeCueWithNext(id: id)
    }

    /// Marks the selected cue's start time to the current playhead (or creates a new cue if none is selected).
    func markStartAtPlayhead() {
        guard let index = selectedCueIndex else {
            addCueAtPlayhead()
            return
        }
        let duration = max(document.cues[index].duration, 1.5)
        document.cues[index].startTime = currentTime
        if document.cues[index].endTime <= currentTime + 0.1 {
            document.cues[index].endTime = currentTime + duration
        }
        document.sortCues()
    }

    /// Marks the selected cue's end time to the current playhead and optionally advances to the next cue.
    func markEndAtPlayhead(advanceToNext: Bool = false) {
        guard let index = selectedCueIndex else { return }
        let start = document.cues[index].startTime
        document.cues[index].endTime = max(start + 0.1, currentTime)
        if advanceToNext, index + 1 < document.cues.count {
            selectedCueID = document.cues[index + 1].id
        }
    }

    /// One-tap live syncing: closes the current cue at the playhead and starts the next cue at the playhead.
    func markAndAdvanceToNextCue() {
        guard let index = selectedCueIndex else {
            addCueAtPlayhead()
            return
        }
        let current = document.cues[index]
        if currentTime <= current.startTime + 0.05 {
            document.cues[index].startTime = currentTime
            return
        }
        document.cues[index].endTime = currentTime
        if index + 1 < document.cues.count {
            let nextIndex = index + 1
            let nextDuration = max(document.cues[nextIndex].duration, 2.0)
            document.cues[nextIndex].startTime = currentTime
            if document.cues[nextIndex].endTime <= currentTime + 0.1 {
                document.cues[nextIndex].endTime = currentTime + nextDuration
            }
            selectedCueID = document.cues[nextIndex].id
            document.sortCues()
        }
    }

    func nudgeSelectedCue(startDelta: TimeInterval = 0, endDelta: TimeInterval = 0) {
        guard let selectedCueID else { return }
        document.nudgeCue(id: selectedCueID, startDelta: startDelta, endDelta: endDelta)
    }

    func shiftAllTimings(by offset: TimeInterval) {
        document.shiftAll(by: offset)
    }

    func seekToCue(id: UUID) {
        guard let cue = document.cues.first(where: { $0.id == id }) else { return }
        selectedCueID = cue.id
        seek(to: cue.startTime)
    }

    func updateCueText(id: UUID, text: String) {
        guard let index = document.cues.firstIndex(where: { $0.id == id }) else { return }
        document.cues[index].text = text
    }

    func updateCueTimes(id: UUID, start: TimeInterval, end: TimeInterval) {
        guard let index = document.cues.firstIndex(where: { $0.id == id }) else { return }
        document.cues[index].startTime = max(0, start)
        document.cues[index].endTime = max(document.cues[index].startTime + 0.1, end)
        document.sortCues()
    }

    /// Replaces cues by splitting pasted plain lyrics into lines so the user can time them against the video.
    func importPlainLyrics(_ plainText: String) {
        let converted = TimedTextDocument.fromPlainLyrics(
            plainText,
            totalDuration: totalDuration,
            title: document.title,
            languageCode: document.languageCode
        )
        document.cues = converted.cues
        document.isLyrics = true
        selectedCueID = document.cues.first?.id
    }

    // MARK: - Saving

    /// Saves the document to the requested destination and returns whether the video file itself changed on disk.
    func save(to destination: SubtitleSaveDestination) async -> Bool {
        pause()
        isSaving = true
        saveProgress = 0
        savedNotice = nil
        defer { isSaving = false }

        do {
            switch destination {
            case .sidecar(let format):
                let existingURL: URL? = {
                    if case .sidecar(let file) = activeSource, file.format == format {
                        return file.url
                    }
                    return nil
                }()
                let writtenURL = try VideoSubtitleSaver.saveSidecar(
                    document,
                    for: videoURL,
                    format: format,
                    destinationURL: existingURL
                )
                hasUnsavedChanges = false
                savedNotice = writtenURL.lastPathComponent
                await discoverTracks()
                if let updated = sidecarFiles.first(where: { $0.url.standardizedFileURL == writtenURL.standardizedFileURL }) {
                    activeSource = .sidecar(updated)
                }
                return false

            case .embedInVideo(let replaceExisting):
                let replacingID = replaceExisting ? editingEmbeddedTrackID : nil
                try await VideoSubtitleSaver.embed(
                    document,
                    into: videoURL,
                    replacingTrackID: replacingID
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.saveProgress = progress
                    }
                }
                hasUnsavedChanges = false
                savedNotice = videoURL.lastPathComponent
                await discoverTracks()
                await configurePreviewPlayer()
                return true

            case .lyricsTag:
                try await VideoSubtitleSaver.saveLyricsTag(document, to: videoURL)
                hasUnsavedChanges = false
                savedNotice = String(localized: "Subtitles.EmbeddedLyrics")
                await discoverTracks()
                return true
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private nonisolated static func readEmbeddedLyricsString(from videoURL: URL) async -> String? {
        let tagLibLyrics: String? = await Task.detached(priority: .userInitiated) {
            let path = videoURL.path(percentEncoded: false)
            guard TagLibFile.supportedExtensions().contains(videoURL.pathExtension.lowercased()),
                  let tagFile = TagLibFile(path: path),
                  let values = tagFile.properties["LYRICS"] else {
                return nil
            }
            let joined = values.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }.value
        if let tagLibLyrics {
            return tagLibLyrics
        }
        return await Videoglot.extractEmbeddedLyrics(from: videoURL)
    }

    /// Formats seconds as `MM:SS.d` or `H:MM:SS.d` for cue timing controls.
    static func formatCueTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let totalTenths = Int((clamped * 10.0).rounded())
        let hours = totalTenths / 36_000
        let minutes = (totalTenths / 600) % 60
        let secs = (totalTenths / 10) % 60
        let tenths = totalTenths % 10
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, secs, tenths)
        }
        return String(format: "%02d:%02d.%d", minutes, secs, tenths)
    }
}
