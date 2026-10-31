import Foundation
import Prelude
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Reads and writes tags with Prelude, expanding the tag editor's tokens for each file.
/// Shared by the iPhone tag editor and the Mac inspector.
enum TagFileIO {

    /// - Parameter properties: Raw property values to write after the tag, where an empty array removes the property.
    nonisolated static func save(_ tag: Tag, to file: FSFile, albumArtRemoved: Bool,
                                 properties: [String: [String]] = [:]) async -> Bool {
        return await Task.detached(priority: .userInitiated) {
            // Each save opens its own file, since TagLib files can't be shared across tasks
            guard let tagFile = TagLibFile(path: file.path) else {
                debugPrint("Could not open file \(file.name) for saving")
                return false
            }
            var tag = tag
            // The track number is the only number field that takes a token
            if let track = tag.track {
                tag.track = replaceTokens(track, file: file)
                guard tag.hasValidNumbers else { return false }
            }
            let albumArt = tag.albumArt.flatMap { sanitizedImageData($0) }
            TagWriter.apply(tag, to: tagFile, albumArt: albumArt, albumArtRemoved: albumArtRemoved) {
                replaceTokens($0, file: file)
            }
            for (key, values) in properties {
                tagFile.setValues(values.isEmpty ? nil : values, forProperty: key)
            }
            return tagFile.save()
        }.value
    }

    nonisolated static func removeAllTags(from file: FSFile) async -> Bool {
        return await Task.detached(priority: .userInitiated) {
            guard let tagFile = TagLibFile(path: file.path) else { return false }
            return tagFile.removeAllTags()
        }.value
    }

    nonisolated static func replaceTokens(_ original: String, file: FSFile) -> String {
        guard original.contains("%") else { return original }
        var newString = original
        let componentsDash = file.name.components(separatedBy: "-").map { string in
            string.trimmingCharacters(in: .whitespaces)
        }
        let componentsDot = file.name.components(separatedBy: ".").map { string in
            string.trimmingCharacters(in: .whitespaces)
        }
        var trackNumber = ""
        if let properDigits = Bundle.main.plist(named: "ProperDigit"),
           let trackNumberDigits = self.trackNumber(in: file.name) {
            trackNumberDigits.forEach { character in
                if let digit = properDigits[String(character)] {
                    trackNumber += digit
                } else if character.isNumber {
                    trackNumber += String(character)
                }
            }
        }
        let tokens: [String: String] = [
            "fileName": file.name,
            "folderName": file.containingFolderName(),
            "dashFront": componentsDash[0],
            "dashBack": componentsDash.count >= 2 ? componentsDash[1] : "",
            "dotFront": componentsDot[0],
            "dotBack": componentsDot.count >= 2 ? componentsDot[1] : "",
            "trackNumber": trackNumber
        ]
        for (key, value) in tokens {
            newString = newString.replacingOccurrences(of: "%\(key)%", with: value, options: .caseInsensitive)
        }
        return newString
    }

    nonisolated static func trackNumber(in fileName: String) -> String? {
        if let trackNumberRegex = try? NSRegularExpression(pattern:
    """
    【?([１２３４５６７８９０]*)([⒈⒉⒊⒋⒌⒍⒎⒏⒐⒑]*)([①②③④⑤⑥⑦⑧⑨⑩]*)([0-9]*)】?(.*)
    """) {
            let stringRange = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
            for match in trackNumberRegex.matches(in: fileName, options: [], range: stringRange) {
                for rangeIndex in 0..<match.numberOfRanges {
                    let matchRange = match.range(at: rangeIndex)
                    if matchRange == stringRange { continue }
                    if let substringRange = Range(matchRange, in: fileName) {
                        let capture = String(fileName[substringRange])
                        if capture != "" {
                            return capture
                        }
                    }
                }
            }
        }
        return nil
    }

    nonisolated private static func sanitizedImageData(_ data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        if let pngData = image.pngData() {
            return pngData
        }
        return image.jpegData(compressionQuality: 1.0)
        #else
        guard let bitmap = NSImage(data: data)?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
            ?? bitmap.representation(using: .jpeg, properties: [.compressionFactor: 1.0])
        #endif
    }
}

extension Tag {

    /// Checks the number fields, allowing the track number to be a token that's filled in when saving.
    var hasValidNumbersAllowingTokens: Bool {
        var tag = self
        if tag.track?.uppercased() == "%TRACKNUMBER%" {
            tag.track = nil
        }
        return tag.hasValidNumbers
    }
}
