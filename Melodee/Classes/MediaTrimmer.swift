import Audioglot
@preconcurrency import AVFoundation
import Foundation
import Prelude
import SFBAudioEngine
import Videoglot

enum MediaTrimmerError: LocalizedError {
    /// The original is in iCloud Drive and is downloading. Trying again once it has downloaded works.
    case originalNotDownloaded
    case noOriginal

    var errorDescription: String? {
        switch self {
        case .originalNotDownloaded: String(localized: "Trim.Error.OriginalDownloading")
        case .noOriginal: String(localized: "Trim.Error.NoOriginal")
        }
    }
}

/// Trims audio and video files in place, keeping their originals with ``TrimBackups``.
enum MediaTrimmer {

    /// The shortest selection that may be kept, in seconds.
    static let minimumLength: TimeInterval = 0.5

    static func canTrim(_ file: FSFile) -> Bool {
        switch file.type {
        case .audio: Audioglot.trimmableExtensions.contains(file.extension)
        case .video: Videoglot.trimmableExtensions.contains(file.extension)
        default: false
        }
    }

    static func hasOriginal(_ file: FSFile) -> Bool {
        TrimBackups.hasBackup(for: URL(filePath: file.path))
    }

    /// Opens the media to trim: the original if the file was trimmed before, otherwise the file itself.
    static func openSource(for file: FSFile) throws -> TrimSource {
        let fileURL = URL(filePath: file.path)
        guard TrimBackups.hasBackup(for: fileURL) else {
            return TrimSource(url: fileURL, temporaryDirectory: nil)
        }
        let backupURL = try downloadedBackupURL(for: fileURL)
        // Decoders pick a format from the extension, so read the original through a link that keeps it
        let directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                    appropriateFor: fileURL, create: true)
        let linkURL = directory.appending(path: "Original.\(fileURL.pathExtension)")
        do {
            try FileManager.default.linkItem(at: backupURL, to: linkURL)
        } catch {
            try FileManager.default.copyItem(at: backupURL, to: linkURL)
        }
        return TrimSource(url: linkURL, temporaryDirectory: directory)
    }

    /// The length of the original, in seconds, which is what a pasted trim is measured against.
    static func originalDuration(of file: FSFile) async throws -> TimeInterval {
        let source = try openSource(for: file)
        if file.type == .video {
            let asset = AVURLAsset(url: source.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            return try await asset.load(.duration).seconds
        }
        let decoder = try AudioDecoder(url: source.url)
        try decoder.open()
        defer { try? decoder.close() }
        return Double(decoder.length) / decoder.processingFormat.sampleRate
    }

    /// Replaces the file with the part of its original between the range's bounds, in seconds.
    static func trim(_ file: FSFile, to range: ClosedRange<TimeInterval>,
                     progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let fileURL = URL(filePath: file.path)
        let source = try openSource(for: file)
        let workDirectory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                        appropriateFor: fileURL, create: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let trimmedURL = workDirectory.appending(path: fileURL.lastPathComponent)

        if file.type == .video {
            try await Videoglot.trim(source.url, from: range.lowerBound, to: range.upperBound,
                                     outputURL: trimmedURL, progress: progress)
        } else {
            try await Audioglot.trim(source.url, from: range.lowerBound, to: range.upperBound,
                                     outputURL: trimmedURL, progress: progress)
        }
        // Tags come from the file as it is now, so edits made after an earlier trim are kept
        await copyTags(from: fileURL, to: trimmedURL)

        let manager = FileManager.default
        let backupURL = TrimBackups.backupURL(for: fileURL)
        if TrimBackups.hasBackup(for: fileURL) {
            // Trimmed before: the original stays, and only the trimmed file is replaced
            _ = try manager.replaceItemAt(fileURL, withItemAt: trimmedURL)
        } else {
            try manager.moveItem(at: fileURL, to: backupURL)
            do {
                try manager.moveItem(at: trimmedURL, to: fileURL)
            } catch {
                try? manager.moveItem(at: backupURL, to: fileURL)
                throw error
            }
        }
        TrimBackups.recordTrim(of: fileURL, range: range)
    }

    /// Puts the original back in place of the trimmed file.
    static func restoreOriginal(of file: FSFile) throws {
        let fileURL = URL(filePath: file.path)
        guard TrimBackups.hasBackup(for: fileURL) else { throw MediaTrimmerError.noOriginal }
        let backupURL = try downloadedBackupURL(for: fileURL)
        removexattr(backupURL.path, TrimBackups.rangeAttribute, 0)
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: backupURL)
        } else {
            try FileManager.default.moveItem(at: backupURL, to: fileURL)
        }
    }

    /// The original's URL, starting a download and throwing if iCloud Drive has evicted it.
    private static func downloadedBackupURL(for fileURL: URL) throws -> URL {
        if TrimBackups.isBackupEvicted(for: fileURL) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: TrimBackups.backupURL(for: fileURL))
            throw MediaTrimmerError.originalNotDownloaded
        }
        return TrimBackups.backupURL(for: fileURL)
    }

    /// Gives the trimmed file exactly the tags and artwork of `sourceURL`. Encoders and exports add or carry
    /// over tags of their own, so those are removed rather than left mixed in.
    static func copyTags(from sourceURL: URL, to destinationURL: URL) async {
        await Task.detached(priority: .userInitiated) {
            guard TagLibFile.supportedExtensions().contains(destinationURL.pathExtension.lowercased()),
                  let source = TagLibFile(path: sourceURL.path(percentEncoded: false)),
                  let destination = TagLibFile(path: destinationURL.path(percentEncoded: false)) else { return }
            // Gapless playback info describes the trimmed audio itself, so the trimmed file keeps its own
            let sourceProperties = source.properties.filter { !MediaTrimmerTags.keptFromTrim.contains($0.key) }
            for key in destination.properties.keys
            where sourceProperties[key] == nil && !MediaTrimmerTags.keptFromTrim.contains(key) {
                destination.setValues(nil, forProperty: key)
            }
            for (key, values) in sourceProperties {
                destination.setValues(values, forProperty: key)
            }
            destination.setFrontCover(source.frontCover)
            _ = destination.save()
        }.value
    }
}

/// Media opened for trimming, readable by decoders. Removes any temporary link when released.
final class TrimSource: Sendable {

    let url: URL
    private let temporaryDirectory: URL?

    init(url: URL, temporaryDirectory: URL?) {
        self.url = url
        self.temporaryDirectory = temporaryDirectory
    }

    deinit {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }
}

/// Tags written by the trim that describe the trimmed audio, rather than the song.
enum MediaTrimmerTags {
    /// iTunes gapless info: the encoder delay, padding and length of the audio. Copying the original's would make
    /// players treat the trimmed file as full length.
    static let keptFromTrim: Set<String> = ["ITUNSMPB"]
}
