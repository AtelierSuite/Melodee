import Foundation

extension URL {
    var attributes: [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: path)
        } catch let error as NSError {
            debugPrint(error.localizedDescription)
        }
        return nil
    }

    var fileSize: UInt64 {
        return attributes?[.size] as? UInt64 ?? UInt64(0)
    }

    var fileSizeString: String {
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var creationDate: Date? {
        return attributes?[.creationDate] as? Date
    }

    /// When the item arrived in its folder, or when it was created on volumes that don't record that.
    /// Files evicted from iCloud may only exist as a `.icloud` placeholder, so that is checked too.
    var dateAdded: Date? {
        let placeholderURL = deletingLastPathComponent().appending(path: ".\(lastPathComponent).icloud")
        for url in [self, placeholderURL] {
            if let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey]),
               let date = values.addedToDirectoryDate ?? values.creationDate {
                return date
            }
        }
        return nil
    }
}
