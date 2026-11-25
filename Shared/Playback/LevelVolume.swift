@preconcurrency import AVFAudio
import Foundation
import SFBAudioEngine

/// Evens out loudness between tracks by raising or lowering each one towards the same level, like Sound Check.
@MainActor
@Observable
final class LevelVolume {

    nonisolated static let isEnabledKey = "LevelVolume.IsEnabled"

    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isEnabledKey) }
    }

    /// Analysis measures loudness against -18 LUFS, and tracks are brought to -16 LUFS instead,
    /// which keeps most music close to how loud it was mastered.
    private static let targetOffset: Float = 2.0
    nonisolated static let targetLoudness: Float = -16.0
    private static let gainRange: ClosedRange<Float> = -15.0...9.0
    /// Changes during a track ease in, so the volume never jumps suddenly.
    private static let ramp: Duration = .seconds(2)
    private static let rampStep: Duration = .milliseconds(20)

    @ObservationIgnored nonisolated let unit = AVAudioUnitEQ(numberOfBands: 0)

    /// Whether tracks are raised or lowered. Turning it on or off eases into the new gain.
    var isOn: Bool = LevelVolume.isEnabled {
        didSet {
            guard isOn != oldValue else { return }
            Self.isEnabled = isOn
            refresh(ramp: Self.ramp)
        }
    }
    /// What is known about the playing track's loudness.
    private(set) var status: Status = .idle
    /// The gain being applied right now in dB, which moves gradually while easing into a new gain.
    private(set) var appliedGain: Float = 0.0

    enum Status: Equatable {
        case idle
        /// Videos aren't adjusted.
        case video
        /// The track hasn't been measured, and won't be while the setting is off.
        case notMeasured
        case measuring
        /// The track has no sound, so there's nothing to adjust.
        case silent
        case measured(Measurement)
    }

    struct Measurement: Equatable {
        /// The track's integrated loudness in LUFS.
        let loudness: Float
        /// The gain that brings the track to the target, in dB.
        let gain: Float
    }

    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var upcomingURLs: [URL] = []
    @ObservationIgnored private var isVideo: Bool = false
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var rampTask: Task<Void, Never>?
    @ObservationIgnored private var analyses: [String: Task<Analysis?, Never>] = [:]
    @ObservationIgnored private var cache: [String: Analysis]

    private struct Analysis: Codable, Sendable {
        let gain: Float
        let peak: Float
    }

    init() {
        cache = Self.loadCache()
        unit.globalGain = 0.0
        unit.bypass = true
    }

    // MARK: Processing graph

    /// Places the gain unit between `node`, or the source node, and the main mixer.
    nonisolated func insert(into audioPlayer: AudioPlayer, after node: AVAudioNode? = nil) {
        let unit = self.unit
        let sourceNode = audioPlayer.sourceNode
        audioPlayer.modifyProcessingGraph { engine in
            let format = sourceNode.outputFormat(forBus: 0)
            engine.attach(unit)
            if let node {
                engine.disconnectNodeOutput(node)
                engine.connect(node, to: unit, format: format)
            } else {
                engine.disconnectNodeOutput(sourceNode)
                engine.connect(sourceNode, to: unit, format: format)
            }
            engine.connect(unit, to: engine.mainMixerNode, format: format)
        }
    }

    /// Carries the gain unit over to a new format, returning the node the source node should connect to.
    nonisolated func reconnect(in engine: AVAudioEngine, after node: AVAudioNode? = nil,
                               with format: AVAudioFormat) -> AVAudioNode {
        if let node {
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: unit, format: format)
        }
        engine.disconnectNodeOutput(unit)
        engine.connect(unit, to: engine.mainMixerNode, format: format)
        return node ?? unit
    }

    // MARK: Tracks

    /// Sets the gain for a track about to play, then measures it and the tracks after it if they haven't been yet.
    func trackWillPlay(_ url: URL?, isVideo: Bool = false, upcoming: [URL] = []) {
        currentURL = isVideo ? nil : url
        self.isVideo = isVideo
        upcomingURLs = Array(upcoming.prefix(2))
        refresh()
    }

    private func refresh(ramp: Duration = .zero) {
        analysisTask?.cancel()
        analysisTask = nil
        guard let url = currentURL else {
            status = isVideo ? .video : .idle
            setGain(0.0, ramp: ramp)
            return
        }
        if let analysis = cachedAnalysis(for: url) {
            let measurement = Self.measurement(for: analysis)
            status = measurement.map { .measured($0) } ?? .silent
            setGain(isOn ? measurement?.gain ?? 0.0 : 0.0, ramp: ramp)
            if isOn {
                analysisTask = Task { [upcomingURLs] in
                    await self.analyze(upcomingURLs)
                }
            }
            return
        }
        setGain(0.0, ramp: ramp)
        guard isOn else {
            status = .notMeasured
            return
        }
        status = .measuring
        analysisTask = Task { [upcomingURLs] in
            let analysis = await self.analysis(for: url)
            guard !Task.isCancelled, self.currentURL == url else { return }
            if let analysis {
                let measurement = Self.measurement(for: analysis)
                self.status = measurement.map { .measured($0) } ?? .silent
                self.setGain(measurement?.gain ?? 0.0, ramp: Self.ramp)
            } else {
                self.status = .notMeasured
            }
            await self.analyze(upcomingURLs)
        }
    }

    private func analyze(_ urls: [URL]) async {
        for url in urls where !Task.isCancelled {
            _ = await analysis(for: url)
        }
    }

    private static func measurement(for analysis: Analysis) -> Measurement? {
        guard analysis.peak > 0 else { return nil }
        // Analysis gives the gain that brings a track to -18 LUFS
        let loudness = -18.0 - analysis.gain
        // Never raise the loudest sample past full scale, where it would clip
        let gain = min(analysis.gain + targetOffset, -20.0 * log10(analysis.peak))
        return Measurement(loudness: loudness, gain: min(max(gain, gainRange.lowerBound), gainRange.upperBound))
    }

    private func setGain(_ gain: Float, ramp: Duration) {
        rampTask?.cancel()
        rampTask = nil
        let unit = self.unit
        let start = unit.bypass ? 0.0 : unit.globalGain
        guard ramp > .zero, abs(gain - start) > 0.1 else {
            unit.globalGain = gain
            unit.bypass = gain == 0.0
            appliedGain = gain
            return
        }
        unit.bypass = false
        rampTask = Task {
            let steps = max(1, Int(ramp / Self.rampStep))
            for step in 1...steps {
                try? await Task.sleep(for: Self.rampStep)
                guard !Task.isCancelled else { return }
                unit.globalGain = start + (gain - start) * Float(step) / Float(steps)
                self.appliedGain = unit.globalGain
            }
            unit.bypass = gain == 0.0
        }
    }

    // MARK: Analysis

    private func analysis(for url: URL) async -> Analysis? {
        guard let key = Self.cacheKey(for: url) else { return nil }
        if let analysis = cache[key] { return analysis }
        if let task = analyses[key] { return await task.value }
        let task = Task.detached(priority: .utility) { () -> Analysis? in
            guard let replayGain = try? ReplayGainAnalyzer.analyzeTrack(url) else { return nil }
            return Analysis(gain: replayGain.gain, peak: replayGain.peak)
        }
        analyses[key] = task
        let analysis = await task.value
        analyses[key] = nil
        if let analysis {
            cache[key] = analysis
            saveCache()
        }
        return analysis
    }

    private func cachedAnalysis(for url: URL) -> Analysis? {
        Self.cacheKey(for: url).flatMap { cache[$0] }
    }

    /// Includes the file's size and modification date, so an edited or trimmed file is measured again.
    private static func cacheKey(for url: URL) -> String? {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        // The app's container moves when the app is updated, so files inside it are keyed relative to it
        let home = URL.homeDirectory.standardizedFileURL.path(percentEncoded: false)
        if path.hasPrefix(home) {
            path = "~/" + path.dropFirst(home.count).trimmingPrefix("/")
        }
        return "\(path)|\(size)|\(modified.timeIntervalSinceReferenceDate)"
    }

    private static var cacheURL: URL {
        URL.cachesDirectory.appending(path: "LevelVolume.json")
    }

    private static func loadCache() -> [String: Analysis] {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode([String: Analysis].self, from: data) else { return [:] }
        return cache
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }
}
