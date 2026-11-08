@preconcurrency import AVFoundation
import Foundation
import lame
import SFBAudioEngine

/// Something that turns PCM into an encoded file: an SFBAudioEngine encoder, or ``LAMEEncoder`` for MP3.
protocol PCMEncoder: AnyObject {
    /// The format buffers passed to ``encode(_:)`` must be in.
    var processingFormat: AVAudioFormat { get }
    func encode(_ buffer: AVAudioPCMBuffer) throws
    /// Writes everything still held by the encoder. The file is complete afterwards.
    func finish() throws
    func close()
}

/// An SFBAudioEngine encoder, opened for a source format.
final class SFBPCMEncoder: PCMEncoder {

    private let encoder: AudioEncoder

    init(_ encoder: AudioEncoder, sourceFormat: AVAudioFormat, estimatedFrames: AVAudioFramePosition) throws {
        self.encoder = encoder
        try encoder.setSourceFormat(sourceFormat)
        encoder.estimatedFramesToEncode = estimatedFrames
        try encoder.openReturningError()
    }

    var processingFormat: AVAudioFormat { encoder.processingFormat }

    func encode(_ buffer: AVAudioPCMBuffer) throws {
        try encoder.encode(from: buffer, length: buffer.frameLength)
    }

    func finish() throws {
        try encoder.finish()
    }

    func close() {
        try? encoder.close()
    }
}

/// Writes MP3 by calling LAME directly, rather than through SFBAudioEngine's MP3 encoder, which as of 0.14:
/// - never writes the frames LAME returns when flushed, cutting about 40 ms off the end of every file, and
/// - passes mono audio to `lame_encode_buffer_interleaved_ieee_float`, which always reads two channels, so it
///   encodes memory past the end of the buffer and crashes LAME at random.
///
/// Files are constant bitrate, with a LAME tag so players know the exact length.
final class LAMEEncoder: PCMEncoder {

    let processingFormat: AVAudioFormat
    private let flags: lame_t
    private let file: UnsafeMutablePointer<FILE>
    private var output: [UInt8] = []
    private var isClosed = false

    init(outputURL: URL, sampleRate: Double, channelCount: AVAudioChannelCount, bitrate: Int) throws {
        guard channelCount == 1 || channelCount == 2,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
              let flags = lame_init() else {
            throw AudioglotError.unsupportedAudioFormat
        }
        lame_set_num_channels(flags, Int32(channelCount))
        lame_set_in_samplerate(flags, Int32(sampleRate.rounded()))
        lame_set_mode(flags, channelCount == 1 ? MONO : JOINT_STEREO)
        lame_set_VBR(flags, vbr_off)
        lame_set_brate(flags, Int32(bitrate))
        lame_set_quality(flags, 2)
        lame_set_bWriteVbrTag(flags, 1)
        lame_set_write_id3tag_automatic(flags, 0)
        guard lame_init_params(flags) >= 0 else {
            lame_close(flags)
            throw AudioglotError.unsupportedAudioFormat
        }
        guard let file = fopen(outputURL.path(percentEncoded: false), "w+b") else {
            lame_close(flags)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: outputURL])
        }
        self.processingFormat = format
        self.flags = flags
        self.file = file
    }

    deinit {
        close()
    }

    func encode(_ buffer: AVAudioPCMBuffer) throws {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channels = buffer.floatChannelData else { return }
        // LAME's documented worst case for the encoded size of `frameCount` samples
        reserveOutput(Int(1.25 * Double(frameCount)) + 7200)
        let left = channels[0]
        let right = processingFormat.channelCount > 1 ? channels[1] : channels[0]
        let written = output.withUnsafeMutableBufferPointer { output in
            lame_encode_buffer_ieee_float(flags, left, right, Int32(frameCount),
                                          output.baseAddress, Int32(output.count))
        }
        try write(byteCount: written)
    }

    func finish() throws {
        reserveOutput(7200)
        let flushed = output.withUnsafeMutableBufferPointer { output in
            lame_encode_flush(flags, output.baseAddress, Int32(output.count))
        }
        try write(byteCount: flushed)

        // The LAME tag replaces the empty first frame LAME wrote, giving the exact length for gapless playback
        let tagSize = lame_get_lametag_frame(flags, nil, 0)
        if tagSize > 0 {
            reserveOutput(tagSize)
            let tagLength = output.withUnsafeMutableBufferPointer { output in
                lame_get_lametag_frame(flags, output.baseAddress, output.count)
            }
            guard fseeko(file, 0, SEEK_SET) == 0 else { throw CocoaError(.fileWriteUnknown) }
            try write(byteCount: Int32(tagLength))
        }
        guard fflush(file) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        fclose(file)
        lame_close(flags)
    }

    private func reserveOutput(_ byteCount: Int) {
        if output.count < byteCount {
            output = [UInt8](repeating: 0, count: byteCount)
        }
    }

    private func write(byteCount: Int32) throws {
        guard byteCount >= 0 else { throw AudioglotError.unsupportedAudioFormat }
        guard byteCount > 0 else { return }
        let written = output.withUnsafeBufferPointer { fwrite($0.baseAddress, 1, Int(byteCount), file) }
        guard written == Int(byteCount) else { throw CocoaError(.fileWriteOutOfSpace) }
    }
}
