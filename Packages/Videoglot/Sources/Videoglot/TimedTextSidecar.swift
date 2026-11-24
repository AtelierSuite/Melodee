import Foundation

/// A sidecar subtitle or synced-lyrics file located alongside a video file.
public struct SidecarTimedTextFile: Identifiable, Hashable, Sendable {

    public let url: URL
    public let format: TimedTextFormat
    public let languageCode: String?
    public let variantLabel: String?

    public var id: String {
        url.path(percentEncoded: false)
    }

    public init(url: URL, format: TimedTextFormat, languageCode: String?, variantLabel: String?) {
        self.url = url
        self.format = format
        self.languageCode = languageCode
        self.variantLabel = variantLabel
    }

    /// A readable label describing the sidecar's language/variant and format.
    public var displayName: String {
        var parts: [String] = []
        if let languageCode,
           let localized = Locale.current.localizedString(forIdentifier: languageCode),
           !localized.isEmpty {
            parts.append(localized.capitalized(with: .current))
        }
        if let variantLabel, !variantLabel.isEmpty {
            parts.append(variantLabel)
        }
        if parts.isEmpty {
            parts.append(format.isLyrics ? "Lyrics" : "Subtitles")
        }
        return "\(parts.joined(separator: " · ")) (\(format.displayName))"
    }

    /// Finds all matching `.srt`, `.vtt`, `.ass`, `.ssa`, and `.lrc` sidecar files in the same folder as `videoURL`.
    public static func discover(for videoURL: URL) -> [SidecarTimedTextFile] {
        let directory = videoURL.deletingLastPathComponent()
        let videoStem = videoURL.deletingPathExtension().lastPathComponent
        let videoStemLower = videoStem.lowercased()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [SidecarTimedTextFile] = []
        for itemURL in contents {
            guard let format = TimedTextFormat(fileExtension: itemURL.pathExtension) else { continue }
            let stem = itemURL.deletingPathExtension().lastPathComponent
            let stemLower = stem.lowercased()
            if stemLower == videoStemLower {
                results.append(SidecarTimedTextFile(url: itemURL, format: format, languageCode: nil, variantLabel: nil))
                continue
            }
            guard stemLower.hasPrefix(videoStemLower) else { continue }
            let suffixStart = stem.index(stem.startIndex, offsetBy: videoStem.count)
            let remainder = stem[suffixStart...]
            guard let first = remainder.first, first == "." || first == "_" || first == "-" else { continue }
            let rawSuffix = String(remainder.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawSuffix.isEmpty else { continue }
            let (languageCode, variantLabel) = parseSuffix(rawSuffix)
            results.append(SidecarTimedTextFile(
                url: itemURL,
                format: format,
                languageCode: languageCode,
                variantLabel: variantLabel
            ))
        }

        return results.sorted { lhs, rhs in
            if lhs.format.isLyrics != rhs.format.isLyrics {
                return !lhs.format.isLyrics
            }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
    }

    /// Suggests a sidecar file URL next to `videoURL` for saving a new track.
    public static func suggestedURL(
        for videoURL: URL,
        format: TimedTextFormat,
        languageCode: String? = nil,
        title: String? = nil
    ) -> URL {
        let directory = videoURL.deletingLastPathComponent()
        let stem = videoURL.deletingPathExtension().lastPathComponent
        var components = [stem]
        if let language = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            components.append(language)
        } else if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            let safe = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            components.append(safe)
        }
        let fileName = components.joined(separator: ".") + "." + format.fileExtension
        return directory.appendingPathComponent(fileName)
    }

    /// Parses suffixes such as `en`, `ja`, `zh-Hans`, `en.forced`, or `Commentary`.
    private static func parseSuffix(_ rawSuffix: String) -> (languageCode: String?, variantLabel: String?) {
        let tokens = rawSuffix.split(whereSeparator: { $0 == "." || $0 == "_" }).map(String.init)
        guard !tokens.isEmpty else { return (nil, nil) }

        if let normalizedLang = normalizedLanguageCode(tokens[0]) {
            let rest = tokens.dropFirst().joined(separator: " ")
            return (normalizedLang, rest.isEmpty ? nil : rest)
        }
        return (nil, tokens.joined(separator: " "))
    }

    /// Recognizes ISO 639-1, ISO 639-2, or BCP-47 language tags like `en`, `jpn`, `en-US`, `zh-Hans`.
    public static func normalizedLanguageCode(_ candidate: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let primary = trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? trimmed
        let primaryLower = primary.lowercased()
        guard primaryLower.count == 2 || primaryLower.count == 3,
              primaryLower.allSatisfy(\.isASCII),
              primaryLower.allSatisfy(\.isLetter) else {
            return nil
        }
        let language = Locale.Language(identifier: trimmed)
        guard let code = language.languageCode,
              Locale.LanguageCode.isoLanguageCodes.contains(code) else {
            return nil
        }
        return trimmed
    }
}
