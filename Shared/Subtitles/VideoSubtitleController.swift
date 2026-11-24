@preconcurrency import AVFoundation
import Foundation
import Prelude
import Videoglot

/// Manages subtitle and synced-lyrics discovery, track selection, and cue timing for the playing video.
/// Shared by both iOS (`MediaPlayerManager`) and macOS (`MacPlayer`).
@Observable
@MainActor
final class VideoSubtitleController {

    private(set) var videoURL: URL?
    private(set) var availableTracks: [VideoSubtitleTrack] = []
    /// The selected track ID, or `nil` when subtitles/lyrics are off.
    private(set) var selectedTrackID: String?
    /// The timed-text document currently rendered by Melodee's overlay (sidecars and synced embedded lyrics).
    private(set) var activeDocument: TimedTextDocument?
    /// The active subtitle or lyric text at the current playback time.
    private(set) var activeText: String?
    /// Plain (unsynced) embedded lyrics when the user chooses an unsynced lyrics track.
    private(set) var unsyncedLyrics: String?
    /// Whether the currently selected track is lyrics (rather than subtitles).
    var isShowingLyrics: Bool {
        selectedTrack?.isLyrics ?? false
    }

    var selectedTrack: VideoSubtitleTrack? {
        guard let selectedTrackID else { return nil }
        return availableTracks.first { $0.id == selectedTrackID }
    }

    var hasTracks: Bool {
        !availableTracks.isEmpty
    }

    /// Called whenever tracks change or selection changes (used by AppKit observers on Mac).
    @ObservationIgnored var onChange: (() -> Void)?
    /// Set by the player: swaps the playing item for one on `asset`, keeping its position and play state.
    @ObservationIgnored var replacePlayerAsset: ((AVAsset) -> AVPlayerItem?)?

    @ObservationIgnored private weak var avPlayerItem: AVPlayerItem?
    @ObservationIgnored private var originalAsset: AVAsset?
    @ObservationIgnored private var composition: VideoSubtitleComposition?
    @ObservationIgnored private var compositionTrackID: String?
    @ObservationIgnored private var compositionLegibleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var compositionOption: AVMediaSelectionOption?
    @ObservationIgnored private var compositionTask: Task<Void, Never>?
    @ObservationIgnored private var avLegibleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var avLegibleOptions: [AVMediaSelectionOption] = []
    @ObservationIgnored private weak var extendedVideoPlayer: ExtendedVideoPlayer?
    @ObservationIgnored private var vlcTracks: [ExtendedVideoPlayer.TextTrack] = []
    @ObservationIgnored private var sidecarTracks: [VideoSubtitleTrack] = []
    @ObservationIgnored private var embeddedLyricsTrack: VideoSubtitleTrack?
    @ObservationIgnored private var embeddedLyricsDocument: TimedTextDocument?
    @ObservationIgnored private var lastNonNilTrackID: String?
    @ObservationIgnored private var hasAppliedInitialSelection = false
    @ObservationIgnored private var lastKnownTime: TimeInterval = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init() {
        VideoSubtitleComposition.removeStaleFiles()
    }

    // MARK: - Loading

    /// Loads embedded `AVMediaSelectionGroup` tracks, sidecar files, and embedded lyrics for a standard-engine video.
    func loadForAVPlayer(videoURL: URL, item: AVPlayerItem) {
        resetState(for: videoURL)
        self.avPlayerItem = item
        self.originalAsset = item.asset

        let url = videoURL
        loadTask = Task { [weak self] in
            async let sidecars = Self.discoverSidecarTracks(for: url)
            async let lyricsDoc = Self.loadEmbeddedLyrics(for: url)
            async let legibleGroup: AVMediaSelectionGroup? = try? await item.asset.loadMediaSelectionGroup(for: .legible)

            let resolvedSidecars = await sidecars
            let resolvedLyrics = await lyricsDoc
            let resolvedGroup = await legibleGroup

            guard !Task.isCancelled, let self, self.videoURL == url, self.avPlayerItem === item else { return }

            self.sidecarTracks = resolvedSidecars
            self.setEmbeddedLyricsDocument(resolvedLyrics)
            self.avLegibleGroup = resolvedGroup
            self.avLegibleOptions = resolvedGroup?.options.filter {
                !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
            } ?? []
            self.rebuildAvailableTracks(applyInitialPreference: true)
        }
    }

    /// Loads sidecar files, embedded lyrics, and listens for VLCKit text tracks for an extended-engine video.
    func loadForExtendedPlayer(videoURL: URL, extendedPlayer: ExtendedVideoPlayer) {
        resetState(for: videoURL)
        self.extendedVideoPlayer = extendedPlayer
        self.vlcTracks = extendedPlayer.textTracks

        let url = videoURL
        loadTask = Task { [weak self] in
            async let sidecars = Self.discoverSidecarTracks(for: url)
            async let lyricsDoc = Self.loadEmbeddedLyrics(for: url)

            let resolvedSidecars = await sidecars
            let resolvedLyrics = await lyricsDoc

            guard !Task.isCancelled, let self, self.videoURL == url else { return }
            self.sidecarTracks = resolvedSidecars
            self.setEmbeddedLyricsDocument(resolvedLyrics)
            self.rebuildAvailableTracks(applyInitialPreference: true)
        }
    }

    /// Called when VLCKit discovers, updates, or removes embedded text tracks during playback.
    func updateExtendedTextTracks(_ tracks: [ExtendedVideoPlayer.TextTrack]) {
        guard extendedVideoPlayer != nil else { return }
        guard tracks != vlcTracks else { return }
        vlcTracks = tracks
        // Re-evaluate initial selection once embedded tracks arrive if the user hasn't picked a track yet.
        let shouldAutoSelect = !hasAppliedInitialSelection || selectedTrackID == nil
        rebuildAvailableTracks(applyInitialPreference: shouldAutoSelect)
    }

    /// Re-scans sidecar files and embedded lyrics after the user saves edits in the subtitle/lyrics editor.
    func reloadAfterEdit() {
        guard let url = videoURL else { return }
        let currentSelection = selectedTrackID
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            async let sidecars = Self.discoverSidecarTracks(for: url)
            async let lyricsDoc = Self.loadEmbeddedLyrics(for: url)
            let resolvedSidecars = await sidecars
            let resolvedLyrics = await lyricsDoc
            guard !Task.isCancelled, let self, self.videoURL == url else { return }
            self.sidecarTracks = resolvedSidecars
            self.setEmbeddedLyricsDocument(resolvedLyrics)
            self.rebuildAvailableTracks(applyInitialPreference: false)
            // The edited text has to be written into a new subtitle track
            self.compositionTrackID = nil
            if let currentSelection, self.availableTracks.contains(where: { $0.id == currentSelection }) {
                self.applySelection(currentSelection, persistPreference: false)
            } else if let currentSelection {
                // Previously selected sidecar may have been replaced; keep selection clean.
                _ = currentSelection
                self.applySelection(nil, persistPreference: false)
            }
        }
    }

    /// Clears all subtitle state when stopping or switching away from video.
    func clear() {
        loadTask?.cancel()
        loadTask = nil
        videoURL = nil
        avPlayerItem = nil
        discardComposition()
        avLegibleGroup = nil
        avLegibleOptions = []
        extendedVideoPlayer = nil
        vlcTracks = []
        sidecarTracks = []
        embeddedLyricsTrack = nil
        embeddedLyricsDocument = nil
        availableTracks = []
        selectedTrackID = nil
        lastNonNilTrackID = nil
        activeDocument = nil
        activeText = nil
        unsyncedLyrics = nil
        hasAppliedInitialSelection = false
        lastKnownTime = 0
        onChange?()
    }

    // MARK: - Selection & Playback Tick

    /// Selects a subtitle or lyrics track by ID, or turns subtitles off when `trackID` is `nil`.
    func selectTrack(_ trackID: String?) {
        applySelection(trackID, persistPreference: true)
    }

    /// Turns subtitles off if active, or re-enables the last used / preferred track.
    func toggleSubtitles() {
        if selectedTrackID != nil {
            selectTrack(nil)
        } else if let lastNonNilTrackID, availableTracks.contains(where: { $0.id == lastNonNilTrackID }) {
            selectTrack(lastNonNilTrackID)
        } else if let first = availableTracks.first {
            selectTrack(first.id)
        }
    }

    /// Updates the displayed overlay cue for `currentTime`. Call periodically during video playback and after seeks.
    func update(currentTime: TimeInterval) {
        lastKnownTime = currentTime
        guard let activeDocument else {
            if activeText != nil {
                activeText = nil
            }
            return
        }
        let nextText = activeDocument.activeText(at: currentTime)
        if nextText != activeText {
            activeText = nextText
        }
    }

    // MARK: - Internal

    private func resetState(for url: URL) {
        loadTask?.cancel()
        loadTask = nil
        videoURL = url
        avPlayerItem = nil
        discardComposition()
        avLegibleGroup = nil
        avLegibleOptions = []
        extendedVideoPlayer = nil
        vlcTracks = []
        sidecarTracks = []
        embeddedLyricsTrack = nil
        embeddedLyricsDocument = nil
        availableTracks = []
        selectedTrackID = nil
        lastNonNilTrackID = nil
        activeDocument = nil
        activeText = nil
        unsyncedLyrics = nil
        hasAppliedInitialSelection = false
        lastKnownTime = 0
        onChange?()
    }

    private func setEmbeddedLyricsDocument(_ document: TimedTextDocument?) {
        embeddedLyricsDocument = document
        guard let document, document.hasTimedCues || (document.unsyncedText?.isEmpty == false) else {
            embeddedLyricsTrack = nil
            return
        }
        let title = document.hasTimedCues
            ? String(localized: "Subtitles.EmbeddedSyncedLyrics")
            : String(localized: "Subtitles.EmbeddedLyrics")
        embeddedLyricsTrack = VideoSubtitleTrack(
            id: "embedded-lyrics",
            title: title,
            languageCode: document.languageCode,
            isLyrics: true,
            source: .embeddedLyrics(isSynced: document.hasTimedCues)
        )
    }

    private func rebuildAvailableTracks(applyInitialPreference: Bool) {
        var tracks: [VideoSubtitleTrack] = []

        // 1. Embedded AVPlayer legible tracks
        for (index, option) in avLegibleOptions.enumerated() {
            let lang = option.extendedLanguageTag ?? option.locale?.identifier
            let title = option.displayName.isEmpty
                ? String(localized: "Subtitles.TrackNumber.\(index + 1)")
                : option.displayName
            let id = "av:\(index):\(lang ?? title)"
            tracks.append(VideoSubtitleTrack(
                id: id,
                title: title,
                languageCode: lang,
                isLyrics: false,
                source: .avMediaOption(index: index)
            ))
        }

        // 2. Embedded VLCKit text tracks
        for vlcTrack in vlcTracks {
            let title = Self.displayName(forVLCTrack: vlcTrack)
            tracks.append(VideoSubtitleTrack(
                id: "vlc:\(vlcTrack.id)",
                title: title,
                languageCode: vlcTrack.language,
                isLyrics: false,
                source: .vlcTextTrack(trackID: vlcTrack.id)
            ))
        }

        // 3. Sidecar subtitle and synced-lyrics files
        tracks.append(contentsOf: sidecarTracks)

        // 4. Embedded lyrics
        if let embeddedLyricsTrack {
            tracks.append(embeddedLyricsTrack)
        }

        availableTracks = tracks

        if applyInitialPreference, let videoURL {
            hasAppliedInitialSelection = true
            let initial = SubtitlePreferences.resolveInitialTrack(
                for: videoURL.path(percentEncoded: false),
                availableTracks: tracks
            )
            applySelection(initial?.id, persistPreference: false)
        } else {
            onChange?()
        }
    }

    private func applySelection(_ trackID: String?, persistPreference: Bool) {
        let track = trackID.flatMap { id in availableTracks.first { $0.id == id } }
        selectedTrackID = track?.id
        if let id = track?.id {
            lastNonNilTrackID = id
        }

        if persistPreference, let videoURL {
            SubtitlePreferences.saveSelection(track, for: videoURL.path(percentEncoded: false))
        }

        // Timed text from files and tags, which Melodee shows itself unless AVPlayer can draw it
        var document: TimedTextDocument?
        unsyncedLyrics = nil
        switch track?.source {
        case .sidecar(let sidecar):
            document = try? TimedTextCodec.parse(contentsOf: sidecar.url)
        case .embeddedLyrics(let isSynced):
            if isSynced {
                document = embeddedLyricsDocument
            } else {
                unsyncedLyrics = embeddedLyricsDocument?.unsyncedText
            }
        default:
            break
        }

        if avPlayerItem != nil {
            if let track, let timedDocument = document, timedDocument.hasTimedCues, replacePlayerAsset != nil {
                if compositionTrackID == track.id, let composition, !isPlayingComposition,
                   let newItem = replacePlayerAsset?(composition.asset) {
                    avPlayerItem = newItem
                }
                if compositionTrackID == track.id, isPlayingComposition {
                    compositionTask?.cancel()
                    selectCompositionOption()
                    document = nil
                } else {
                    if isPlayingComposition, let group = compositionLegibleGroup {
                        avPlayerItem?.select(nil, in: group)
                    } else if let group = avLegibleGroup {
                        avPlayerItem?.select(nil, in: group)
                    }
                    // The overlay shows the text until AVPlayer can take over
                    buildComposition(for: track.id, document: timedDocument)
                }
            } else {
                compositionTask?.cancel()
                if case .avMediaOption(let index) = track?.source, avLegibleOptions.indices.contains(index) {
                    restoreOriginalAsset()
                    if let group = avLegibleGroup {
                        avPlayerItem?.select(avLegibleOptions[index], in: group)
                    }
                } else if isPlayingComposition, let group = compositionLegibleGroup {
                    avPlayerItem?.select(nil, in: group)
                } else if let group = avLegibleGroup {
                    avPlayerItem?.select(nil, in: group)
                }
            }
        }
        if let extendedVideoPlayer {
            if case .vlcTextTrack(let vlcTrackID) = track?.source {
                extendedVideoPlayer.selectTextTrack(id: vlcTrackID)
            } else {
                extendedVideoPlayer.selectTextTrack(id: nil)
            }
        }

        activeDocument = document
        activeText = document?.activeText(at: lastKnownTime)
        onChange?()
    }

    // MARK: - Subtitle Track Composition

    private var isPlayingComposition: Bool {
        guard let composition, let avPlayerItem else { return false }
        return avPlayerItem.asset === composition.asset
    }

    private func selectCompositionOption() {
        guard let group = compositionLegibleGroup, let option = compositionOption else { return }
        avPlayerItem?.select(option, in: group)
    }

    /// Writes `document` into a subtitle track and swaps the playing item for a composition holding it.
    private func buildComposition(for trackID: String, document: TimedTextDocument) {
        compositionTask?.cancel()
        guard let videoURL else { return }
        compositionTask = Task { [weak self] in
            guard let built = try? await VideoSubtitleComposition.make(videoURL: videoURL, document: document) else {
                return
            }
            let group = try? await built.asset.loadMediaSelectionGroup(for: .legible)
            let option = group?.options.first { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }
            guard let self, !Task.isCancelled, self.videoURL == videoURL, self.selectedTrackID == trackID,
                  self.avPlayerItem != nil, let group, let option,
                  let newItem = self.replacePlayerAsset?(built.asset) else {
                try? FileManager.default.removeItem(at: built.subtitleFileURL)
                return
            }
            if let previous = self.composition {
                try? FileManager.default.removeItem(at: previous.subtitleFileURL)
            }
            self.composition = built
            self.compositionTrackID = trackID
            self.compositionLegibleGroup = group
            self.compositionOption = option
            self.avPlayerItem = newItem
            newItem.select(option, in: group)
            self.activeDocument = nil
            self.activeText = nil
            self.onChange?()
        }
    }

    /// Goes back to playing the video file itself, for its own subtitle tracks.
    private func restoreOriginalAsset() {
        guard isPlayingComposition, let originalAsset,
              let newItem = replacePlayerAsset?(originalAsset) else { return }
        avPlayerItem = newItem
    }

    private func discardComposition() {
        compositionTask?.cancel()
        compositionTask = nil
        if let composition {
            try? FileManager.default.removeItem(at: composition.subtitleFileURL)
        }
        composition = nil
        compositionTrackID = nil
        compositionLegibleGroup = nil
        compositionOption = nil
        originalAsset = nil
    }

    private static func displayName(forVLCTrack track: ExtendedVideoPlayer.TextTrack) -> String {
        var parts: [String] = []
        let trimmedName = track.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            parts.append(trimmedName)
        }
        if let lang = track.language?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lang.isEmpty,
           let localized = Locale.current.localizedString(forIdentifier: lang) {
            let formatted = localized.capitalized(with: .current)
            if !parts.contains(where: { $0.localizedCaseInsensitiveContains(formatted) }) {
                parts.append(formatted)
            }
        }
        return parts.isEmpty ? track.id : parts.joined(separator: " · ")
    }

    private nonisolated static func discoverSidecarTracks(for videoURL: URL) async -> [VideoSubtitleTrack] {
        await Task.detached(priority: .utility) {
            SidecarTimedTextFile.discover(for: videoURL).map { sidecar in
                VideoSubtitleTrack(
                    id: "sidecar:\(sidecar.url.lastPathComponent)",
                    title: sidecar.displayName,
                    languageCode: sidecar.languageCode,
                    isLyrics: sidecar.format.isLyrics,
                    source: .sidecar(sidecar)
                )
            }
        }.value
    }

    /// Reads embedded lyrics from TagLib (`LYRICS` property, matching the tag editor) and AVURLAsset metadata.
    private nonisolated static func loadEmbeddedLyrics(for videoURL: URL) async -> TimedTextDocument? {
        let tagLibLyrics: String? = await Task.detached(priority: .utility) {
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
            return TimedTextCodec.parseEmbeddedLyrics(tagLibLyrics)
        }
        if let avLyrics = await Videoglot.extractEmbeddedLyrics(from: videoURL) {
            return TimedTextCodec.parseEmbeddedLyrics(avLyrics)
        }
        return nil
    }
}
