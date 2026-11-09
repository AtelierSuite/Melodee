import Accelerate
@preconcurrency import AVFAudio
import Foundation
import SFBAudioEngine

/// The direction audio is played in while holding the fast forward or rewind buttons.
enum ScrubDirection: Sendable {
    case forward
    case backward
}

/// Plays a file's audio faster than normal, forwards or in reverse, while the fast forward or rewind
/// buttons are held. It runs on its own audio engine so the main player can stay paused at its position.
///
/// The file is decoded a short chunk at a time. Going backwards, each chunk is decoded from a seek and
/// reversed, and the chunks are played from the latest to the earliest, so the reversed audio is continuous.
final class ScrubAudioPlayer: @unchecked Sendable {

    enum ScrubError: Error {
        case unsupportedFile
    }

    /// Seconds of the file decoded at a time.
    private static let chunkDuration: TimeInterval = 0.25
    /// How many chunks are kept scheduled ahead of the one being heard.
    private static let chunksAhead = 3

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let queue = DispatchQueue(label: "ScrubAudioPlayer", qos: .userInteractive)
    private let lock = NSLock()

    // Only accessed on the queue
    private var decoder: AudioDecoder?
    private var converter: AVAudioConverter?
    private var chunkLength: AVAudioFramePosition = 0
    /// Going forwards, the next frame to decode. Going backwards, the frame the next chunk ends before.
    private var nextFrame: AVAudioFramePosition = 0
    private var hasReachedEdge = false
    /// Changes whenever playback stops, so completion handlers of buffers from earlier runs do nothing.
    private var generation = 0

    // Guarded by the lock, as they are read from the main thread for the playback position
    private var isActive = false
    private var direction: ScrubDirection = .forward
    private var rate: Double = 1.0
    private var sampleRate: Double = 44_100
    private var startFrame: AVAudioFramePosition = 0
    private var fileLength: AVAudioFramePosition = 0
    private var scheduledFrames: AVAudioFramePosition = 0
    private var startUptime: TimeInterval = 0

    init() {
        engine.attach(playerNode)
        engine.attach(timePitch)
    }

    /// Starts playing the file at `url` from `time` seconds, at `rate` times normal speed in `direction`.
    func start(url: URL, at time: TimeInterval, direction: ScrubDirection, rate: Float) throws {
        stop()
        try queue.sync {
            let decoder = try AudioDecoder(url: url)
            try decoder.open()
            let processingFormat = decoder.processingFormat
            let length = decoder.length
            guard decoder.supportsSeeking, length > 0,
                  let outputFormat = AVAudioFormat(standardFormatWithSampleRate: processingFormat.sampleRate,
                                                   channels: min(processingFormat.channelCount, 2)) else {
                throw ScrubError.unsupportedFile
            }
            if processingFormat == outputFormat {
                converter = nil
            } else {
                guard let converter = AVAudioConverter(from: processingFormat, to: outputFormat) else {
                    throw ScrubError.unsupportedFile
                }
                converter.downmix = true
                self.converter = converter
            }
            let sampleRate = processingFormat.sampleRate
            let frame = min(max(0, AVAudioFramePosition(time * sampleRate)), length)
            if direction == .forward, frame > 0 {
                try decoder.seek(to: frame)
            }
            self.decoder = decoder
            chunkLength = max(1, AVAudioFramePosition(Self.chunkDuration * sampleRate))
            nextFrame = frame
            hasReachedEdge = false
            lock.withLock {
                self.direction = direction
                self.rate = Double(rate)
                self.sampleRate = sampleRate
                self.startFrame = frame
                self.fileLength = length
                self.scheduledFrames = 0
            }

            engine.disconnectNodeOutput(playerNode)
            engine.disconnectNodeOutput(timePitch)
            engine.connect(playerNode, to: timePitch, format: outputFormat)
            engine.connect(timePitch, to: engine.mainMixerNode, format: outputFormat)
            timePitch.rate = rate

            for _ in 0..<Self.chunksAhead {
                scheduleNextChunk()
            }
            try engine.start()
            playerNode.play()
            lock.withLock {
                startUptime = ProcessInfo.processInfo.systemUptime
                isActive = true
            }
        }
    }

    /// The position in the file being heard, in seconds, or nil when not playing.
    var currentTime: TimeInterval? {
        lock.withLock {
            guard isActive else { return nil }
            let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
            let playedFrames = min(AVAudioFramePosition(elapsed * rate * sampleRate), scheduledFrames)
            let frame = direction == .forward ? startFrame + playedFrames : startFrame - playedFrames
            return TimeInterval(min(max(0, frame), fileLength)) / sampleRate
        }
    }

    func stop() {
        lock.withLock { isActive = false }
        queue.sync {
            generation += 1
            playerNode.stop()
            engine.stop()
            try? decoder?.close()
            decoder = nil
            converter = nil
        }
    }

    // MARK: - Decoding

    private func scheduleNextChunk() {
        guard let decoder, !hasReachedEdge else { return }
        let direction = lock.withLock { self.direction }
        let range: Range<AVAudioFramePosition>
        switch direction {
        case .forward:
            range = nextFrame..<min(nextFrame + chunkLength, decoder.length)
        case .backward:
            range = max(0, nextFrame - chunkLength)..<nextFrame
        }
        guard !range.isEmpty else {
            hasReachedEdge = true
            return
        }
        do {
            if direction == .backward {
                try decoder.seek(to: range.lowerBound)
            }
        } catch {
            hasReachedEdge = true
            return
        }
        guard let buffer = decodeChunk(frameCount: AVAudioFrameCount(range.count)), buffer.frameLength > 0 else {
            hasReachedEdge = true
            return
        }
        switch direction {
        case .forward:
            nextFrame = range.lowerBound + AVAudioFramePosition(buffer.frameLength)
        case .backward:
            Self.reverse(buffer)
            nextFrame = range.lowerBound
        }
        lock.withLock { scheduledFrames += AVAudioFramePosition(buffer.frameLength) }
        let generation = self.generation
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard self.generation == generation else { return }
                self.scheduleNextChunk()
            }
        }
    }

    /// Decodes the next frames from the decoder, converted to the format the engine plays.
    private func decodeChunk(frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let decoder,
              let decoded = AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: frameCount) else {
            return nil
        }
        do {
            try decoder.decode(into: decoded, length: frameCount)
        } catch {
            debugPrint("Failed to decode audio for scrubbing: \(error.localizedDescription)")
            return nil
        }
        guard let converter else { return decoded }
        guard let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                               frameCapacity: decoded.frameLength) else {
            return nil
        }
        do {
            try converter.convert(to: converted, from: decoded)
        } catch {
            debugPrint("Failed to convert audio for scrubbing: \(error.localizedDescription)")
            return nil
        }
        return converted
    }

    private static func reverse(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        for channel in 0..<Int(buffer.format.channelCount) {
            vDSP_vrvrs(channels[channel], 1, vDSP_Length(buffer.frameLength))
        }
    }
}
