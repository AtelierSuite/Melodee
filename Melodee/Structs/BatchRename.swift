import Foundation

struct BatchRenamePresentation: Identifiable {
    let id = UUID()
    let files: [FSFile]
}

enum BatchRenameMode: String, CaseIterable, Identifiable {
    case replace
    case keepFront
    case keepBack

    var id: String { rawValue }
}

enum BatchRenameSplitOccurrence: String, CaseIterable, Identifiable {
    case first
    case last

    var id: String { rawValue }
}

enum BatchRenameNumberPosition: String, CaseIterable, Identifiable {
    case before
    case after

    var id: String { rawValue }
}

/// The set of rules applied to the base name (without extension) of every file in a batch rename.
struct BatchRenameRules {
    var mode: BatchRenameMode = .replace

    // Replace
    var findText: String = ""
    var replaceText: String = ""
    var isCaseSensitive: Bool = false
    var isRegularExpression: Bool = false

    // Split
    var delimiter: String = " - "
    var splitOccurrence: BatchRenameSplitOccurrence = .first

    // Extras
    var prefix: String = ""
    var suffix: String = ""
    var trimsWhitespace: Bool = true
    var isNumbering: Bool = false
    var numberStart: Int = 1
    var numberDigits: Int = 2
    var numberSeparator: String = " "
    var numberPosition: BatchRenameNumberPosition = .before

    /// Returns true when regular expression matching is on and the find text is not a valid pattern.
    var isRegularExpressionInvalid: Bool {
        mode == .replace && isRegularExpression && !findText.isEmpty && regularExpression() == nil
    }

    func regularExpression() -> NSRegularExpression? {
        try? NSRegularExpression(pattern: findText,
                                 options: isCaseSensitive ? [] : [.caseInsensitive])
    }

    /// Applies the rules to a base name. `index` is the position of the file within the batch,
    /// used for sequential numbering.
    func apply(to name: String, index: Int, regex: NSRegularExpression? = nil) -> String {
        var newName = name

        switch mode {
        case .replace:
            if !findText.isEmpty {
                if isRegularExpression {
                    if let regex = regex ?? regularExpression() {
                        newName = regex.stringByReplacingMatches(
                            in: newName,
                            range: NSRange(newName.startIndex..., in: newName),
                            withTemplate: replaceText
                        )
                    }
                } else {
                    newName = newName.replacingOccurrences(
                        of: findText,
                        with: replaceText,
                        options: isCaseSensitive ? [] : [.caseInsensitive]
                    )
                }
            }
        case .keepFront, .keepBack:
            if !delimiter.isEmpty,
               let range = newName.range(of: delimiter,
                                         options: splitOccurrence == .last ? [.backwards] : []) {
                newName = mode == .keepFront
                    ? String(newName[..<range.lowerBound])
                    : String(newName[range.upperBound...])
            }
        }

        if trimsWhitespace {
            newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        newName = prefix + newName + suffix

        if isNumbering {
            let number = String(format: "%0\(max(1, numberDigits))d", numberStart + index)
            newName = numberPosition == .before
                ? number + numberSeparator + newName
                : newName + numberSeparator + number
        }

        return newName
    }
}

enum BatchRenameStatus: Equatable {
    case unchanged
    case willRename
    case empty
    case invalidName
    case conflictsWithExistingFile
    case conflictsWithinBatch

    var isProblem: Bool {
        switch self {
        case .unchanged, .willRename: return false
        default: return true
        }
    }
}

struct BatchRenameItem: Identifiable {
    var file: FSFile
    var newName: String
    var status: BatchRenameStatus

    var id: String { file.path }

    /// The file's extension as it appears on disk (FSFile.extension is lowercased).
    var originalExtension: String {
        URL(filePath: file.path).pathExtension
    }

    var newFileName: String {
        BatchRenamePlanner.fileName(base: newName, extension: originalExtension)
    }
}

enum BatchRenamePlanner {

    static func fileName(base: String, extension fileExtension: String) -> String {
        fileExtension.isEmpty ? base : "\(base).\(fileExtension)"
    }

    /// Keys used to compare file names. Comparison is case-insensitive since iCloud Drive and
    /// external drives are commonly case-insensitive.
    static func comparisonKey(_ fileName: String) -> String {
        fileName.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Builds the preview of the batch rename, flagging empty results and name collisions.
    static func plan(files: [FSFile], rules: BatchRenameRules) -> [BatchRenameItem] {
        let regex = rules.isRegularExpression ? rules.regularExpression() : nil
        var items: [BatchRenameItem] = files.enumerated().map { index, file in
            let newName = rules.apply(to: file.name, index: index, regex: regex)
            let status: BatchRenameStatus
            if newName == file.name {
                status = .unchanged
            } else if newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                status = .empty
            } else if newName.contains("/") || newName.contains(":") ||
                        newName.hasPrefix(".") {
                status = .invalidName
            } else {
                status = .willRename
            }
            return BatchRenameItem(file: file, newName: newName, status: status)
        }

        // Group by containing folder, since collisions only matter within the same folder
        let indicesByFolder = Dictionary(grouping: items.indices) { items[$0].file.containingFolderPath() }
        for (folderPath, indices) in indicesByFolder {
            // Names in the folder that will still be occupied after the batch completes
            let renamingKeys = Set(indices.filter { items[$0].status == .willRename }
                .map { comparisonKey(URL(filePath: items[$0].file.path).lastPathComponent) })
            let remainingKeys = Set(existingFileNames(in: folderPath).map(comparisonKey))
                .subtracting(renamingKeys)

            var targetCounts: [String: Int] = [:]
            for index in indices where items[index].status != .empty && items[index].status != .invalidName {
                let key = comparisonKey(items[index].status == .unchanged
                                        ? URL(filePath: items[index].file.path).lastPathComponent
                                        : items[index].newFileName)
                targetCounts[key, default: 0] += 1
            }

            for index in indices where items[index].status == .willRename {
                let key = comparisonKey(items[index].newFileName)
                if (targetCounts[key] ?? 0) > 1 {
                    items[index].status = .conflictsWithinBatch
                } else if remainingKeys.contains(key) {
                    items[index].status = .conflictsWithExistingFile
                }
            }
        }

        return items
    }

    /// Returns the names of everything in a folder, including hidden files, folders and files
    /// that are not part of the batch.
    static func existingFileNames(in folderPath: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folderPath)) ?? []
        return names.map { name in
            // Map iCloud placeholders (.Name.ext.icloud) to the name of the file they represent
            if name.hasPrefix(".") && name.hasSuffix(".icloud") && name.count > 8 {
                return String(name.dropFirst().dropLast(7))
            }
            return name
        }
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
}

struct BatchRenameFailure: Identifiable {
    let id = UUID()
    let fileName: String
    let reason: String
}

struct BatchRenameResult {
    /// Maps normalized old paths to new paths for every file that was renamed.
    var renamedPaths: [String: String] = [:]
    var failures: [BatchRenameFailure] = []
}
