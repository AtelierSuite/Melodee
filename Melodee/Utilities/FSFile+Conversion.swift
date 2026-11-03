import Audioglot
import Foundation
import Synchronization
import Videoglot

extension FSFile {

    /// Audio formats this file may be converted to, decided by its codec rather than its extension.
    func audioConversionTargets() -> [AudioFormat] {
        guard type == .audio else { return [] }
        return AudioConversionTargetCache.shared.targets(forPath: path)
    }

    /// Containers this video may be copied into, plus audio-only extraction.
    func videoConversionTargets() -> [VideoFormat] {
        guard type == .video else { return [] }
        return VideoFormat.targets(forPathExtension: self.extension)
    }
}

/// Remembers each file's conversion targets so menus don't re-open the file every time they are built.
/// Entries are invalidated when the file's modification date changes.
final class AudioConversionTargetCache: Sendable {

    static let shared = AudioConversionTargetCache()

    private struct Entry {
        let modificationDate: Date?
        let targets: [AudioFormat]
    }

    private let entries = Mutex<[String: Entry]>([:])

    func targets(forPath path: String) -> [AudioFormat] {
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        if let entry = entries.withLock({ $0[path] }), entry.modificationDate == modificationDate {
            return entry.targets
        }
        let targets = Audioglot.availableTargets(for: URL(filePath: path))
        entries.withLock { $0[path] = Entry(modificationDate: modificationDate, targets: targets) }
        return targets
    }
}
