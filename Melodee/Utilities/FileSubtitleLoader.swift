@preconcurrency import AVFoundation
import Foundation
import SFBAudioEngine

/// Builds the subtitle shown under a file's name in the file browser: format, total time and size.
///
/// Total time is only read for audio and video files that are stored locally.
/// Files evicted to iCloud skip it, because reading inside them would make iCloud download the whole file.
/// Their format and size come from the file name and filesystem metadata, so they are still shown.
enum FileSubtitleLoader {

    struct Result: Sendable {
        var subtitle: String?
        var isEvicted: Bool
    }

    private final class CachedDuration {
        let duration: String?
        init(_ duration: String?) { self.duration = duration }
    }

    nonisolated(unsafe) private static let durationCache = NSCache<NSString, CachedDuration>()

    /// Reads the file's eviction state and subtitle off the main thread.
    static func load(for file: FSFile) async -> Result {
        let path = file.path
        let type = file.type
        let format = file.extension.uppercased()
        return await Task.detached(priority: .utility) { () -> Result in
            let url = URL(filePath: path)
            let isEvicted = FSFile.isEvicted(atPath: path)
            var duration: String?
            if !isEvicted, type == .audio || type == .video {
                duration = await cachedDuration(for: url, type: type)
            }
            let size = isEvicted ? evictedFileSizeString(for: url) : fileSizeString(for: url)
            let parts = [format.isEmpty ? nil : format, duration, size].compactMap { $0 }
            return Result(subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "), isEvicted: isEvicted)
        }.value
    }

    // MARK: - Total time

    private static func cachedDuration(for url: URL, type: FileType) async -> String? {
        let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let cacheKey = "\(url.path(percentEncoded: false))|\(modificationDate)" as NSString
        if let cached = durationCache.object(forKey: cacheKey) {
            return cached.duration
        }
        let seconds: Double? = if type == .audio {
            audioDuration(for: url)
        } else {
            await videoDuration(for: url)
        }
        let duration = seconds.flatMap(durationString)
        durationCache.setObject(CachedDuration(duration), forKey: cacheKey)
        return duration
    }

    private static func audioDuration(for url: URL) -> Double? {
        // SFBAudioEngine reads the duration from the file's headers, falling back to AVFoundation
        if let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url),
           let duration = audioFile.properties.duration {
            return duration
        }
        return nil
    }

    private static func videoDuration(for url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        return duration.seconds
    }

    private static func durationString(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds.rounded()).formatted(.time(pattern: pattern))
    }

    // MARK: - File size

    private static func fileSizeString(for url: URL) -> String? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Reads an evicted file's size without downloading it.
    /// Older iCloud evictions leave a `.<name>.icloud` placeholder holding the size, newer ones keep a dataless file.
    private static func evictedFileSizeString(for url: URL) -> String? {
        let placeholderURL = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).icloud")
        if let data = try? Data(contentsOf: placeholderURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let size = (plist["NSURLFileSizeKey"] as? NSNumber)?.int64Value {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        return fileSizeString(for: url)
    }
}
