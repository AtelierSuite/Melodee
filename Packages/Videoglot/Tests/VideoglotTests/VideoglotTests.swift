@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import Videoglot

@Suite struct TargetTests {

    @Test func ownContainerIsNeverOffered() {
        #expect(VideoFormat.targets(forPathExtension: "mov") == [.mp4, .m4v, .m4a])
        #expect(VideoFormat.targets(forPathExtension: "MP4") == [.mov, .m4v, .m4a])
        #expect(VideoFormat.targets(forPathExtension: "3gp") == [.mp4, .mov, .m4v, .m4a])
        #expect(VideoFormat.targets(forPathExtension: "mkv").isEmpty)
    }
}

@Suite(.serialized) struct ExportTests {

    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoglotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Writes a one-second 64×64 H.264 MOV, with an audio track in `audioFormat` (or none).
    private func makeMOV(name: String, audioFormat: AudioFormatID?) async throws -> URL {
        let url = directory.appendingPathComponent("\(name).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if let audioFormat {
            var settings: [String: Any] = [
                AVFormatIDKey: audioFormat, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2
            ]
            if audioFormat == kAudioFormatLinearPCM {
                settings[AVLinearPCMBitDepthKey] = 16
                settings[AVLinearPCMIsFloatKey] = false
                settings[AVLinearPCMIsBigEndianKey] = false
                settings[AVLinearPCMIsNonInterleaved] = false
            }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            writer.add(input)
            audioInput = input
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<30 {
            while !videoInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
            adaptor.append(pixelBuffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        videoInput.markAsFinished()

        if let audioInput {
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100, channels: 2,
                                       interleaved: true)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
            buffer.frameLength = 44100
            var sampleBuffer: CMSampleBuffer?
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44100),
                                            presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
            CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
                                 refcon: nil, formatDescription: format.formatDescription, sampleCount: 44100,
                                 sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0,
                                 sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
            CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer!, blockBufferAllocator: nil,
                                                           blockBufferMemoryAllocator: nil, flags: 0,
                                                           bufferList: buffer.audioBufferList)
            while !audioInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            audioInput.append(sampleBuffer!)
            audioInput.markAsFinished()
        }

        await writer.finishWriting()
        #expect(writer.status == .completed, "\(String(describing: writer.error))")
        return url
    }

    private func audioCodec(of url: URL) async throws -> FourCharCode? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first,
              let description = try await track.load(.formatDescriptions).first else { return nil }
        return CMFormatDescriptionGetMediaSubType(description)
    }

    @Test func remuxesIntoEveryContainer() async throws {
        let mov = try await makeMOV(name: "clip", audioFormat: kAudioFormatMPEG4AAC)
        for target in [VideoFormat.mp4, .m4v] {
            let output = try await Videoglot.convert(mov, to: target)
            let asset = AVURLAsset(url: output)
            #expect(try await asset.loadTracks(withMediaType: .video).count == 1, "\(target)")
            #expect(try await audioCodec(of: output) == kAudioFormatMPEG4AAC, "\(target)")
        }
    }

    @Test func extractsAACAudioWithoutReencoding() async throws {
        let mov = try await makeMOV(name: "aac", audioFormat: kAudioFormatMPEG4AAC)
        let m4a = try await Videoglot.convert(mov, to: .m4a)
        let asset = AVURLAsset(url: m4a)
        #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
        #expect(try await audioCodec(of: m4a) == kAudioFormatMPEG4AAC)
    }

    @Test func extractsPCMAudioAsAAC() async throws {
        let mov = try await makeMOV(name: "pcm", audioFormat: kAudioFormatLinearPCM)
        let m4a = try await Videoglot.convert(mov, to: .m4a)
        #expect(try await audioCodec(of: m4a) == kAudioFormatMPEG4AAC)
    }

    @Test func refusesAudioExtractionWithoutAudio() async throws {
        let mov = try await makeMOV(name: "silent", audioFormat: nil)
        await #expect(throws: VideoglotError.noAudioTrack) {
            try await Videoglot.convert(mov, to: .m4a)
        }
    }

    @Test func refusesOwnContainerAndExistingOutput() async throws {
        let mov = try await makeMOV(name: "dupe", audioFormat: kAudioFormatMPEG4AAC)
        await #expect(throws: VideoglotError.conversionNotAllowed(from: "mov", to: .mov)) {
            try await Videoglot.convert(mov, to: .mov)
        }
        let mp4 = try await Videoglot.convert(mov, to: .mp4)
        await #expect(throws: VideoglotError.outputExists(mp4)) {
            try await Videoglot.convert(mov, to: .mp4)
        }
    }
}
