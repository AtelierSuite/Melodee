@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import Videoglot

@Suite struct TimedTextCodecTests {

    @Test func parsesAndSerializesSRT() {
        let srt = """
        1
        00:00:01,500 --> 00:00:04,250
        Hello, <i>world</i>!
        Second line

        2
        00:00:05,000 --> 00:00:08,750
        Next cue
        """
        let doc = TimedTextCodec.parse(string: srt, format: .srt)
        #expect(!doc.isLyrics)
        #expect(doc.cues.count == 2)
        #expect(abs(doc.cues[0].startTime - 1.5) < 0.001)
        #expect(abs(doc.cues[0].endTime - 4.25) < 0.001)
        #expect(doc.cues[0].text == "Hello, world!\nSecond line")
        #expect(doc.activeText(at: 2.0) == "Hello, world!\nSecond line")
        #expect(doc.activeText(at: 4.5) == nil)

        let serialized = TimedTextCodec.serialize(doc, as: .srt)
        let reparsed = TimedTextCodec.parse(string: serialized, format: .srt)
        #expect(reparsed.cues.count == 2)
        #expect(reparsed.cues[0].text == doc.cues[0].text)
        #expect(abs(reparsed.cues[1].endTime - 8.75) < 0.001)
    }

    @Test func parsesAndSerializesWebVTT() {
        let vtt = """
        WEBVTT - English Captions
        Language: en

        NOTE this is a comment

        00:01.200 --> 00:03.400 align:center
        <v Speaker>First <b>cue</b></v>

        00:01:05.000 --> 00:01:08.500
        Second cue &amp; more
        """
        let doc = TimedTextCodec.parse(string: vtt, format: .vtt)
        #expect(doc.title == "English Captions")
        #expect(doc.languageCode == "en")
        #expect(doc.cues.count == 2)
        #expect(abs(doc.cues[0].startTime - 1.2) < 0.001)
        #expect(doc.cues[0].text == "First cue")
        #expect(abs(doc.cues[1].startTime - 65.0) < 0.001)
        #expect(doc.cues[1].text == "Second cue & more")

        let serialized = TimedTextCodec.serialize(doc, as: .vtt)
        let reparsed = TimedTextCodec.parse(string: serialized, format: .vtt)
        #expect(reparsed.title == "English Captions")
        #expect(reparsed.languageCode == "en")
        #expect(reparsed.cues.count == 2)
        #expect(reparsed.cues[1].text == "Second cue & more")
    }

    @Test func parsesASSAndStripsOverrideTags() {
        let ass = """
        [Script Info]
        Title: Demo Subtitles

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:02.50,0:00:05.00,Default,,0,0,0,,{\\an8\\i1}Top line\\NBottom line
        """
        let doc = TimedTextCodec.parse(string: ass, format: .ass)
        #expect(doc.title == "Demo Subtitles")
        #expect(doc.cues.count == 1)
        #expect(abs(doc.cues[0].startTime - 2.5) < 0.001)
        #expect(abs(doc.cues[0].endTime - 5.0) < 0.001)
        #expect(doc.cues[0].text == "Top line\nBottom line")
    }

    @Test func parsesAndSerializesLRC() {
        let lrc = """
        [ti:Midnight City]
        [ar:Artist]
        [la:en]
        [00:01.00]First line
        [00:04.50][00:12.00]Chorus <00:05.00>line
        [00:08.00]
        """
        let doc = TimedTextCodec.parse(string: lrc, format: .lrc)
        #expect(doc.isLyrics)
        #expect(doc.title == "Midnight City")
        #expect(doc.artist == "Artist")
        #expect(doc.languageCode == "en")
        #expect(doc.cues.count == 3)
        #expect(doc.cues[0].text == "First line")
        #expect(abs(doc.cues[0].endTime - 4.5) < 0.01)
        #expect(doc.cues[1].text == "Chorus line")
        #expect(abs(doc.cues[1].endTime - 8.0) < 0.01)
        #expect(abs(doc.cues[2].startTime - 12.0) < 0.01)

        let serialized = TimedTextCodec.serialize(doc, as: .lrc)
        let reparsed = TimedTextCodec.parse(string: serialized, format: .lrc)
        #expect(reparsed.cues.count == 3)
        #expect(reparsed.cues[1].text == "Chorus line")
        #expect(reparsed.activeText(at: 9.0) == nil)
    }

    @Test func parsesEmbeddedLyricsSyncedAndUnsynced() {
        let synced = TimedTextCodec.parseEmbeddedLyrics("[00:02.00]Hello\n[00:05.00]World")
        #expect(synced.hasTimedCues)
        #expect(synced.cues.count == 2)

        let plain = TimedTextCodec.parseEmbeddedLyrics("Line one\nLine two")
        #expect(!plain.hasTimedCues)
        #expect(plain.unsyncedText == "Line one\nLine two")
    }

    @Test func cueEditingOperationsWork() {
        var doc = TimedTextDocument()
        let first = doc.addCue(at: 2.0, duration: 4.0, text: "Hello world")
        let second = doc.addCue(at: 8.0, duration: 2.0, text: "Goodbye")
        #expect(doc.cues.count == 2)

        let splitID = doc.splitCue(id: first.id, at: 4.0)
        #expect(splitID != nil)
        #expect(doc.cues.count == 3)
        #expect(doc.cues[0].text == "Hello")
        #expect(doc.cues[1].text == "world")
        #expect(abs(doc.cues[0].endTime - 4.0) < 0.001)
        #expect(abs(doc.cues[1].startTime - 4.0) < 0.001)

        let merged = doc.mergeCueWithNext(id: first.id)
        #expect(merged)
        #expect(doc.cues.count == 2)
        #expect(doc.cues[0].text == "Hello\nworld")
        #expect(abs(doc.cues[0].endTime - 6.0) < 0.001)

        doc.shiftAll(by: -3.0)
        #expect(abs(doc.cues[0].startTime - 0.0) < 0.001)
        #expect(abs(doc.cues[0].endTime - 3.0) < 0.001)
        #expect(abs(doc.cues[1].startTime - 5.0) < 0.001)

        doc.deleteCues(ids: [second.id])
        #expect(doc.cues.count == 1)
    }

    @Test func discoversSidecarsWithLanguageSuffixes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidecarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let video = dir.appendingPathComponent("Concert.mp4")
        try Data().write(to: video)
        for name in ["Concert.srt", "Concert.en.vtt", "Concert.ja.lrc", "Concert.en-US.forced.srt", "Other.srt"] {
            try "test".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let found = SidecarTimedTextFile.discover(for: video)
        #expect(found.count == 4)
        #expect(found.contains { $0.url.lastPathComponent == "Concert.srt" && $0.languageCode == nil })
        #expect(found.contains { $0.url.lastPathComponent == "Concert.en.vtt" && $0.languageCode == "en" })
        #expect(found.contains { $0.url.lastPathComponent == "Concert.ja.lrc" && $0.format == .lrc && $0.languageCode == "ja" })
        #expect(found.contains {
            $0.url.lastPathComponent == "Concert.en-US.forced.srt" &&
            $0.languageCode == "en-US" &&
            $0.variantLabel == "forced"
        })
    }
}

@Suite(.serialized) struct SubtitleEmbedTests {

    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubtitleEmbedTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func makeMP4(name: String) async throws -> URL {
        let url = directory.appendingPathComponent("\(name).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 72
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 72
        ])
        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            while !videoInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
            adaptor.append(pixelBuffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        videoInput.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed, "\(String(describing: writer.error))")
        return url
    }

    @Test func embedsAndExtractsTX3GSubtitlesInMP4() async throws {
        let source = try await makeMP4(name: "clip")
        let output = directory.appendingPathComponent("clip-subtitled.mp4")

        let doc = TimedTextDocument(
            cues: [
                TimedTextCue(startTime: 0.2, endTime: 0.9, text: "First subtitle"),
                TimedTextCue(startTime: 1.1, endTime: 1.8, text: "Second line\nWith newline")
            ],
            title: "English",
            languageCode: "en",
            isLyrics: false
        )

        try await Videoglot.embedSubtitles(doc, into: source, outputURL: output)

        let asset = AVURLAsset(url: output)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        #expect(videoTracks.count == 1)

        let tracks = try await Videoglot.embeddedSubtitleTracks(in: output)
        #expect(tracks.count == 1)
        #expect(tracks[0].title == "English")
        #expect(tracks[0].effectiveLanguageCode == "en" || tracks[0].languageCode == "eng")

        let legibleGroup = try await asset.loadMediaSelectionGroup(for: .legible)
        #expect(legibleGroup != nil)
        #expect((legibleGroup?.options.count ?? 0) >= 1)

        let extracted = try await Videoglot.extractEmbeddedSubtitles(from: output, trackID: tracks[0].trackID)
        #expect(extracted.cues.count == 2)
        #expect(extracted.cues[0].text == "First subtitle")
        #expect(extracted.cues[1].text == "Second line\nWith newline")
        #expect(abs(extracted.cues[0].startTime - 0.2) < 0.05)
        #expect(abs(extracted.cues[1].startTime - 1.1) < 0.05)
    }

    @Test func writesSubtitleTrackFileThatComposesWithVideo() async throws {
        let video = try await makeMP4(name: "composed")
        let subtitleFile = directory.appendingPathComponent("composed-subtitles.mp4")
        let doc = TimedTextDocument(
            cues: [
                TimedTextCue(startTime: 0.2, endTime: 0.9, text: "Composed one"),
                TimedTextCue(startTime: 1.1, endTime: 1.8, text: "Composed two")
            ],
            title: nil,
            languageCode: "ja",
            isLyrics: false
        )

        try await Videoglot.writeSubtitleTrackFile(doc, duration: 2, videoSize: CGSize(width: 64, height: 64), to: subtitleFile)

        let tracks = try await Videoglot.embeddedSubtitleTracks(in: subtitleFile)
        #expect(tracks.count == 1)
        let extracted = try await Videoglot.extractEmbeddedSubtitles(from: subtitleFile, trackID: tracks[0].trackID)
        #expect(extracted.cues.map(\.text) == ["Composed one", "Composed two"])

        let videoAsset = AVURLAsset(url: video)
        let subtitleAsset = AVURLAsset(url: subtitleFile)
        let composition = AVMutableComposition()
        let duration = try await videoAsset.load(.duration)
        for track in try await videoAsset.load(.tracks) {
            let compositionTrack = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)
            try compositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        }
        for track in try await subtitleAsset.load(.tracks) {
            let timeRange = try await track.load(.timeRange)
            let compositionTrack = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)
            try compositionTrack?.insertTimeRange(timeRange, of: track, at: timeRange.start)
            compositionTrack?.extendedLanguageTag = "ja"
        }
        let group = try await composition.loadMediaSelectionGroup(for: .legible)
        #expect(group?.options.contains { $0.extendedLanguageTag == "ja" } == true)
    }
}
