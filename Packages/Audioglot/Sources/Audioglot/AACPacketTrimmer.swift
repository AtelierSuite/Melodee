import AudioToolbox
import Foundation

/// Trims AAC-LC in M4A by copying packets, so the audio is never re-encoded.
///
/// AAC packets hold 1024 frames each, and decoding one needs the packet before it. The trimmer copies the packets
/// covering the range plus a couple of packets of pre-roll, then records in the file's packet table how many frames
/// at the start (priming) and end (remainder) the decoder should drop. Players that honour the packet table, as
/// Core Audio and SFBAudioEngine do, play exactly the requested frames.
///
/// Files are written with Core Audio's `AudioFile`, since SFBAudioEngine can't open M4A files written by
/// `AVAssetExportSession`.
enum AACPacketTrimmer {

    /// Packets copied before the first wanted frame, so the decoder has warmed up by the time it reaches it.
    static let prerollPackets: Int64 = 2

    static func canTrim(_ url: URL) -> Bool {
        guard let file = try? AudioFileHandle(url: url) else { return false }
        return (try? file.dataFormat().mFormatID) == kAudioFormatMPEG4AAC
    }

    static func trim(_ url: URL, from start: TimeInterval, to end: TimeInterval, outputURL: URL,
                     progress: (@Sendable (Double) -> Void)?) throws {
        let source = try AudioFileHandle(url: url)
        var format = try source.dataFormat()
        let framesPerPacket = Int64(format.mFramesPerPacket)
        guard format.mFormatID == kAudioFormatMPEG4AAC, framesPerPacket > 0 else {
            throw AudioglotError.trimNotSupported("AAC")
        }
        let packetCount = try source.packetCount()
        let sourceTable = source.packetTableInfo()
        let sourcePriming = Int64(sourceTable?.mPrimingFrames ?? 0)
        let validFrames = sourceTable.map { $0.mNumberValidFrames }
            ?? packetCount * framesPerPacket - sourcePriming

        // Frames are counted from the first audible frame, as players report them
        let startFrame = max(0, Int64((start * format.mSampleRate).rounded()))
        let endFrame = min(validFrames, Int64((end * format.mSampleRate).rounded()))
        guard endFrame > startFrame else { throw AudioglotError.invalidTrimRange }

        // Packets holding those frames, counted in the encoded stream, which starts with the priming frames
        let firstPacket = max(0, (startFrame + sourcePriming) / framesPerPacket - prerollPackets)
        let lastPacket = min(packetCount, (endFrame + sourcePriming + framesPerPacket - 1) / framesPerPacket + 1)
        let priming = startFrame + sourcePriming - firstPacket * framesPerPacket
        let wantedFrames = endFrame - startFrame

        let destination = try AudioFileHandle(creating: outputURL, format: &format)
        // Tell the writer how long the file will be, so it sizes the index instead of leaving tens of
        // kilobytes of padding for it to grow into
        var reserveDuration = Double((lastPacket - firstPacket) * framesPerPacket) / format.mSampleRate
        AudioFileSetProperty(destination.id, kAudioFilePropertyReserveDuration,
                             UInt32(MemoryLayout<Float64>.size), &reserveDuration)
        if let cookie = source.magicCookie() {
            try destination.setMagicCookie(cookie)
        }

        let maxPacketSize = try source.maximumPacketSize()
        let chunkPackets: UInt32 = 256
        var buffer = [UInt8](repeating: 0, count: Int(maxPacketSize) * Int(chunkPackets))
        var descriptions = [AudioStreamPacketDescription](repeating: AudioStreamPacketDescription(),
                                                          count: Int(chunkPackets))
        var readPacket = firstPacket
        var writePacket: Int64 = 0
        let totalPackets = Double(lastPacket - firstPacket)
        progress?(0)
        while readPacket < lastPacket {
            try Task.checkCancellation()
            var packets = UInt32(min(Int64(chunkPackets), lastPacket - readPacket))
            var bytes = UInt32(buffer.count)
            let readStatus = AudioFileReadPacketData(source.id, false, &bytes, &descriptions, readPacket,
                                                     &packets, &buffer)
            guard readStatus == noErr || readStatus == kAudioFileEndOfFileError, packets > 0 else { break }
            let writeStatus = AudioFileWritePackets(destination.id, false, bytes, descriptions, writePacket,
                                                    &packets, buffer)
            guard writeStatus == noErr else { throw osStatusError(writeStatus) }
            readPacket += Int64(packets)
            writePacket += Int64(packets)
            progress?(Double(readPacket - firstPacket) / totalPackets)
        }

        // Drop the pre-roll and the tail of the last packet, so exactly the wanted frames play
        let writtenFrames = writePacket * framesPerPacket
        guard writtenFrames > priming else { throw AudioglotError.invalidTrimRange }
        let playableFrames = min(wantedFrames, writtenFrames - priming)
        var table = AudioFilePacketTableInfo(
            mNumberValidFrames: playableFrames,
            mPrimingFrames: Int32(priming),
            mRemainderFrames: Int32(writtenFrames - priming - playableFrames)
        )
        try destination.setPacketTableInfo(&table)
        try destination.close()
        progress?(1)
    }

    static func osStatusError(_ status: OSStatus) -> Error {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}

/// A thin wrapper that closes the `AudioFileID` when it's no longer used.
final class AudioFileHandle {

    let id: AudioFileID
    private var isClosed = false

    init(url: URL) throws {
        var file: AudioFileID?
        let status = AudioFileOpenURL(url as CFURL, .readPermission, 0, &file)
        guard status == noErr, let file else { throw AACPacketTrimmer.osStatusError(status) }
        id = file
    }

    init(creating url: URL, format: inout AudioStreamBasicDescription) throws {
        var file: AudioFileID?
        let status = AudioFileCreateWithURL(url as CFURL, kAudioFileM4AType, &format, [], &file)
        guard status == noErr, let file else { throw AACPacketTrimmer.osStatusError(status) }
        id = file
    }

    deinit {
        if !isClosed {
            AudioFileClose(id)
        }
    }

    func close() throws {
        guard !isClosed else { return }
        isClosed = true
        let status = AudioFileClose(id)
        guard status == noErr else { throw AACPacketTrimmer.osStatusError(status) }
    }

    func dataFormat() throws -> AudioStreamBasicDescription {
        try property(kAudioFilePropertyDataFormat, AudioStreamBasicDescription())
    }

    func packetCount() throws -> Int64 {
        try property(kAudioFilePropertyAudioDataPacketCount, UInt64(0)).toInt64
    }

    func maximumPacketSize() throws -> UInt32 {
        try property(kAudioFilePropertyPacketSizeUpperBound, UInt32(0))
    }

    func packetTableInfo() -> AudioFilePacketTableInfo? {
        try? property(kAudioFilePropertyPacketTableInfo, AudioFilePacketTableInfo())
    }

    func setPacketTableInfo(_ table: inout AudioFilePacketTableInfo) throws {
        let status = AudioFileSetProperty(id, kAudioFilePropertyPacketTableInfo,
                                          UInt32(MemoryLayout<AudioFilePacketTableInfo>.size), &table)
        guard status == noErr else { throw AACPacketTrimmer.osStatusError(status) }
    }

    func magicCookie() -> [UInt8]? {
        var size: UInt32 = 0
        guard AudioFileGetPropertyInfo(id, kAudioFilePropertyMagicCookieData, &size, nil) == noErr, size > 0 else {
            return nil
        }
        var cookie = [UInt8](repeating: 0, count: Int(size))
        guard AudioFileGetProperty(id, kAudioFilePropertyMagicCookieData, &size, &cookie) == noErr else { return nil }
        return cookie
    }

    func setMagicCookie(_ cookie: [UInt8]) throws {
        var cookie = cookie
        let status = AudioFileSetProperty(id, kAudioFilePropertyMagicCookieData, UInt32(cookie.count), &cookie)
        guard status == noErr else { throw AACPacketTrimmer.osStatusError(status) }
    }

    private func property<T>(_ propertyID: AudioFilePropertyID, _ initial: T) throws -> T {
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioFileGetProperty(id, propertyID, &size, &value)
        guard status == noErr else { throw AACPacketTrimmer.osStatusError(status) }
        return value
    }
}

private extension UInt64 {
    var toInt64: Int64 { Int64(clamping: self) }
}
