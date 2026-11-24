@preconcurrency import AVFoundation
import CoreMedia
import Foundation

/// Metadata describing an embedded subtitle or text track inside a video container.
public struct EmbeddedSubtitleTrackInfo: Identifiable, Hashable, Sendable {

    public let trackID: CMPersistentTrackID
    public let index: Int
    public let title: String?
    public let languageCode: String?
    public let extendedLanguageTag: String?
    public let mediaSubType: FourCharCode

    public var id: CMPersistentTrackID { trackID }

    public var effectiveLanguageCode: String? {
        extendedLanguageTag ?? languageCode
    }

    public var displayName: String {
        var parts: [String] = []
        if let title, !title.isEmpty {
            parts.append(title)
        }
        if let code = effectiveLanguageCode,
           let localized = Locale.current.localizedString(forIdentifier: code),
           !localized.isEmpty {
            let formatted = localized.capitalized(with: .current)
            if !parts.contains(where: { $0.caseInsensitiveCompare(formatted) == .orderedSame }) {
                parts.append(formatted)
            }
        }
        if parts.isEmpty {
            return "Track \(index + 1)"
        }
        return parts.joined(separator: " · ")
    }
}

extension Videoglot {

    /// Video container extensions into which Melodee can embed `tx3g` subtitle tracks without re-encoding.
    public static let subtitleEmbeddableExtensions: Set<String> = ["mp4", "m4v", "mov"]

    /// Lists embedded text/subtitle tracks in an AVFoundation-readable video container.
    public static func embeddedSubtitleTracks(in url: URL) async throws -> [EmbeddedSubtitleTrackInfo] {
        let asset = AVURLAsset(url: url)
        let textTracks = (try? await asset.loadTracks(withMediaType: .text)) ?? []
        let subtitleTracks = (try? await asset.loadTracks(withMediaType: .subtitle)) ?? []
        let combined = textTracks + subtitleTracks

        var infos: [EmbeddedSubtitleTrackInfo] = []
        for (index, track) in combined.enumerated() {
            let languageCode = try? await track.load(.languageCode)
            let extendedLanguageTag = try? await track.load(.extendedLanguageTag)
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            let subType = descriptions.first.map(CMFormatDescriptionGetMediaSubType) ?? 0
            let metadata = (try? await track.load(.metadata)) ?? []
            var title: String?
            for item in metadata {
                if item.commonKey == .commonKeyTitle || item.identifier == .quickTimeUserDataTrackName {
                    if let string = try? await item.load(.stringValue), !string.isEmpty {
                        title = string
                        break
                    }
                }
            }
            infos.append(EmbeddedSubtitleTrackInfo(
                trackID: track.trackID,
                index: index,
                title: title,
                languageCode: languageCode,
                extendedLanguageTag: extendedLanguageTag,
                mediaSubType: subType
            ))
        }
        return infos
    }

    /// Reads embedded lyrics metadata (`©lyr` / common lyrics key) from an AVFoundation-readable media container.
    public static func extractEmbeddedLyrics(from url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        for item in metadata {
            let keyString = (item.key as? String)?.lowercased()
            if item.identifier == .iTunesMetadataLyrics ||
                item.identifier == .id3MetadataUnsynchronizedLyric ||
                keyString == "©lyr" ||
                keyString == "uslt" ||
                keyString == "lyrics" {
                if let value = try? await item.load(.stringValue),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    /// Extracts all cues from an embedded text or subtitle track (`tx3g` / `wvtt` / plain text).
    public static func extractEmbeddedSubtitles(
        from url: URL,
        trackID: CMPersistentTrackID
    ) async throws -> TimedTextDocument {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTrack(withTrackID: trackID) else {
            throw VideoglotError.subtitleTrackNotFound
        }
        let info = (try? await embeddedSubtitleTracks(in: url).first { $0.trackID == trackID })
        let subType = info?.mediaSubType ?? 0

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw VideoglotError.subtitleReadFailed
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? VideoglotError.subtitleReadFailed
        }

        var cues: [TimedTextCue] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let duration = CMSampleBufferGetDuration(sampleBuffer)
            guard pts.isNumeric else { continue }
            let startSeconds = max(0, pts.seconds)
            let durationSeconds = (duration.isNumeric && duration.seconds > 0) ? duration.seconds : 3.0
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            ) == kCMBlockBufferNoErr, let dataPointer, totalLength > 0 else { continue }

            let payload = Data(bytes: dataPointer, count: totalLength)
            if let text = decodeSubtitleSample(payload, mediaSubType: subType),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cues.append(TimedTextCue(
                    startTime: startSeconds,
                    endTime: startSeconds + durationSeconds,
                    text: text
                ))
            }
        }

        var document = TimedTextDocument(
            cues: cues,
            title: info?.title,
            languageCode: info?.effectiveLanguageCode,
            isLyrics: false
        )
        document.sortCues()
        return document
    }

    /// Writes a copy of `sourceURL` to `outputURL` with `document` embedded as a `tx3g` subtitle track.
    /// Existing video, audio, and non-replaced subtitle tracks are copied losslessly without re-encoding.
    public static func embedSubtitles(
        _ document: TimedTextDocument,
        into sourceURL: URL,
        outputURL: URL,
        replacingTrackID: CMPersistentTrackID? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let sourceExtension = sourceURL.pathExtension.lowercased()
        guard subtitleEmbeddableExtensions.contains(sourceExtension),
              let format = VideoFormat(rawValue: sourceExtension) else {
            throw VideoglotError.subtitleEmbedNotSupported(sourceExtension)
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
            throw VideoglotError.outputExists(outputURL)
        }

        let asset = AVURLAsset(url: sourceURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration)
        let totalSeconds = max(duration.isNumeric ? duration.seconds : 0, 0.001)
        let allTracks = try await asset.load(.tracks)
        let videoTrack = allTracks.first { $0.mediaType == .video }
        let videoNaturalSize = (try? await videoTrack?.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: format.fileType)
        writer.metadata = (try? await asset.load(.metadata)) ?? []

        // Wire up lossless passthrough for every existing track except the one being replaced.
        var passthroughPairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        for track in allTracks {
            if let replacingTrackID, track.trackID == replacingTrackID {
                continue
            }
            guard track.mediaType == .video || track.mediaType == .audio ||
                  track.mediaType == .text || track.mediaType == .subtitle else {
                continue
            }
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            guard let formatHint = descriptions.first else { continue }
            guard writer.canApply(outputSettings: nil, forMediaType: track.mediaType) else { continue }

            let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            readerOutput.alwaysCopiesSampleData = false
            let writerInput = AVAssetWriterInput(
                mediaType: track.mediaType,
                outputSettings: nil,
                sourceFormatHint: formatHint
            )
            writerInput.expectsMediaDataInRealTime = false
            if track.mediaType == .video {
                writerInput.transform = (try? await track.load(.preferredTransform)) ?? .identity
            }
            writerInput.languageCode = try? await track.load(.languageCode)
            writerInput.extendedLanguageTag = try? await track.load(.extendedLanguageTag)
            writerInput.metadata = (try? await track.load(.metadata)) ?? []

            guard reader.canAdd(readerOutput), writer.canAdd(writerInput) else { continue }
            reader.add(readerOutput)
            writer.add(writerInput)
            passthroughPairs.append((readerOutput, writerInput))
        }

        let (subtitleInput, textFormatDescription) = try makeSubtitleInput(for: document, videoSize: videoNaturalSize)
        guard writer.canAdd(subtitleInput) else {
            throw VideoglotError.subtitleWriteFailed
        }
        writer.add(subtitleInput)

        guard reader.startReading() else {
            throw reader.error ?? VideoglotError.subtitleReadFailed
        }
        guard writer.startWriting() else {
            throw writer.error ?? VideoglotError.subtitleWriteFailed
        }
        writer.startSession(atSourceTime: .zero)
        progress?(0)

        var sortedDoc = document
        sortedDoc.sortCues()
        let subtitleSamples = buildTX3GSampleBuffers(
            cues: sortedDoc.cues,
            totalDuration: duration.isNumeric ? duration.seconds : 0,
            formatDescription: textFormatDescription
        )

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, pair) in passthroughPairs.enumerated() {
                    let reportProgress = index == 0 ? progress : nil
                    nonisolated(unsafe) let output = pair.0
                    nonisolated(unsafe) let input = pair.1
                    group.addTask {
                        try await Self.pumpTrack(
                            from: output,
                            to: input,
                            totalSeconds: totalSeconds,
                            progress: reportProgress
                        )
                    }
                }
                nonisolated(unsafe) let subInput = subtitleInput
                nonisolated(unsafe) let samples = subtitleSamples
                group.addTask {
                    try await Self.writeSubtitleSamples(samples, to: subInput)
                }
                try await group.waitForAll()
            }

            if reader.status == .failed {
                throw reader.error ?? VideoglotError.subtitleReadFailed
            }
            await writer.finishWriting()
            if writer.status != .completed {
                throw writer.error ?? VideoglotError.subtitleWriteFailed
            }
            progress?(1)
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    /// Writes an MP4 holding only `document` as a `tx3g` subtitle track, timed for a video `duration` seconds long.
    public static func writeSubtitleTrackFile(
        _ document: TimedTextDocument,
        duration: TimeInterval,
        videoSize: CGSize,
        to outputURL: URL
    ) async throws {
        guard !FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
            throw VideoglotError.outputExists(outputURL)
        }
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let (subtitleInput, textFormatDescription) = try makeSubtitleInput(for: document, videoSize: videoSize)
        guard writer.canAdd(subtitleInput) else {
            throw VideoglotError.subtitleWriteFailed
        }
        writer.add(subtitleInput)
        guard writer.startWriting() else {
            throw writer.error ?? VideoglotError.subtitleWriteFailed
        }
        writer.startSession(atSourceTime: .zero)

        var sortedDoc = document
        sortedDoc.sortCues()
        let samples = buildTX3GSampleBuffers(
            cues: sortedDoc.cues,
            totalDuration: duration,
            formatDescription: textFormatDescription
        )
        do {
            try await writeSubtitleSamples(samples, to: subtitleInput)
            await writer.finishWriting()
            if writer.status != .completed {
                throw writer.error ?? VideoglotError.subtitleWriteFailed
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func makeSubtitleInput(
        for document: TimedTextDocument,
        videoSize: CGSize
    ) throws -> (AVAssetWriterInput, CMFormatDescription) {
        let dimensions = CGSize(
            width: max(abs(videoSize.width), 320),
            height: max((abs(videoSize.height) * 0.15).rounded(), 60)
        )
        let formatDescription = try makeTX3GFormatDescription(dimensions: dimensions)
        let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: formatDescription)
        input.expectsMediaDataInRealTime = false
        input.marksOutputTrackAsEnabled = true
        input.naturalSize = dimensions
        input.mediaTimeScale = 600
        if let rawLang = document.languageCode?.trimmingCharacters(in: .whitespacesAndNewlines), !rawLang.isEmpty {
            input.extendedLanguageTag = rawLang
            if let iso3 = iso639_2TCode(for: rawLang) {
                input.languageCode = iso3
            }
        }
        if let title = document.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            let titleItem = AVMutableMetadataItem()
            titleItem.keySpace = .common
            titleItem.key = AVMetadataKey.commonKeyTitle as NSString
            titleItem.value = title as NSString
            input.metadata = [titleItem]
        }
        return (input, formatDescription)
    }

    // MARK: - Track pumping

    private final class PumpState: @unchecked Sendable {
        var finished = false
        var index = 0
    }

    private static func pumpTrack(
        from output: AVAssetReaderTrackOutput,
        to input: AVAssetWriterInput,
        totalSeconds: TimeInterval,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        nonisolated(unsafe) let readerOutput = output
        nonisolated(unsafe) let writerInput = input
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "Videoglot.TrackPump.\(UUID().uuidString)")
            let state = PumpState()
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData && !state.finished {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        if let progress, pts.isNumeric, totalSeconds > 0 {
                            progress(min(max(pts.seconds / totalSeconds, 0), 0.99))
                        }
                        if !writerInput.append(sampleBuffer) {
                            state.finished = true
                            writerInput.markAsFinished()
                            continuation.resume(throwing: VideoglotError.subtitleWriteFailed)
                            return
                        }
                    } else {
                        state.finished = true
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }

    private static func writeSubtitleSamples(
        _ samples: [CMSampleBuffer],
        to input: AVAssetWriterInput
    ) async throws {
        nonisolated(unsafe) let writerInput = input
        nonisolated(unsafe) let buffers = samples
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "Videoglot.SubtitleWrite.\(UUID().uuidString)")
            let state = PumpState()
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData && !state.finished {
                    if state.index < buffers.count {
                        let sample = buffers[state.index]
                        state.index += 1
                        if !writerInput.append(sample) {
                            state.finished = true
                            writerInput.markAsFinished()
                            continuation.resume(throwing: VideoglotError.subtitleWriteFailed)
                            return
                        }
                    } else {
                        state.finished = true
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }

    // MARK: - 3GPP Timed Text (tx3g) encoding & decoding

    /// Decodes a sample payload from `tx3g`, `wvtt` (WebVTT ISO-BMFF), or plain text tracks.
    static func decodeSubtitleSample(_ payload: Data, mediaSubType: FourCharCode) -> String? {
        // WebVTT in MP4 (`wvtt`) wraps cue payloads in `vttc` -> `payl` boxes
        if mediaSubType == fourCC("wvtt") {
            if let text = extractWebVTTPayload(from: payload) {
                return text
            }
        }
        // 3GPP Timed Text (`tx3g`) and QuickTime `text`: 2-byte big-endian UTF-8 byte length followed by text
        if payload.count >= 2 {
            let length = Int(payload[payload.startIndex]) << 8 | Int(payload[payload.startIndex + 1])
            if length == 0 {
                return nil
            }
            if 2 + length <= payload.count {
                let textData = payload[(payload.startIndex + 2)..<(payload.startIndex + 2 + length)]
                if let text = String(data: textData, encoding: .utf8) {
                    return text
                }
            }
        }
        return String(data: payload, encoding: .utf8)
    }

    private static func extractWebVTTPayload(from data: Data) -> String? {
        var offset = data.startIndex
        while offset + 8 <= data.endIndex {
            let size = readUInt32BE(data, at: offset)
            let boxEnd = size >= 8 ? min(offset + Int(size), data.endIndex) : data.endIndex
            let boxType = String(data: data[(offset + 4)..<(offset + 8)], encoding: .ascii)
            let content = data[(offset + 8)..<boxEnd]
            if boxType == "payl" {
                return String(data: content, encoding: .utf8)
            } else if boxType == "vttc" {
                if let nested = extractWebVTTPayload(from: content) {
                    return nested
                }
            }
            guard boxEnd > offset else { break }
            offset = boxEnd
        }
        return nil
    }

    private static func readUInt32BE(_ data: Data, at index: Data.Index) -> UInt32 {
        UInt32(data[index]) << 24 |
        UInt32(data[index + 1]) << 16 |
        UInt32(data[index + 2]) << 8 |
        UInt32(data[index + 3])
    }

    private static func fourCC(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    /// Creates a standard 3GPP Timed Text (`tx3g`) format description accepted by AVAssetWriter and AVPlayer.
    private static func makeTX3GFormatDescription(dimensions: CGSize) throws -> CMFormatDescription {
        let width = Int16(clamping: Int(dimensions.width.rounded()))
        let height = Int16(clamping: Int(dimensions.height.rounded()))
        let extensions: [CFString: Any] = [
            kCMTextFormatDescriptionExtension_DisplayFlags: Int32(0),
            kCMTextFormatDescriptionExtension_BackgroundColor: [
                kCMTextFormatDescriptionColor_Red: 0,
                kCMTextFormatDescriptionColor_Green: 0,
                kCMTextFormatDescriptionColor_Blue: 0,
                kCMTextFormatDescriptionColor_Alpha: 0
            ] as [CFString: Any],
            kCMTextFormatDescriptionExtension_DefaultTextBox: [
                kCMTextFormatDescriptionRect_Top: Int16(0),
                kCMTextFormatDescriptionRect_Left: Int16(0),
                kCMTextFormatDescriptionRect_Bottom: height,
                kCMTextFormatDescriptionRect_Right: width
            ] as [CFString: Any],
            kCMTextFormatDescriptionExtension_DefaultStyle: [
                kCMTextFormatDescriptionStyle_StartChar: Int16(0),
                kCMTextFormatDescriptionStyle_EndChar: Int16(0),
                kCMTextFormatDescriptionStyle_Font: Int16(1),
                kCMTextFormatDescriptionStyle_FontFace: Int8(0),
                kCMTextFormatDescriptionStyle_FontSize: Int8(24),
                kCMTextFormatDescriptionStyle_ForegroundColor: [
                    kCMTextFormatDescriptionColor_Red: 255,
                    kCMTextFormatDescriptionColor_Green: 255,
                    kCMTextFormatDescriptionColor_Blue: 255,
                    kCMTextFormatDescriptionColor_Alpha: 255
                ] as [CFString: Any]
            ] as [CFString: Any],
            kCMTextFormatDescriptionExtension_HorizontalJustification: Int8(1), // centered
            kCMTextFormatDescriptionExtension_VerticalJustification: Int8(-1), // bottom
            kCMTextFormatDescriptionExtension_FontTable: ["1": "Sans-Serif"]
        ]

        var formatDescription: CMFormatDescription?
        let status = CMFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            mediaType: kCMMediaType_Subtitle,
            mediaSubType: kCMTextFormatType_3GText,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else {
            throw VideoglotError.subtitleWriteFailed
        }
        return formatDescription
    }

    /// Converts timed cues into non-overlapping chronological `tx3g` sample buffers, inserting empty clear samples
    /// at cue ends so subtitles disappear cleanly on time.
    private static func buildTX3GSampleBuffers(
        cues: [TimedTextCue],
        totalDuration: TimeInterval,
        formatDescription: CMFormatDescription
    ) -> [CMSampleBuffer] {
        let timescale: CMTimeScale = 600
        let validCues = cues
            .map { $0.normalized() }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.endTime > $0.startTime }

        var buffers: [CMSampleBuffer] = []
        var cursor: TimeInterval = 0

        for (index, cue) in validCues.enumerated() {
            let start = max(cursor, cue.startTime)
            let nextCueStart = (index + 1 < validCues.count) ? validCues[index + 1].startTime : nil
            let rawEnd = cue.endTime
            let end = nextCueStart.map { min(rawEnd, max(start + 0.05, $0)) } ?? rawEnd
            guard end > start else { continue }

            // Insert an empty sample before the cue if there is a gap
            if start > cursor + 0.01 {
                if let empty = makeTX3GSampleBuffer(
                    text: "",
                    startTime: CMTime(seconds: cursor, preferredTimescale: timescale),
                    duration: CMTime(seconds: start - cursor, preferredTimescale: timescale),
                    formatDescription: formatDescription
                ) {
                    buffers.append(empty)
                }
            }

            if let buffer = makeTX3GSampleBuffer(
                text: cue.text,
                startTime: CMTime(seconds: start, preferredTimescale: timescale),
                duration: CMTime(seconds: end - start, preferredTimescale: timescale),
                formatDescription: formatDescription
            ) {
                buffers.append(buffer)
            }
            cursor = end
        }

        // Trailing empty sample so the final subtitle clears at its endTime
        let finalDuration = max(0.1, totalDuration - cursor)
        if !buffers.isEmpty || totalDuration > 0 {
            if let trailing = makeTX3GSampleBuffer(
                text: "",
                startTime: CMTime(seconds: cursor, preferredTimescale: timescale),
                duration: CMTime(seconds: finalDuration, preferredTimescale: timescale),
                formatDescription: formatDescription
            ) {
                buffers.append(trailing)
            }
        }
        return buffers
    }

    private static func makeTX3GSampleBuffer(
        text: String,
        startTime: CMTime,
        duration: CMTime,
        formatDescription: CMFormatDescription
    ) -> CMSampleBuffer? {
        let utf8 = Data(text.utf8.prefix(Int(UInt16.max)))
        let length = UInt16(utf8.count)
        var payload = Data(capacity: 2 + utf8.count)
        payload.append(UInt8((length >> 8) & 0xFF))
        payload.append(UInt8(length & 0xFF))
        payload.append(utf8)

        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: payload.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: payload.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard createStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        let replaceStatus = payload.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: payload.count
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: startTime,
            decodeTimeStamp: .invalid
        )
        var sampleSize = payload.count
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr else { return nil }
        return sampleBuffer
    }

    /// Converts a BCP-47 or ISO 639-1 language code to the ISO 639-2/T 3-letter code MP4/QuickTime tracks expect.
    private static func iso639_2TCode(for identifier: String) -> String? {
        let language = Locale.Language(identifier: identifier)
        guard let code = language.languageCode else { return nil }
        return code.identifier(.alpha3)
    }
}
