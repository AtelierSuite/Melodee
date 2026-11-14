import Foundation

/// Trims MP3 by copying frames, so the audio is never re-encoded.
///
/// MP3 frames hold 1152 samples each (576 at the lower MPEG-2 sample rates). Decoding a frame needs the frame
/// before it, whose output overlaps it, and the bytes it borrows from earlier frames through the bit reservoir. The
/// trimmer copies the frames covering the range plus those it depends on, then writes a new LAME tag in front of
/// them giving how many samples at the start (delay) and end (padding) players should drop. Players that honour
/// the LAME tag, as Core Audio and mpg123 (SFBAudioEngine) do, play exactly the requested samples.
///
/// Plain streams of frames, with no Xing frame, are played from their first frame, so they get a LAME tag counted
/// from there. Files the trimmer can't place exactly, such as those with a Xing frame but no LAME tag, throw
/// ``Unsupported`` before anything is written, so the caller can re-encode instead.
enum MP3FrameTrimmer {

    /// The file can't be trimmed by copying frames. Nothing has been written.
    struct Unsupported: Error {
        let reason: String
    }

    /// Samples every MP3 decoder holds back, which LAME's delay and padding don't count.
    static let decoderDelay = 529
    /// The LAME tag stores delay and padding in 12 bits each.
    static let maximumGap = 4095

    static func trim(_ url: URL, from start: TimeInterval, to end: TimeInterval, outputURL: URL,
                     progress: (@Sendable (Double) -> Void)?) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let stream = try MP3Stream(data)
        let frames = stream.frames
        let samplesPerFrame = stream.samplesPerFrame
        let sampleRate = Double(stream.sampleRate)

        // Samples are counted from the first one players play
        let skipBegin = stream.skipBegin
        let validSamples = frames.count * samplesPerFrame - skipBegin - stream.skipEnd
        // The LAME tag can't keep the decoder's own lead-in, so a file without a tag starts after it at the
        // earliest. Those first 12 ms or so are silence the encoder added.
        let earliestStart = max(0, decoderDelay - skipBegin)
        let startSample = max(earliestStart, Int((start * sampleRate).rounded()))
        let endSample = min(validSamples, Int((end * sampleRate).rounded()))
        guard endSample > startSample else { throw AudioglotError.invalidTrimRange }

        // Positions in the decoder's output, which includes the samples it skips
        let outputStart = startSample + skipBegin
        let outputEnd = endSample + skipBegin
        let firstWantedFrame = outputStart / samplesPerFrame

        // The frame before the first wanted one overlaps it, so it must decode correctly too, which needs the
        // frames holding the bytes it borrows
        var firstFrame = max(0, firstWantedFrame - 1)
        if firstWantedFrame > 0 {
            var borrowed = frames[firstFrame].mainDataBegin
            while borrowed > 0 && firstFrame > 0 {
                firstFrame -= 1
                borrowed -= frames[firstFrame].mainDataSize
            }
        }
        // The delay can't be negative, since the decoder always holds back its own samples
        while outputStart - firstFrame * samplesPerFrame < decoderDelay && firstFrame > 0 {
            firstFrame -= 1
        }
        let endFrame = min(frames.count, (outputEnd - 1) / samplesPerFrame + 1)

        let delay = outputStart - firstFrame * samplesPerFrame - decoderDelay
        let padding = (endFrame - firstFrame) * samplesPerFrame - delay - (endSample - startSample)
        guard (0...maximumGap).contains(delay), (0...maximumGap).contains(padding) else {
            throw Unsupported(reason: "delay \(delay) or padding \(padding) doesn't fit the LAME tag")
        }

        let copied = Array(frames[firstFrame..<endFrame])
        let audioRange = copied.first!.offset..<(copied.last!.offset + copied.last!.length)
        let infoFrame = stream.makeInfoFrame(for: copied, audioData: data[audioRange], delay: delay,
                                             padding: padding)

        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }
        progress?(0)
        try handle.write(contentsOf: infoFrame)
        let chunkSize = 1 << 20
        var position = audioRange.lowerBound
        while position < audioRange.upperBound {
            try Task.checkCancellation()
            let chunkEnd = min(audioRange.upperBound, position + chunkSize)
            try handle.write(contentsOf: data[position..<chunkEnd])
            position = chunkEnd
            progress?(Double(position - audioRange.lowerBound) / Double(audioRange.count))
        }
        progress?(1)
    }
}

// MARK: - Reading the stream

/// The frames of an MP3 file and its LAME tag.
struct MP3Stream {

    struct Frame {
        let offset: Int
        let length: Int
        /// How many bytes of main data this frame borrows from the frames before it.
        let mainDataBegin: Int
        /// How many bytes of main data this frame holds, which later frames may borrow.
        let mainDataSize: Int
        let bitrateIndex: Int
    }

    let frames: [Frame]
    let header: MP3FrameHeader
    var samplesPerFrame: Int { header.samplesPerFrame }
    var sampleRate: Int { header.sampleRate }
    /// How many samples players drop from the start and end of the decoded frames: those the LAME tag gives,
    /// or none without one.
    let skipBegin: Int
    let skipEnd: Int
    /// The 36 bytes of the LAME tag, if the file has one.
    let lameTag: [UInt8]?
    let quality: [UInt8]?

    /// Bytes from the Xing tag to the LAME tag, when every optional field is present.
    static let xingLength = 120
    static let lameTagLength = 36

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        var offset = Self.skipID3v2(bytes)
        guard let firstOffset = Self.findFirstFrame(bytes, from: offset),
              let first = MP3FrameHeader(bytes, at: firstOffset) else {
            throw MP3FrameTrimmer.Unsupported(reason: "no MPEG Layer III frames")
        }
        header = first

        // A Xing or Info frame in front of the audio holds the LAME tag, which says where the audio starts
        var audioOffset = firstOffset
        var xingFrameCount: Int?
        var lameTag: [UInt8]?
        var quality: [UInt8]?
        let xingOffset = firstOffset + 4 + (first.hasCRC ? 2 : 0) + first.sideInfoSize
        if xingOffset + 8 <= bytes.count, let marker = String(bytes: bytes[xingOffset..<(xingOffset + 4)],
                                                              encoding: .ascii),
           marker == "Xing" || marker == "Info" {
            audioOffset = firstOffset + first.length
            let flags = Self.uint32(bytes, at: xingOffset + 4)
            var field = xingOffset + 8
            if flags & 1 != 0 {
                xingFrameCount = Int(Self.uint32(bytes, at: field))
                field += 4
            }
            if flags & 2 != 0 { field += 4 }
            if flags & 4 != 0 { field += 100 }
            if flags & 8 != 0, field + 4 <= audioOffset {
                quality = Array(bytes[field..<(field + 4)])
                field += 4
            }
            let tagEnd = field + Self.lameTagLength
            if tagEnd <= audioOffset,
               bytes[field..<(field + 4)].allSatisfy({ (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) }) {
                lameTag = Array(bytes[field..<tagEnd])
            } else {
                // Decoders disagree on whether to read gapless info from such a frame, so where the audio
                // starts is unclear
                throw MP3FrameTrimmer.Unsupported(reason: "Xing frame without a LAME tag")
            }
        } else if firstOffset + 40 <= bytes.count,
                  bytes[(firstOffset + 36)..<(firstOffset + 40)].elementsEqual("VBRI".utf8) {
            throw MP3FrameTrimmer.Unsupported(reason: "VBRI header")
        }
        if let lameTag {
            let delay = Int(lameTag[21]) << 4 | Int(lameTag[22]) >> 4
            let padding = Int(lameTag[22] & 0x0F) << 8 | Int(lameTag[23])
            skipBegin = delay + MP3FrameTrimmer.decoderDelay
            skipEnd = max(0, padding - MP3FrameTrimmer.decoderDelay)
        } else {
            skipBegin = 0
            skipEnd = 0
        }
        self.lameTag = lameTag
        self.quality = quality

        // The audio frames, which must all share the first frame's version and sample rate
        var frames: [Frame] = []
        offset = audioOffset
        while let frame = MP3FrameHeader(bytes, at: offset), offset + frame.length <= bytes.count,
              frame.version == first.version, frame.sampleRate == first.sampleRate {
            let sideInfoOffset = offset + 4 + (frame.hasCRC ? 2 : 0)
            let mainDataBegin = frame.version == .mpeg1
                ? Int(bytes[sideInfoOffset]) << 1 | Int(bytes[sideInfoOffset + 1]) >> 7
                : Int(bytes[sideInfoOffset])
            frames.append(Frame(offset: offset, length: frame.length, mainDataBegin: mainDataBegin,
                                mainDataSize: frame.length - (sideInfoOffset - offset) - frame.sideInfoSize,
                                bitrateIndex: frame.bitrateIndex))
            offset += frame.length
        }
        // Anything after the frames should be tags. Other data means frames were missed, so the counts would be off.
        guard !frames.isEmpty, xingFrameCount == nil || xingFrameCount == frames.count,
              Self.isTrailingTag(bytes, at: offset) else {
            throw MP3FrameTrimmer.Unsupported(reason: "unreadable data after frame \(frames.count)")
        }
        self.frames = frames
    }

    /// Builds the Xing frame with the LAME tag that goes in front of `copied`.
    func makeInfoFrame(for copied: [Frame], audioData: Data, delay: Int, padding: Int) -> Data {
        let isConstantBitrate = Set(copied.map(\.bitrateIndex)).count == 1
        let tagOffset = 4 + header.sideInfoSize
        let needed = tagOffset + Self.xingLength + Self.lameTagLength
        let bitrateIndex = (isConstantBitrate && header.frameLength(bitrateIndex: copied[0].bitrateIndex) >= needed)
            ? copied[0].bitrateIndex
            : (1...14).first { header.frameLength(bitrateIndex: $0) >= needed } ?? 14
        let length = header.frameLength(bitrateIndex: bitrateIndex)
        let totalBytes = length + audioData.count

        var frame = [UInt8](repeating: 0, count: length)
        frame[0] = 0xFF
        frame[1] = header.bytes[1] | 0x01 // no CRC
        frame[2] = UInt8(bitrateIndex << 4) | (header.bytes[2] & 0x0C) | (header.bytes[2] & 0x01) // no padding
        frame[3] = header.bytes[3] & 0xCF // no mode extension

        var position = tagOffset
        func write(_ values: [UInt8]) {
            frame.replaceSubrange(position..<(position + values.count), with: values)
            position += values.count
        }
        // "Xing" even at a constant bitrate: Core Audio estimates the length of an "Info" file from its size,
        // which can come out a frame long, but takes a Xing frame's count as given
        write(Array("Xing".utf8))
        write(Self.bigEndian(UInt32(0x0F)))
        write(Self.bigEndian(UInt32(copied.count)))
        write(Self.bigEndian(UInt32(totalBytes)))
        // Seek table: where each percent of the duration starts, as a fraction of the file out of 256
        let firstOffset = copied[0].offset
        write((0..<100).map { percent in
            let frameOffset = copied[percent * copied.count / 100].offset - firstOffset + length
            return UInt8(min(255, frameOffset * 256 / totalBytes))
        })
        write(quality ?? [0, 0, 0, 0])

        var tag = lameTag ?? Self.newLAMETag
        // Replay gain was measured on the untrimmed audio, so it's left unset
        tag.replaceSubrange(11..<19, with: [UInt8](repeating: 0, count: 8))
        tag[21] = UInt8(delay >> 4)
        tag[22] = UInt8((delay & 0x0F) << 4) | UInt8(padding >> 8)
        tag[23] = UInt8(padding & 0xFF)
        tag[25] = 0
        tag.replaceSubrange(28..<32, with: Self.bigEndian(UInt32(totalBytes)))
        tag.replaceSubrange(32..<34, with: Self.bigEndian(Self.crc16(audioData)))
        write(Array(tag[0..<34]))
        write(Self.bigEndian(Self.crc16(frame[0..<position])))
        return Data(frame)
    }

    /// A LAME tag for files that had none: just the version, which players look for before reading the rest.
    private static let newLAMETag = Array("LAME3.100".utf8) + [UInt8](repeating: 0, count: lameTagLength - 9)

    // MARK: Helpers

    private static func skipID3v2(_ bytes: [UInt8]) -> Int {
        var offset = 0
        while offset + 10 <= bytes.count, bytes[offset] == 0x49, bytes[offset + 1] == 0x44, bytes[offset + 2] == 0x33 {
            let size = bytes[(offset + 6)..<(offset + 10)].reduce(0) { $0 << 7 | Int($1 & 0x7F) }
            offset += 10 + size + (bytes[offset + 5] & 0x10 != 0 ? 10 : 0)
        }
        return offset
    }

    /// The first frame header followed by another one, so stray sync bytes in leftover data aren't taken for it.
    private static func findFirstFrame(_ bytes: [UInt8], from start: Int) -> Int? {
        let limit = min(bytes.count - 4, start + 65536)
        guard start < limit else { return nil }
        for offset in start..<limit where bytes[offset] == 0xFF {
            guard let header = MP3FrameHeader(bytes, at: offset) else { continue }
            let next = offset + header.length
            if next == bytes.count || MP3FrameHeader(bytes, at: next) != nil {
                return offset
            }
        }
        return nil
    }

    private static func isTrailingTag(_ bytes: [UInt8], at offset: Int) -> Bool {
        let remaining = bytes.count - offset
        guard remaining > 0 else { return true }
        for marker in ["TAG", "APETAGEX", "LYRICSBEGIN", "ID3"] where remaining >= marker.utf8.count {
            if bytes[offset..<(offset + marker.utf8.count)].elementsEqual(marker.utf8) { return true }
        }
        if let header = MP3FrameHeader(bytes, at: offset) {
            // A last frame cut short is fine; a frame in another format means the stream changed partway
            return offset + header.length > bytes.count
        }
        // A few stray bytes
        return remaining < 2048
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func bigEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    /// The CRC-16 the LAME tag uses (polynomial 0x8005, reflected, starting from 0).
    static func crc16<C: Collection>(_ bytes: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }
}

/// An MPEG audio Layer III frame header.
struct MP3FrameHeader: Equatable {

    enum Version: Equatable {
        case mpeg1, mpeg2, mpeg25
    }

    let bytes: [UInt8]
    let version: Version
    let bitrateIndex: Int
    let sampleRate: Int
    let hasPadding: Bool
    let hasCRC: Bool
    let isMono: Bool

    private static let mpeg1Bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
    private static let mpeg2Bitrates = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]

    /// Reads a header at `offset`, or nil if there isn't a valid Layer III one there. Free-format frames aren't
    /// accepted, since their length can't be told from the header.
    init?(_ bytes: [UInt8], at offset: Int) {
        guard offset >= 0, offset + 4 <= bytes.count,
              bytes[offset] == 0xFF, bytes[offset + 1] & 0xE0 == 0xE0 else { return nil }
        let header = Array(bytes[offset..<(offset + 4)])
        switch header[1] >> 3 & 0x03 {
        case 3: version = .mpeg1
        case 2: version = .mpeg2
        case 0: version = .mpeg25
        default: return nil
        }
        guard header[1] >> 1 & 0x03 == 1 else { return nil } // Layer III
        bitrateIndex = Int(header[2] >> 4)
        guard (1...14).contains(bitrateIndex) else { return nil }
        let sampleRateIndex = Int(header[2] >> 2 & 0x03)
        guard sampleRateIndex < 3 else { return nil }
        let rates = switch version {
        case .mpeg1: [44100, 48000, 32000]
        case .mpeg2: [22050, 24000, 16000]
        case .mpeg25: [11025, 12000, 8000]
        }
        sampleRate = rates[sampleRateIndex]
        hasPadding = header[2] & 0x02 != 0
        hasCRC = header[1] & 0x01 == 0
        isMono = header[3] >> 6 == 3
        self.bytes = header
    }

    var samplesPerFrame: Int { version == .mpeg1 ? 1152 : 576 }

    var sideInfoSize: Int {
        switch (version == .mpeg1, isMono) {
        case (true, true): 17
        case (true, false): 32
        case (false, true): 9
        case (false, false): 17
        }
    }

    var length: Int { frameLength(bitrateIndex: bitrateIndex) + (hasPadding ? 1 : 0) }

    /// The length of an unpadded frame like this one at another bitrate.
    func frameLength(bitrateIndex: Int) -> Int {
        let kbps = (version == .mpeg1 ? Self.mpeg1Bitrates : Self.mpeg2Bitrates)[bitrateIndex]
        return (version == .mpeg1 ? 144_000 : 72_000) * kbps / sampleRate
    }
}
