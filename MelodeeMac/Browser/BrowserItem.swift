//
//  BrowserItem.swift
//  Melodee
//

import Foundation
import UniformTypeIdentifiers

/// A folder or file listed in the browser.
struct BrowserItem: Sendable {

    enum Kind: Sendable {
        case folder
        case file(FSFile)
    }

    let url: URL
    let name: String
    let kind: Kind
    let size: Int64?
    let kindDescription: String

    var file: FSFile? {
        if case .file(let file) = kind { file } else { nil }
    }

    var isFolder: Bool {
        if case .folder = kind { true } else { false }
    }

    /// Audio files are played in Melodee. Everything else opens in its own app.
    var isPlayable: Bool {
        file?.type == .audio
    }

    var sizeDescription: String {
        size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--"
    }

    /// Lists a folder's contents, folders first, without blocking the caller.
    static func items(in folderURL: URL) async -> [BrowserItem] {
        await Task.detached(priority: .userInitiated) {
            let objects = FilesystemManager().files(in: folderURL, recursive: false)
            return objects.compactMap(item(for:)).sorted(by: isOrderedBefore)
        }.value
    }

    /// Finds folders and files whose name contains the query, anywhere below `folderURL`.
    static func search(_ query: String, in folderURL: URL) async -> [BrowserItem] {
        await Task.detached(priority: .userInitiated) {
            let results = FilesystemManager().search(matching: query, in: folderURL)
            let objects: [any FilesystemObject] = results.folders + results.files
            return objects.compactMap(item(for:)).sorted(by: isOrderedBefore)
        }.value
    }

    nonisolated private static func item(for object: any FilesystemObject) -> BrowserItem? {
        let url = URL(filePath: object.path)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .localizedTypeDescriptionKey])
        if object is FSDirectory {
            return BrowserItem(
                url: url, name: object.name, kind: .folder, size: nil,
                kindDescription: values?.localizedTypeDescription ?? ""
            )
        } else if let file = object as? FSFile {
            return BrowserItem(
                url: url, name: url.lastPathComponent, kind: .file(file),
                size: values?.fileSize.map(Int64.init),
                kindDescription: values?.localizedTypeDescription
                    ?? UTType(filenameExtension: file.extension)?.localizedDescription ?? ""
            )
        }
        return nil
    }

    nonisolated static func isOrderedBefore(_ lhs: BrowserItem, _ rhs: BrowserItem) -> Bool {
        if lhs.isFolder != rhs.isFolder {
            return lhs.isFolder
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
