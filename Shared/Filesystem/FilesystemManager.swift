import Foundation
import SwiftUI
import ZIPFoundation

@Observable
class FilesystemManager {

    @ObservationIgnored let manager = FileManager.default
    @ObservationIgnored var directory: URL?

    var storageLocation: StorageLocation = .local

    @ObservationIgnored var documentsDirectoryURL: URL?
    @ObservationIgnored var cloudDocumentsDirectoryURL: URL?
    @ObservationIgnored var externalDirectoryURL: URL?

    var files: [any FilesystemObject] = []
    var extractionProgress: Progress?

    init() {
        do {
            documentsDirectoryURL = try FileManager.default
                .url(for: .documentDirectory,
                     in: .userDomainMask,
                     appropriateFor: nil,
                     create: true)
            cloudDocumentsDirectoryURL = FileManager.default
                .url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents")
            directory = documentsDirectoryURL
        } catch {
            debugPrint(error.localizedDescription)
        }
    }

    func files(in url: URL? = nil, recursive: Bool = true) -> [any FilesystemObject] {
        debugPrint("Enumerating files in '\(url == nil ? directory?.absoluteString ?? "": url?.absoluteString ?? "")'.")
        do {
            if let directory = (url == nil ? directory : url), directoryOrFileExists(at: directory) {
                // Determine if we're at the root directory
                let isRootDirectory = (url == nil || url?.path == directory.path)

                // Get contents of directory
                let filesStaged: [any FilesystemObject] = try manager
                    .contentsOfDirectory(at: directory,
                                         includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                                         options: []).compactMap { url in
                        // Hide .Trash directory when at root
                        if isRootDirectory && url.hasDirectoryPath && url.lastPathComponent == ".Trash" {
                            return nil
                        }

                        if url.hasDirectoryPath {
                            return FSDirectory(name: url.lastPathComponent,
                                               path: url.path,
                                               files: recursive ? files(in: url, recursive: true) : [])
                        } else {
                            // Get actual path for dataless files
                            let fileURL: URL = fileURL(for: url)
                            var file = FSFile(name: fileURL.deletingPathExtension().lastPathComponent,
                                              extension: fileURL.pathExtension.lowercased(),
                                              path: fileURL.path,
                                              type: .notSet)
                            if let fileType = fileType(for: fileURL) {
                                file.type = fileType
                                return file
                            } else {
                                return nil
                            }
                        }
                    }
                // Sort folders above files
                var filesCombined: [any FilesystemObject] = filesStaged.filter({ $0 is FSDirectory })
                    .sorted { $0.name < $1.name }
                let filesOnly: [any FilesystemObject] = filesStaged.filter({ $0 is FSFile })
                    .sorted { $0.name < $1.name }
                    .sorted { lhs, rhs in
                        if let lhs = lhs as? FSFile, let rhs = rhs as? FSFile {
                            return lhs.type.rawValue < rhs.type.rawValue
                        }
                        return false
                    }
                filesCombined.append(contentsOf: filesOnly)
                return filesCombined
            }
        } catch {
            debugPrint(error.localizedDescription)
        }
        return []
    }

    /// Recursively searches for folders and files whose name matches the query, starting at `url`.
    /// Folders and files are returned separately so they can be displayed in their own sections.
    func search(matching query: String, in url: URL) -> (folders: [FSDirectory], files: [FSFile]) {
        var matchedFolders: [FSDirectory] = []
        var matchedFiles: [FSFile] = []
        func walk(_ directoryURL: URL) {
            for object in files(in: directoryURL, recursive: false) {
                if let directory = object as? FSDirectory {
                    if directory.name.localizedCaseInsensitiveContains(query) {
                        matchedFolders.append(directory)
                    }
                    walk(URL(fileURLWithPath: directory.path))
                } else if let file = object as? FSFile,
                          file.name.localizedCaseInsensitiveContains(query) {
                    matchedFiles.append(file)
                }
            }
        }
        walk(url)
        return (matchedFolders, matchedFiles)
    }

    func fileURL(for url: URL) -> URL {
        var fileName: String = url.lastPathComponent
        if fileName.hasPrefix(".") && fileName.hasSuffix(".icloud") {
            let fromIndex = fileName.index(fileName.startIndex, offsetBy: 1)
            let toIndex = fileName.index(fileName.endIndex, offsetBy: -7)
            fileName = String(fileName[fromIndex..<toIndex])
        }
        return url.deletingLastPathComponent().appending(path: fileName)
    }

    func fileType(for url: URL) -> FileType? {
        let fileExtension = url.pathExtension.lowercased()
        if FilesystemManager.audioExtensions.contains(fileExtension) { return .audio }
        if FilesystemManager.videoExtensions.contains(fileExtension) { return .video }
        switch fileExtension {
        case "png", "jpg", "jpeg", "tif", "tiff", "heic": return .image
        case "txt": return .text
        case "pdf": return .pdf
        case "zip": return .zip
        case "mpl": return .playlist
        case "icloud": return fileType(for: url.deletingPathExtension())
        default: return nil
        }
    }

    static func fileType(forExtension fileExtension: String) -> FileType {
        if audioExtensions.contains(fileExtension) { return .audio }
        if videoExtensions.contains(fileExtension) { return .video }
        switch fileExtension {
        case "png", "jpg", "jpeg", "tif", "tiff", "heic": return .image
        case "txt": return .text
        case "pdf": return .pdf
        case "zip": return .zip
        case "mpl": return .playlist
        default: return .notSet
        }
    }

    /// Audio file extensions recognized by the file browser. SFBAudioEngine decodes all of these.
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "wave", "aif", "aiff", "aifc", "caf",
        "alac", "flac", "ogg", "oga", "opus", "spx",
        "ape", "wv", "mpc", "tta", "shn",
        "dsf", "dff"
    ]

    /// Video file extensions recognized by the file browser. AVPlayer decodes all of these.
    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "3gp", "3g2"
    ]

    func createDirectory(at directoryPath: String) {
        let url = URL(fileURLWithPath: directoryPath)
        if !directoryOrFileExists(at: url) {
            do {
                try FileManager.default.createDirectory(atPath: directoryPath,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
            } catch {
                debugPrint("Error occurred while creating directory: \(error.localizedDescription)")
            }
        }
    }

    func createPlaceholders() {
        let placeholderFilename = NSLocalizedString("Shared.DropFilesFileName",
                                                    comment: "")
        if let documentsDirectoryURL {
            manager
                .createFile(
                    atPath: "\(documentsDirectoryURL.path())\(placeholderFilename)",
                    contents: Data()
                )
        }
        if let cloudDocumentsDirectoryURL {
            let placeholderFileURL: URL = cloudDocumentsDirectoryURL.appending(path: placeholderFilename)
            NSFileCoordinator().coordinate(writingItemAt: placeholderFileURL, error: .none) { url in
                self.manager.createFile(
                    atPath: url.path(percentEncoded: false),
                    contents: Data()
                )
            }
        }
    }

    func directoryOrFileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func rename(file: FSFile, newName: String) {
        do {
            try manager
                .moveItem(atPath: file.path,
                          toPath: "\(file.containingFolderPath())\(newName).\(file.extension)")
        } catch {
            debugPrint("Error occurred while renaming file: \(error.localizedDescription)")
        }
    }

    func rename(directory: FSDirectory, newName: String) {
        do {
            try manager
                .moveItem(atPath: directory.path,
                          toPath: "\(directory.containingFolderPath())\(newName)/")
        } catch {
            debugPrint("Error occurred while renaming directory: \(error.localizedDescription)")
        }
    }

    func extractFiles(file: FSFile,
                      encoding: String.Encoding = .shiftJIS,
                      onProgressUpdate: @escaping @Sendable () -> Void,
                      onError: @escaping @Sendable (String) -> Void,
                      onCompletion: @escaping @Sendable () -> Void) {
        let destinationURL = URL(filePath: file.path).deletingPathExtension()
        let destinationDirectory = destinationURL.path().removingPercentEncoding ?? destinationURL.path()
        debugPrint("Attempting to create directory \(destinationDirectory)...")
        createDirectory(at: destinationDirectory)
        debugPrint("Attempting to extract ZIP to \(destinationDirectory)...")
        extractionProgress = Progress()
        let extractionProgressRef = extractionProgress
        nonisolated(unsafe) let managerRef = self
        DispatchQueue.global(qos: .background).async {
            let observation = extractionProgressRef?.observe(\.fractionCompleted) { _, _ in
                DispatchQueue.main.async {
                    onProgressUpdate()
                }
            }
            do {
                try FileManager().unzipItem(at: URL(filePath: file.path),
                                            to: URL(filePath: destinationDirectory),
                                            skipCRC32: true,
                                            progress: extractionProgressRef,
                                            pathEncoding: encoding)
                DispatchQueue.main.async {
                    onCompletion()
                }
            } catch {
                if !(extractionProgressRef?.isCancelled ?? false) {
                    debugPrint("Error occurred while extracting ZIP: \(error.localizedDescription)")
                    if encoding == .shiftJIS {
                        debugPrint("Attempting extraction with UTF-8...")
                        managerRef.extractFiles(file: file,
                                                encoding: .utf8,
                                                onProgressUpdate: onProgressUpdate,
                                                onError: onError,
                                                onCompletion: onCompletion)
                    } else {
                        DispatchQueue.main.async {
                            onError(error.localizedDescription)
                        }
                    }
                } else {
                    debugPrint("ZIP extraction cancelled!")
                }
            }
            observation?.invalidate()
        }
    }

    /// A file for a URL dropped into the app, if Melodee recognizes its type.
    static func file(at url: URL) -> FSFile? {
        let type = fileType(forExtension: url.pathExtension.lowercased())
        guard type != .notSet else { return nil }
        return FSFile(name: url.deletingPathExtension().lastPathComponent,
                      extension: url.pathExtension.lowercased(),
                      path: url.path(percentEncoded: false),
                      type: type)
    }

    /// The files to queue for URLs dropped on the Now Playing bar: playable files, and the playable files
    /// directly inside dropped folders.
    static func playableFiles(for urls: [URL], types: Set<FileType>) -> [FSFile] {
        urls.flatMap { url -> [FSFile] in
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                return contents
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    .compactMap(file(at:))
                    .filter { types.contains($0.type) }
            }
            return file(at: url).map { types.contains($0.type) ? [$0] : [] } ?? []
        }
    }

    // MARK: - Moving

    /// Moves files and folders into a folder, giving each a numbered name if the folder already has one with
    /// the same name. Items already in the folder, and folders dropped into themselves, are skipped.
    /// Returns the normalized old path of each moved item mapped to its new path.
    @discardableResult
    static func move(_ urls: [URL], into folderURL: URL) -> (movedPaths: [String: String], failures: [Error]) {
        var movedPaths: [String: String] = [:]
        var failures: [Error] = []
        let folderPath = normalizedPath(folderURL.path(percentEncoded: false))
        for url in urls {
            let path = normalizedPath(url.path(percentEncoded: false))
            let parentPath = normalizedPath(url.deletingLastPathComponent().path(percentEncoded: false))
            guard parentPath != folderPath, folderPath != path, !folderPath.hasPrefix(path + "/") else { continue }
            let destination = uniqueDestination(for: url, in: folderURL)
            do {
                try FileManager.default.moveItem(at: url, to: destination)
                movedPaths[path] = destination.path(percentEncoded: false)
            } catch {
                failures.append(error)
            }
        }
        return (movedPaths, failures)
    }

    /// A URL in the folder for the item, adding a number to its name when the name is taken.
    static func uniqueDestination(for url: URL, in folderURL: URL) -> URL {
        let baseName = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension
        var destination = folderURL.appending(path: url.lastPathComponent)
        var copyNumber = 2
        while FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            let name = pathExtension.isEmpty ? "\(baseName) \(copyNumber)" : "\(baseName) \(copyNumber).\(pathExtension)"
            destination = folderURL.appending(path: name)
            copyNumber += 1
        }
        return destination
    }

    /// Where a path ends up after a move, including files inside a moved folder. Nil if it didn't move.
    static func movedPath(for path: String, in movedPaths: [String: String]) -> String? {
        let path = normalizedPath(path)
        if let newPath = movedPaths[path] {
            return newPath
        }
        for (oldPath, newPath) in movedPaths where path.hasPrefix(oldPath + "/") {
            return newPath + path.dropFirst(oldPath.count)
        }
        return nil
    }

    /// Normalizes a path so that paths to the same file compare equal.
    static func normalizedPath(_ path: String) -> String {
        var path = URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
        if path.hasPrefix("/private/var/") {
            path = String(path.dropFirst("/private".count))
        }
        if path.count > 1 && path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        return path
    }

    func delete(_ file: any FilesystemObject) {
        do {
            try manager.removeItem(atPath: file.path)
        } catch {
            debugPrint("Error occurred while deleting file: \(error.localizedDescription)")
        }
    }
}
