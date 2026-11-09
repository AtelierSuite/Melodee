@preconcurrency import AVFAudio
import Accelerate
import AudioToolbox
import Foundation
import SFBAudioEngine
import Synchronization

/// Measures the loudness of frequency bands in the audio player's output, for the Now Playing visualizer.
///
/// The samples sent to the output hardware are copied into a ring buffer by a render callback on the
/// engine's output unit, which runs on every I/O cycle (around 10 ms). A tap on a node would be simpler,
/// but iOS delivers tap buffers only every 100 ms or so, which makes the bars lag and stutter.
///
/// The visualizer asks for levels on every display frame, and each request analyses the most recent
/// audio that is being heard, so the bars move as smoothly as the display refreshes.
final class SpectrumAnalyzer: @unchecked Sendable {

    static let bandCount = 24

    /// The loudness of each band from 0 to 1.
    struct Levels: Sendable {
        var bands: [Float]

        static let silent = Levels(bands: Array(repeating: 0, count: bandCount))
    }

    private static let fftSize = 2048
    private static let minimumFrequency: Float = 40.0
    private static let maximumFrequency: Float = 16_000.0
    /// Loudness, in dBFS, that is drawn as an empty and as a full bar.
    private static let floorDecibels: Float = -70.0
    private static let ceilingDecibels: Float = -6.0
    /// How quickly bars ease towards a louder or quieter level, per second. Higher is snappier.
    private static let barRiseRate: Float = 40.0
    private static let barFallRate: Float = 10.0

    private let ring = SampleRing()

    // Only used on the main actor
    private let fftSetup: vDSP.FFT<DSPSplitComplex>?
    private let window: [Float]
    private var samples: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitudes: [Float]
    private var bandRanges: [Range<Int>] = []
    private var bandRangesSampleRate: Double = 0
    private var displayed = Levels.silent
    private var lastDisplayTime: TimeInterval?
    private var outputLatency: TimeInterval = 0
    private var clientCount = 0
    private var installedOutputUnit: AudioUnit?

    init() {
        fftSetup = vDSP.FFT(log2n: vDSP_Length(log2(Float(Self.fftSize))),
                            radix: .radix2,
                            ofType: DSPSplitComplex.self)
        window = vDSP.window(ofType: Float.self,
                             usingSequence: .hanningDenormalized,
                             count: Self.fftSize,
                             isHalfWindow: false)
        samples = [Float](repeating: 0, count: Self.fftSize)
        windowed = [Float](repeating: 0, count: Self.fftSize)
        real = [Float](repeating: 0, count: Self.fftSize / 2)
        imaginary = [Float](repeating: 0, count: Self.fftSize / 2)
        magnitudes = [Float](repeating: 0, count: Self.fftSize / 2)
    }

    // MARK: Lifecycle

    /// Starts analysing the player's output for a visualizer that came on screen.
    /// Balance each call with ``stop(on:)``.
    @MainActor
    func start(on audioPlayer: AudioPlayer) {
        clientCount += 1
        if clientCount == 1 {
            installRenderNotify(on: audioPlayer)
        }
    }

    /// Stops analysing once no visualizer is on screen.
    @MainActor
    func stop(on audioPlayer: AudioPlayer) {
        guard clientCount > 0 else { return }
        clientCount -= 1
        if clientCount == 0 {
            removeRenderNotify()
            // Keep the displayed levels, so the bars stay put while the visualizer turns away
            lastDisplayTime = nil
        }
    }

    /// Installs the render callback again after the engine changed its output, such as on a route change.
    @MainActor
    func reconfigure(on audioPlayer: AudioPlayer) {
        guard clientCount > 0 else { return }
        removeRenderNotify()
        installRenderNotify(on: audioPlayer)
    }

    @MainActor
    private func installRenderNotify(on audioPlayer: AudioPlayer) {
        guard installedOutputUnit == nil, let outputUnit = audioPlayer.outputNode.audioUnit else { return }
        // The output unit receives audio in the format of the main mixer's connection to it
        ring.setSampleRate(audioPlayer.outputNode.inputFormat(forBus: 0).sampleRate)
        let status = AudioUnitAddRenderNotify(outputUnit, spectrumRenderNotify,
                                              Unmanaged.passUnretained(ring).toOpaque())
        guard status == noErr else {
            debugPrint("Could not add render notify for the visualizer: \(status)")
            return
        }
        installedOutputUnit = outputUnit
        // The time between samples leaving the engine and being heard, which is long for Bluetooth outputs
        outputLatency = AVAudioSession.sharedInstance().outputLatency
    }

    @MainActor
    private func removeRenderNotify() {
        guard let outputUnit = installedOutputUnit else { return }
        AudioUnitRemoveRenderNotify(outputUnit, spectrumRenderNotify, Unmanaged.passUnretained(ring).toOpaque())
        installedOutputUnit = nil
    }

    // MARK: Display

    /// The levels to draw at `time`, in seconds on any steadily increasing clock. Call once per display frame.
    @MainActor
    func levels(at time: TimeInterval, isPlaying: Bool) -> Levels {
        let elapsed = Float(min(max(time - (lastDisplayTime ?? time), 0), 0.1))
        lastDisplayTime = time

        var target: [Float]?
        if isPlaying, installedOutputUnit != nil {
            target = analyseLatestAudio()
        }

        for band in 0..<Self.bandCount {
            // Ease towards the new level, rising quickly and falling back gradually,
            // which also evens out the frame to frame jitter of the analysis
            let current = displayed.bands[band]
            let goal = target?[band] ?? 0
            let rate = goal > current ? Self.barRiseRate : Self.barFallRate
            displayed.bands[band] = current + (goal - current) * (1 - exp(-rate * elapsed))
        }
        return displayed
    }

    // MARK: Analysis

    /// Analyses the audio that is being heard now: the most recent window, minus the output latency.
    @MainActor
    private func analyseLatestAudio() -> [Float]? {
        guard let fftSetup else { return nil }
        let sampleRate = ring.sampleRate
        guard sampleRate > 0 else { return nil }
        let latencySamples = Int(outputLatency * sampleRate)
        guard ring.copyLatest(Self.fftSize, skippingNewest: latencySamples, into: &samples) else { return nil }

        if sampleRate != bandRangesSampleRate {
            bandRangesSampleRate = sampleRate
            bandRanges = Self.makeBandRanges(sampleRate: sampleRate)
        }

        vDSP.multiply(samples, window, result: &windowed)
        let halfSize = Self.fftSize / 2
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!,
                                            imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBytes { windowedBytes in
                    vDSP_ctoz(windowedBytes.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                              &split, 1, vDSP_Length(halfSize))
                }
                fftSetup.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &magnitudes)
            }
        }

        // vDSP's real FFT is scaled by 2, and a Hann window halves the amplitude of a sine,
        // so scale the result for a full-scale sine to read as 0 dBFS
        let amplitudeScale = 2.0 / Float(Self.fftSize)
        let powerScale = amplitudeScale * amplitudeScale
        let range = Self.ceilingDecibels - Self.floorDecibels

        return bandRanges.map { bins in
            guard !bins.isEmpty else { return 0 }
            // Use the loudest bin so narrow tones still show in wide high-frequency bands
            let power = magnitudes[bins].max() ?? 0
            let decibels = 10.0 * log10(max(power * powerScale, 1e-12))
            return min(max((decibels - Self.floorDecibels) / range, 0), 1)
        }
    }

    /// Splits the spectrum into bands spaced evenly on a logarithmic scale, as on a graphic equalizer.
    private static func makeBandRanges(sampleRate: Double) -> [Range<Int>] {
        let binWidth = Float(sampleRate) / Float(fftSize)
        let maximumBin = fftSize / 2
        let topFrequency = min(maximumFrequency, Float(sampleRate) / 2)
        let ratio = topFrequency / minimumFrequency
        var ranges: [Range<Int>] = []
        var lowerBin = max(Int((minimumFrequency / binWidth).rounded()), 1)
        for band in 0..<bandCount {
            let upperFrequency = minimumFrequency * pow(ratio, Float(band + 1) / Float(bandCount))
            // Every band covers at least one bin, so low bands don't come out empty
            let upperBin = min(max(Int((upperFrequency / binWidth).rounded()), lowerBin + 1), maximumBin)
            ranges.append(lowerBin..<max(upperBin, lowerBin))
            lowerBin = upperBin
        }
        return ranges
    }
}

// MARK: - Ring buffer

/// The most recent output samples, mixed down to mono.
///
/// Written only by the output unit's render callback on the real-time audio thread, which must not
/// allocate or lock, so the samples live in fixed storage and the write position is an atomic.
/// Reads may race with a write into the oldest samples, which at worst blurs one frame of the display.
private final class SampleRing: @unchecked Sendable {

    static let capacity = 16384
    private static let mask = capacity - 1

    let storage: UnsafeMutablePointer<Float>
    /// The number of samples written so far.
    let writeCount = Atomic<Int>(0)
    private let sampleRateBits = Atomic<UInt64>(0)

    var sampleRate: Double {
        Double(bitPattern: sampleRateBits.load(ordering: .relaxed))
    }

    init() {
        storage = .allocate(capacity: Self.capacity)
        storage.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        storage.deallocate()
    }

    /// Runs on the real-time audio thread.
    /// Set from the main actor when the render callback is installed, before audio is written.
    func setSampleRate(_ sampleRate: Double) {
        sampleRateBits.store(sampleRate.bitPattern, ordering: .relaxed)
    }

    func write(_ bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        guard frameCount > 0, frameCount <= Self.capacity, bufferList.count > 0 else { return }
        let start = writeCount.load(ordering: .relaxed)
        // Non-interleaved audio has a buffer per channel; interleaved audio has one buffer of all channels
        let isInterleaved = bufferList.count == 1 && bufferList[0].mNumberChannels > 1
        let channelCount = isInterleaved ? Int(bufferList[0].mNumberChannels) : bufferList.count
        let scale = 1.0 / Float(channelCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            if isInterleaved {
                guard let data = bufferList[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                for channel in 0..<channelCount {
                    sum += data[frame * channelCount + channel]
                }
            } else {
                for channel in 0..<channelCount {
                    guard let data = bufferList[channel].mData?.assumingMemoryBound(to: Float.self) else { return }
                    sum += data[frame]
                }
            }
            storage[(start + frame) & Self.mask] = sum * scale
        }
        writeCount.store(start + frameCount, ordering: .releasing)
    }

    /// Copies the newest `count` samples, leaving out the `skippingNewest` most recent ones, oldest first.
    /// Returns false if not enough audio has been written yet.
    func copyLatest(_ count: Int, skippingNewest skipped: Int, into destination: inout [Float]) -> Bool {
        let end = writeCount.load(ordering: .acquiring) - max(min(skipped, Self.capacity - count), 0)
        guard end >= count else { return false }
        let start = end - count
        destination.withUnsafeMutableBufferPointer { pointer in
            for index in 0..<count {
                pointer[index] = storage[(start + index) & Self.mask]
            }
        }
        return true
    }
}

/// Called before and after the output unit renders. After rendering, copies what is about to be heard.
/// Runs on the real-time audio thread, so it must not allocate, lock or call into Swift concurrency.
private func spectrumRenderNotify(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    guard ioActionFlags.pointee.contains(.unitRenderAction_PostRender),
          inBusNumber == 0,
          let ioData else {
        return noErr
    }
    let ring = Unmanaged<SampleRing>.fromOpaque(inRefCon).takeUnretainedValue()
    ring.write(UnsafeMutableAudioBufferListPointer(ioData), frameCount: Int(inNumberFrames))
    return noErr
}
