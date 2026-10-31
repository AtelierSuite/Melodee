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

    func delete(_ file: any FilesystemObject) {
        do {
            try manager.removeItem(atPath: file.path)
        } catch {
            debugPrint("Error occurred while deleting file: \(error.localizedDescription)")
        }
    }
}
