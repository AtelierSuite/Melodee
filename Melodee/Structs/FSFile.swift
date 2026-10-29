import Foundation
import Prelude
import SwiftUI

struct FSFile: FilesystemObject {

    var name: String
    var `extension`: String
    var path: String
    var type: FileType
    var playbackQueueID: String = ""

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    func containingFolderPath() -> String {
        let url = URL(filePath: path)
        return url.deletingLastPathComponent().path(percentEncoded: false)
    }

    func containingFolderName() -> String {
        do {
            let url = URL(filePath: containingFolderPath())
            if url.lastPathComponent == "Documents" {
                let documentsDirectoryURL = try FileManager.default
                .url(for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true)
                if documentsDirectoryURL != url {
                    return url.lastPathComponent
                }
            } else {
                return url.lastPathComponent
            }
        } catch {
            debugPrint(error.localizedDescription)
        }
        return "Melodee"
    }

    /// Returns true if this file can be added to the playback queue.
    func isPlayableMedia() -> Bool {
        return type == .audio || type == .video
    }

    /// Returns true if this file is an audio file that Prelude can read and write tags for.
    func isTaggableAudio() -> Bool {
        return type == .audio && FSFile.taggableAudioExtensions.contains(self.extension.lowercased())
    }

    /// Audio file extensions that TagLib can read and write tags for.
    static let taggableAudioExtensions = Set(TagLibFile.supportedExtensions())

    /// Returns true if this audio file can be converted to other formats
    func isConvertibleAudio() -> Bool {
        let convertibleFormats = ["mp3", "m4a", "wav", "alac"]
        return convertibleFormats.contains(self.extension)
    }

    /// Returns available conversion formats for this audio file
    func availableConversionFormats() -> [String] {
        return AudioConverter.availableFormats(for: self.extension)
    }

    /// Returns true if this file is stored in iCloud and not yet downloaded locally
    func isEvicted() -> Bool {
        return FSFile.isEvicted(atPath: path)
    }

    static func isEvicted(atPath path: String) -> Bool {
        let url = URL(filePath: path)
        // Check if the .icloud placeholder file exists
        let placeholderName = ".\(url.lastPathComponent).icloud"
        let placeholderURL = url.deletingLastPathComponent().appending(path: placeholderName)
        if FileManager.default.fileExists(atPath: placeholderURL.path(percentEncoded: false)) {
            return true
        }
        // Also check via resource values for ubiquitous items
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values.ubiquitousItemDownloadingStatus {
                return status != .current
            }
        } catch {
            // Not a ubiquitous item, treat as local
        }
        return false
    }
}
