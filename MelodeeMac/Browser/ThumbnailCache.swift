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

    func thumbnail(for item: BrowserItem, size: CGFloat, scale: CGFloat) async -> NSImage? {
        if let cached = cachedThumbnail(for: item) {
            return cached
        }
        guard let file = item.file else { return nil }
        let url = item.url
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
