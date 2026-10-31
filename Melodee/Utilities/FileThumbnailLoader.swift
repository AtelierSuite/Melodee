@preconcurrency import AVFoundation
import QuickLookThumbnailing
import UIKit

enum FileThumbnailLoader {

    /// Loads a square thumbnail for a file off the main thread.
    /// Taggable audio files use their album art, falling back to a generic album image, and images are downscaled.
    /// Videos, PDFs and text files only get a Quick Look thumbnail when `includesDocuments` is true.
    static func thumbnail(
        for file: FSFile,
        size: CGFloat,
        scale: CGFloat = 2.0,
        includesDocuments: Bool = false
    ) async -> UIImage? {
        let filePath = file.path
        let isTaggable = file.isTaggableAudio()
        let type = file.type
        return await Task.detached(priority: .utility) { () -> UIImage? in
            let fileURL = coordinatedURL(for: URL(filePath: filePath))
            let pixelSize = CGSize(width: size * scale, height: size * scale)
            if isTaggable {
                return await albumArt(at: fileURL, size: pixelSize) ?? UIImage(named: "Album.Generic")
            } else if type == .image {
                return await UIImage(contentsOfFile: fileURL.path(percentEncoded: false))?
                    .byPreparingThumbnail(ofSize: pixelSize)
            } else if includesDocuments, type == .video || type == .pdf || type == .text {
                let request = QLThumbnailGenerator.Request(
                    fileAt: fileURL,
                    size: CGSize(width: size, height: size),
                    scale: scale,
                    representationTypes: .thumbnail
                )
                return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
            }
            return nil
        }.value
    }

    private static func coordinatedURL(for url: URL) -> URL {
        var coordinatedURL = url
        NSFileCoordinator().coordinate(readingItemAt: url, error: .none) { url in
            coordinatedURL = url
        }
        return coordinatedURL
    }

    private static func albumArt(at url: URL, size: CGSize) async -> UIImage? {
        do {
            let asset = AVURLAsset(url: url)
            let metadataList = try await asset.load(.metadata)
            for item in metadataList where item.commonKey == .commonKeyArtwork {
                if let data = try await item.load(.dataValue),
                   let image = UIImage(data: data),
                   let thumbnail = await image.byPreparingThumbnail(ofSize: size) {
                    return thumbnail
                }
            }
        } catch {
            debugPrint(error.localizedDescription)
        }
        return nil
    }
}
