//
//  ThumbnailCache.swift
//  Melodee
//

import AppKit
import QuickLookThumbnailing
import SFBAudioEngine

/// Loads album art and Quick Look thumbnails for the grid, keeping recent ones in memory.
@MainActor
final class ThumbnailCache {

    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    func cachedThumbnail(for item: BrowserItem) -> NSImage? {
        cache.object(forKey: item.url.path as NSString)
    }

    func removeThumbnails(forPaths paths: Set<String>) {
        paths.forEach { cache.removeObject(forKey: $0 as NSString) }
    }

    func thumbnail(for item: BrowserItem, size: CGFloat, scale: CGFloat) async -> NSImage? {
        guard let file = item.file else { return nil }
        return await thumbnail(for: file, size: size, scale: scale)
    }

    func cachedThumbnail(for file: FSFile) -> NSImage? {
        cache.object(forKey: URL(filePath: file.path).path as NSString)
    }

    func thumbnail(for file: FSFile, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let url = URL(filePath: file.path)
        if let cached = cache.object(forKey: url.path as NSString) {
            return cached
        }
        let isTaggable = file.isTaggableAudio()
        let image: NSImage? = await Task.detached(priority: .utility) {
            if isTaggable, let data = AudioFile.read(for: file)?.coverArtData, let image = NSImage(data: data) {
                return image
            }
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: size, height: size),
                scale: scale,
                representationTypes: .thumbnail
            )
            return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }.value
        if let image {
            cache.setObject(image, forKey: url.path as NSString)
        }
        return image
    }
}
