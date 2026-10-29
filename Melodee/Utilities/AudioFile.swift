import Foundation
import SFBAudioEngine
import UIKit

extension AudioFile {

    /// Opens a file for reading metadata via SFBAudioEngine. Returns nil on failure.
    static func read(for file: FSFile) -> AudioFile? {
        do {
            let fileURL = URL(fileURLWithPath: file.path)
            return try AudioFile(readingPropertiesAndMetadataFrom: fileURL)
        } catch {
            debugPrint("Failed to read audio file \(file.name): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Convenience accessors over metadata

    var title: String? { metadata.title }
    var artist: String? { metadata.artist }
    var albumTitle: String? { metadata.albumTitle }
    var albumArtist: String? { metadata.albumArtist }
    var genre: String? { metadata.genre }
    var composer: String? { metadata.composer }
    var trackNumber: Int? { metadata.trackNumber }
    var discNumber: Int? { metadata.discNumber }

    /// Cover art as a UIImage, if any attached picture is present.
    var coverImage: UIImage? {
        guard let data = coverArtData else { return nil }
        return UIImage(data: data)
    }

    /// Cover art as raw image data (whatever bytes the tag contained — typically JPEG or PNG).
    var coverArtData: Data? {
        if let picture = metadata.attachedPictures(ofType: .frontCover).first
            ?? metadata.attachedPictures.first {
            return picture.imageData
        }
        return nil
    }
}
