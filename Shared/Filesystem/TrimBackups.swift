import Foundation

/// The originals of trimmed files, kept as hidden files beside them so they can be restored.
///
/// Trimming `Song.mp3` moves the original to `.Song.mp3.melodee-original` and writes the trimmed audio to
/// `Song.mp3`. Trimming again reads from the original and leaves it in place, so a restore always returns the
/// file as it was before its first trim. Each trim restarts a 30 day clock, kept as the original's modification
/// date, after which the original is deleted.
///
/// Keeping the original next to the file means it syncs with iCloud Drive and stays inside external folders the
/// app has access to. The file browser hides originals, and so do Files and Finder, since their names start with
/// a dot.
enum TrimBackups {

    static let suffix = "melodee-original"
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// Extended attribute holding the last trim's range, so the trimmer can open where it left off.
    /// The `#S` suffix asks iCloud Drive to sync it.
    static let rangeAttribute = "com.tsubuzaki.Melodee.trimRange#S"

    // MARK: Locating

    static func backupURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appending(path: ".\(fileURL.lastPathComponent).\(suffix)")
    }

    /// The placeholder iCloud Drive leaves when it evicts the original to save space.
    static func evictedBackupURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appending(path: ".\(backupURL(for: fileURL).lastPathComponent).icloud")
    }

    /// Whether `url` is an original, or the iCloud placeholder of one.
    static func isBackup(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") && (name.hasSuffix(".\(suffix)") || name.hasSuffix(".\(suffix).icloud"))
    }

    static func hasBackup(for fileURL: URL) -> Bool {
        exists(backupURL(for: fileURL)) || exists(evictedBackupURL(for: fileURL))
    }

    /// Whether the original is only in iCloud and must be downloaded before it can be read.
    static func isBackupEvicted(for fileURL: URL) -> Bool {
        !exists(backupURL(for: fileURL)) && exists(evictedBackupURL(for: fileURL))
    }

    /// When the original will be deleted.
    static func expiryDate(for fileURL: URL) -> Date? {
        modificationDate(of: backupURL(for: fileURL)).map { $0.addingTimeInterval(retention) }
    }

    // MARK: Trim range

    static func storedRange(for fileURL: URL) -> ClosedRange<TimeInterval>? {
        let url = backupURL(for: fileURL)
        let size = getxattr(url.path, rangeAttribute, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, rangeAttribute, $0.baseAddress, size, 0, 0) }
        guard read == size, let values = try? JSONDecoder().decode([TimeInterval].self, from: data),
              values.count == 2, values[1] > values[0] else { return nil }
        return values[0]...values[1]
    }

    /// Records a trim on the original: remembers its range and restarts the 30 day clock.
    static func recordTrim(of fileURL: URL, range: ClosedRange<TimeInterval>) {
        let url = backupURL(for: fileURL)
        if let data = try? JSONEncoder().encode([range.lowerBound, range.upperBound]) {
            _ = data.withUnsafeBytes { setxattr(url.path, rangeAttribute, $0.baseAddress, data.count, 0, 0) }
        }
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
    }

    // MARK: Keeping originals with their files

    /// Moves the original along with a file that was renamed or moved.
    static func moveBackup(from oldPath: String, to newPath: String) {
        moveBackups([oldPath: newPath])
    }

    /// Moves the originals of files that were renamed or moved, given as old paths mapped to new paths.
    /// Originals pass through temporary names first, so files that swapped names keep their own originals.
    static func moveBackups(_ movedPaths: [String: String]) {
        let manager = FileManager.default
        var staged: [(temporaryURL: URL, destinationURL: URL)] = []
        for (oldPath, newPath) in movedPaths {
            let oldURL = URL(filePath: oldPath)
            let newURL = URL(filePath: newPath)
            for (source, destination) in [(backupURL(for: oldURL), backupURL(for: newURL)),
                                          (evictedBackupURL(for: oldURL), evictedBackupURL(for: newURL))]
            where exists(source) {
                let temporaryURL = source.deletingLastPathComponent()
                    .appending(path: ".melodee-moving-\(UUID().uuidString)")
                if (try? manager.moveItem(at: source, to: temporaryURL)) != nil {
                    staged.append((temporaryURL, destination))
                }
            }
        }
        for (temporaryURL, destinationURL) in staged {
            try? manager.removeItem(at: destinationURL)
            try? manager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    static func deleteBackup(for fileURL: URL) {
        try? FileManager.default.removeItem(at: backupURL(for: fileURL))
        try? FileManager.default.removeItem(at: evictedBackupURL(for: fileURL))
    }

    // MARK: Expiry

    /// Deletes `url` if it's an original whose 30 days are up. Called while listing a folder.
    static func deleteIfExpired(_ url: URL) {
        guard isBackup(url) else { return }
        // An original evicted by iCloud Drive is listed as its placeholder, so act on the item itself
        let itemURL = itemURL(forListed: url)
        guard let date = modificationDate(of: itemURL), date.addingTimeInterval(retention) < .now else { return }
        if (try? FileManager.default.removeItem(at: itemURL)) == nil {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The item a listed URL stands for: the URL itself, or for an iCloud placeholder (`.Name.icloud`), the
    /// evicted item it replaces.
    private static func itemURL(forListed url: URL) -> URL {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return url }
        return url.deletingLastPathComponent().appending(path: String(name.dropFirst().dropLast(".icloud".count)))
    }

    // MARK: Helpers

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// The modification date of `url`, which iCloud Drive reports even for an evicted item.
    private static func modificationDate(of url: URL) -> Date? {
        if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
            return date
        }
        return (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate]
            as? Date
    }
}
