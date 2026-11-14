import Foundation

/// Trims Ogg Opus and Ogg Vorbis by copying packets, so the audio is never re-encoded.
///
/// Packets are copied as they are and laid out on new Ogg pages, keeping the stream's headers. Where each copied
/// packet ends is given by the pages' granule positions, which also say which samples players should drop:
/// - **Opus**: the copy starts half a second early so the decoder settles, and the header's pre-skip drops
///   everything before the cut. The last page's granule position drops what follows the end.
/// - **Vorbis**: a packet only needs the one before it, so the copy starts one packet early. The first audio page's
///   granule position is set lower than the samples on it, which tells the decoder to drop the difference from the
///   start, and the last page's drops what follows the end.
///
/// Streams the trimmer can't follow, such as chained or multiplexed files, throw ``Unsupported`` before anything is
/// written, so the caller can re-encode instead.
enum OggPacketTrimmer {

    /// The file can't be trimmed by copying packets. Nothing has been written.
    struct Unsupported: Error {
        let reason: String
    }

    /// Samples of Opus decoded before the cut and dropped, so the decoder has settled by the time it reaches it.
    /// RFC 7845 asks for at least 80 ms, but the decoder's output still differs audibly for a while after that; by
    /// half a second it matches the untrimmed file.
    static let opusPreroll = 24000

    static func trim(_ url: URL, from start: TimeInterval, to end: TimeInterval, outputURL: URL,
                     progress: (@Sendable (Double) -> Void)?) throws {
        let bytes = [UInt8](try Data(contentsOf: url, options: .alwaysMapped))
        let stream = try OggStream(bytes)
        let audio = try OggAudio(stream)

        // Samples are counted from the first one players play, and granule positions from the start of the stream
        let startSample = max(0, Int((start * audio.sampleRate).rounded()))
        let endSample = min(audio.playableSamples, Int((end * audio.sampleRate).rounded()))
        guard endSample > startSample else { throw AudioglotError.invalidTrimRange }
        let startPosition = startSample + audio.playbackOffset
        let endPosition = endSample + audio.playbackOffset
        let ends = audio.packetEnds
        guard let lastPacket = ends.firstIndex(where: { $0 >= endPosition }) else {
            throw Unsupported(reason: "the end lies past the last packet")
        }

        var writer = OggWriter(serial: stream.serial)
        var header = stream.packets[0]
        let firstPacket: Int
        let base: Int
        let finalGranule: Int
        switch audio.codec {
        case .opus:
            // Start where the pre-roll begins, and have the pre-skip drop everything up to the cut
            let prerollPosition = startPosition - opusPreroll
            firstPacket = ends.indices.last { ends[$0] - audio.durations[$0] <= prerollPosition } ?? 0
            base = ends[firstPacket] - audio.durations[firstPacket]
            let preSkip = startPosition - base
            guard preSkip <= Int(UInt16.max) else { throw Unsupported(reason: "pre-skip of \(preSkip)") }
            header[10] = UInt8(preSkip & 0xFF)
            header[11] = UInt8(preSkip >> 8)
            finalGranule = endPosition - base
        case .vorbis:
            // The packet ending at or before the cut produces no samples of its own, but the next one needs it.
            // Positions count from the cut, so the first page's granule position drops what comes before it.
            firstPacket = ends.indices.last { ends[$0] <= startPosition } ?? 0
            base = startPosition
            finalGranule = endPosition - base
            // The first audio page holds the first two packets, and must not also be the last page
            guard lastPacket >= firstPacket + 2 else {
                throw Unsupported(reason: "too few packets to trim the start")
            }
        }

        writer.add(header, granule: 0)
        writer.flush(isFirst: true)
        for packet in stream.packets[1..<audio.headerCount] {
            writer.add(packet, granule: 0)
        }
        writer.flush()

        progress?(0)
        let count = lastPacket - firstPacket + 1
        for (copied, index) in (firstPacket...lastPacket).enumerated() {
            try Task.checkCancellation()
            let granule = index == lastPacket ? finalGranule : ends[index] - base
            writer.add(stream.packets[audio.headerCount + index], granule: granule)
            // A Vorbis page with fewer samples than packets only trims the start when it isn't also the last page
            if audio.codec == .vorbis && copied == 1 && index != lastPacket {
                writer.flush()
            } else if index != lastPacket {
                writer.flushIfFull()
            }
            progress?(Double(copied + 1) / Double(count))
        }
        writer.flush(isLast: true)

        try writer.output.write(to: outputURL, options: .withoutOverwriting)
        progress?(1)
    }
}

// MARK: - Reading the stream

/// The packets of a single logical Ogg stream, and where its pages put granule positions.
struct OggStream {

    struct Page {
        let granule: Int64
        /// The last packet that ends on this page, if any.
        let lastPacket: Int?
        let isLast: Bool
    }

    let serial: UInt32
    let packets: [[UInt8]]
    let pages: [Page]

    init(_ bytes: [UInt8]) throws {
        var offset = 0
        var serial: UInt32?
        var packets: [[UInt8]] = []
        var pages: [Page] = []
        var pending: [UInt8] = []
        var pendingStarted = false

        while offset < bytes.count {
            guard offset + 27 <= bytes.count, bytes[offset..<(offset + 4)].elementsEqual("OggS".utf8),
                  bytes[offset + 4] == 0 else {
                throw OggPacketTrimmer.Unsupported(reason: "not Ogg data at \(offset)")
            }
            let flags = bytes[offset + 5]
            let granule = Int64(bitPattern: Self.littleEndian(bytes, at: offset + 6, count: 8))
            let pageSerial = UInt32(Self.littleEndian(bytes, at: offset + 14, count: 4))
            let segmentCount = Int(bytes[offset + 26])
            var dataOffset = offset + 27 + segmentCount
            guard dataOffset <= bytes.count else { throw OggPacketTrimmer.Unsupported(reason: "page cut short") }
            let lacing = bytes[(offset + 27)..<dataOffset]
            guard dataOffset + lacing.reduce(0, { $0 + Int($1) }) <= bytes.count else {
                throw OggPacketTrimmer.Unsupported(reason: "page cut short")
            }

            if let serial {
                guard pageSerial == serial else {
                    throw OggPacketTrimmer.Unsupported(reason: "more than one stream")
                }
            } else {
                guard flags & 0x02 != 0 else { throw OggPacketTrimmer.Unsupported(reason: "no first page") }
                serial = pageSerial
            }
            // A continued page must continue a packet, and a page that isn't continued must not leave one hanging
            guard (flags & 0x01 != 0) == pendingStarted else {
                throw OggPacketTrimmer.Unsupported(reason: "broken packet across pages")
            }

            var lastPacket: Int?
            for length in lacing {
                pending.append(contentsOf: bytes[dataOffset..<(dataOffset + Int(length))])
                pendingStarted = true
                dataOffset += Int(length)
                if length < 255 {
                    packets.append(pending)
                    pending = []
                    pendingStarted = false
                    lastPacket = packets.count - 1
                }
            }
            let isLast = flags & 0x04 != 0
            pages.append(Page(granule: granule, lastPacket: lastPacket, isLast: isLast))
            offset = dataOffset
            if isLast { break }
        }
        // Anything after the last page would be a chained stream
        guard let serial, offset == bytes.count, !pendingStarted else {
            throw OggPacketTrimmer.Unsupported(reason: "chained or unfinished stream")
        }
        self.serial = serial
        self.packets = packets
        self.pages = pages
    }

    static func littleEndian(_ bytes: [UInt8], at offset: Int, count: Int) -> UInt64 {
        (0..<count).reduce(0) { $0 | UInt64(bytes[offset + $1]) << (8 * $1) }
    }
}

/// The codec of an Ogg stream and where each of its audio packets ends.
struct OggAudio {

    enum Codec {
        case opus, vorbis
    }

    let codec: Codec
    let headerCount: Int
    let sampleRate: Double
    /// Samples each audio packet adds.
    let durations: [Int]
    /// The granule position at the end of each audio packet.
    let packetEnds: [Int]
    /// The granule position of the first sample players play: Opus's pre-skip, or 0 for Vorbis.
    let playbackOffset: Int
    let playableSamples: Int

    init(_ stream: OggStream) throws {
        let packets = stream.packets
        guard let first = packets.first else { throw OggPacketTrimmer.Unsupported(reason: "empty stream") }
        if first.count >= 19, first[0..<8].elementsEqual("OpusHead".utf8) {
            guard packets.count > 2, packets[1].starts(with: "OpusTags".utf8) else {
                throw OggPacketTrimmer.Unsupported(reason: "no OpusTags")
            }
            codec = .opus
            headerCount = 2
            sampleRate = 48000 // Opus granule positions always count 48 kHz samples
            playbackOffset = Int(first[10]) | Int(first[11]) << 8
            durations = try packets[2...].map { try Self.opusDuration(of: $0) }
        } else if first.count >= 30, first[0] == 1, first[1..<7].elementsEqual("vorbis".utf8) {
            guard packets.count > 3, packets[1].starts(with: [3] + "vorbis".utf8),
                  packets[2].starts(with: [5] + "vorbis".utf8) else {
                throw OggPacketTrimmer.Unsupported(reason: "no Vorbis headers")
            }
            codec = .vorbis
            headerCount = 3
            sampleRate = Double(OggStream.littleEndian(first, at: 12, count: 4))
            playbackOffset = 0
            let blockSizes = (1 << Int(first[28] & 0x0F), 1 << Int(first[28] >> 4))
            durations = try Self.vorbisDurations(of: packets[3...], setup: packets[2], blockSizes: blockSizes)
        } else {
            throw OggPacketTrimmer.Unsupported(reason: "not Opus or Vorbis")
        }

        // Count from the start of the stream, then check the pages agree. A Vorbis stream trimmed at the start
        // has a first audio page with fewer samples than its packets hold, which moves every position back.
        var ends: [Int] = []
        var total = 0
        for duration in durations {
            total += duration
            ends.append(total)
        }
        var shift: Int?
        var lastGranule = 0
        for page in stream.pages {
            guard let packet = page.lastPacket, packet >= headerCount else { continue }
            let computed = ends[packet - headerCount]
            let granule = Int(page.granule)
            if shift == nil {
                shift = page.isLast ? 0 : granule - computed
                guard shift == 0 || (codec == .vorbis && shift! < 0) else {
                    throw OggPacketTrimmer.Unsupported(reason: "stream doesn't start at the beginning")
                }
            }
            if page.isLast {
                guard granule <= computed + shift!, granule >= 0 else {
                    throw OggPacketTrimmer.Unsupported(reason: "last page's position is off")
                }
            } else if granule != computed + shift! {
                throw OggPacketTrimmer.Unsupported(reason: "page positions don't match the packets")
            }
            lastGranule = granule
        }
        guard let shift, stream.pages.last?.isLast == true else {
            throw OggPacketTrimmer.Unsupported(reason: "no end of stream")
        }
        packetEnds = ends.map { $0 + shift }
        playableSamples = lastGranule - playbackOffset
        guard playableSamples > 0 else { throw OggPacketTrimmer.Unsupported(reason: "no audio") }
    }

    // MARK: Opus

    /// Samples in an Opus packet, at 48 kHz, read from its table of contents byte (RFC 6716, section 3.1).
    static func opusDuration(of packet: [UInt8]) throws -> Int {
        guard let toc = packet.first else { throw OggPacketTrimmer.Unsupported(reason: "empty Opus packet") }
        let config = Int(toc >> 3)
        let frameSize = switch config {
        case 0...11: [480, 960, 1920, 2880][config % 4]
        case 12...15: [480, 960][config % 2]
        default: [120, 240, 480, 960][config % 4]
        }
        let frames: Int
        switch toc & 0x03 {
        case 0: frames = 1
        case 1, 2: frames = 2
        default:
            guard packet.count > 1 else { throw OggPacketTrimmer.Unsupported(reason: "short Opus packet") }
            frames = Int(packet[1] & 0x3F)
        }
        return frameSize * frames
    }

    // MARK: Vorbis

    /// Samples each Vorbis packet adds: a quarter of its block plus a quarter of the previous one's. The first
    /// adds none, since it only starts the overlap.
    static func vorbisDurations(of packets: ArraySlice<[UInt8]>, setup: [UInt8],
                                blockSizes: (Int, Int)) throws -> [Int] {
        let modeBlockFlags = try vorbisModeBlockFlags(setup)
        let modeBits = bitCount(modeBlockFlags.count - 1)
        var previous: Int?
        return try packets.map { packet in
            guard let first = packet.first, first & 1 == 0 else {
                throw OggPacketTrimmer.Unsupported(reason: "not a Vorbis audio packet")
            }
            let mode = Int(first >> 1) & ((1 << modeBits) - 1)
            guard mode < modeBlockFlags.count else { throw OggPacketTrimmer.Unsupported(reason: "unknown mode") }
            let blockSize = modeBlockFlags[mode] ? blockSizes.1 : blockSizes.0
            defer { previous = blockSize }
            return previous.map { $0 / 4 + blockSize / 4 } ?? 0
        }
    }

    /// Whether each mode uses long blocks, read from the end of the setup header, as the modes come last.
    ///
    /// The codebooks before them would have to be decoded to read forwards, so this reads backwards from the framing
    /// bit, where each mode is 41 bits: a block flag, two 16-bit fields that are always 0, and a mapping number. The
    /// mode count, stored just before the modes, confirms how many there are.
    static func vorbisModeBlockFlags(_ setup: [UInt8]) throws -> [Bool] {
        func bit(_ position: Int) -> Int { Int(setup[position / 8] >> (position % 8)) & 1 }
        func value(at position: Int, bits: Int) -> Int {
            (0..<bits).reduce(0) { $0 | bit(position + $1) << $1 }
        }
        guard let framingBit = (0..<(setup.count * 8)).last(where: { bit($0) == 1 }) else {
            throw OggPacketTrimmer.Unsupported(reason: "no Vorbis framing bit")
        }
        var candidates = 0
        while candidates < 64 {
            let start = framingBit - 41 * (candidates + 1)
            guard start >= 0, value(at: start + 1, bits: 16) == 0, value(at: start + 17, bits: 16) == 0,
                  value(at: start + 33, bits: 8) < 64 else { break }
            candidates += 1
        }
        for count in stride(from: candidates, through: 1, by: -1) {
            let countField = framingBit - 41 * count - 6
            guard countField >= 0, value(at: countField, bits: 6) == count - 1 else { continue }
            return (0..<count).map { bit(framingBit - 41 * (count - $0)) == 1 }
        }
        throw OggPacketTrimmer.Unsupported(reason: "couldn't read the Vorbis modes")
    }

    /// The number of bits needed to hold `value`, as Vorbis's `ilog`.
    static func bitCount(_ value: Int) -> Int {
        value > 0 ? Int.bitWidth - value.leadingZeroBitCount : 0
    }
}

// MARK: - Writing the stream

/// Lays packets out on Ogg pages.
struct OggWriter {

    /// Pages are closed once they hold this much, as libogg does.
    static let targetPageSize = 4096

    let serial: UInt32
    private(set) var output = Data()
    private var sequence: UInt32 = 0
    private var lacing: [UInt8] = []
    private var body: [UInt8] = []
    private var granule: Int64 = -1
    private var isContinued = false

    init(serial: UInt32) {
        self.serial = serial
    }

    /// Adds a packet whose end is at `granule`, spilling onto new pages if it doesn't fit.
    mutating func add(_ packet: [UInt8], granule packetGranule: Int) {
        var remaining = packet[...]
        while true {
            let needed = remaining.count / 255 + 1
            let room = 255 - lacing.count
            if needed <= room {
                lacing.append(contentsOf: [UInt8](repeating: 255, count: remaining.count / 255))
                lacing.append(UInt8(remaining.count % 255))
                body.append(contentsOf: remaining)
                granule = Int64(packetGranule)
                return
            }
            // Fill this page with as much as fits, and continue the packet on the next
            lacing.append(contentsOf: [UInt8](repeating: 255, count: room))
            body.append(contentsOf: remaining.prefix(room * 255))
            remaining = remaining.dropFirst(room * 255)
            writePage(flags: 0)
            isContinued = true
        }
    }

    mutating func flushIfFull() {
        if body.count >= Self.targetPageSize {
            flush()
        }
    }

    mutating func flush(isFirst: Bool = false, isLast: Bool = false) {
        guard !lacing.isEmpty || isLast else { return }
        writePage(flags: (isFirst ? 0x02 : 0) | (isLast ? 0x04 : 0))
    }

    private mutating func writePage(flags: UInt8) {
        var page: [UInt8] = Array("OggS".utf8) + [0, flags | (isContinued ? 0x01 : 0)]
        page += (0..<8).map { UInt8(truncatingIfNeeded: UInt64(bitPattern: granule) >> (8 * $0)) }
        page += (0..<4).map { UInt8(truncatingIfNeeded: serial >> (8 * $0)) }
        page += (0..<4).map { UInt8(truncatingIfNeeded: sequence >> (8 * $0)) }
        page += [0, 0, 0, 0, UInt8(lacing.count)] + lacing + body
        let crc = Self.crc32(page)
        for index in 0..<4 {
            page[22 + index] = UInt8(truncatingIfNeeded: crc >> (8 * index))
        }
        output.append(contentsOf: page)
        sequence += 1
        lacing = []
        body = []
        granule = -1
        isContinued = false
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index) << 24) { crc, _ in crc & 0x8000_0000 != 0 ? crc << 1 ^ 0x04C1_1DB7 : crc << 1 }
    }

    /// Ogg's CRC-32: polynomial 0x04C11DB7, not reflected, starting from 0.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        bytes.reduce(0) { crc, byte in crc << 8 ^ crcTable[Int(crc >> 24 ^ UInt32(byte))] }
    }
}
