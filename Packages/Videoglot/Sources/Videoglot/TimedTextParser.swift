import Foundation

/// Parses and serializes timed-text files (SRT, WebVTT, ASS/SSA, LRC).
public enum TimedTextCodec {

    // MARK: - Decoding

    /// Reads and parses a timed-text file from disk.
    public static func parse(contentsOf url: URL) throws -> TimedTextDocument {
        let data = try Data(contentsOf: url)
        let format = TimedTextFormat(fileExtension: url.pathExtension) ?? detectFormat(from: data)
        return parse(data: data, format: format)
    }

    /// Parses raw bytes as the given timed-text format, trying UTF-8 and common legacy encodings.
    public static func parse(data: Data, format: TimedTextFormat) -> TimedTextDocument {
        let text = decodeString(from: data)
        return parse(string: text, format: format)
    }

    /// Parses a string as the given timed-text format.
    public static func parse(string: String, format: TimedTextFormat) -> TimedTextDocument {
        let normalized = stripBOM(string)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        switch format {
        case .srt: return parseSRT(normalized)
        case .vtt: return parseVTT(normalized)
        case .lrc: return parseLRC(normalized)
        case .ass, .ssa: return parseASS(normalized)
        }
    }

    /// Parses embedded lyrics text: if it contains LRC timestamps, parses it as synced lyrics;
    /// otherwise returns a document carrying `unsyncedText`.
    public static func parseEmbeddedLyrics(_ rawText: String) -> TimedTextDocument {
        let normalized = stripBOM(rawText)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lrcDocument = parseLRC(normalized)
        if !lrcDocument.cues.isEmpty {
            return lrcDocument
        }
        return TimedTextDocument(
            cues: [],
            isLyrics: true,
            unsyncedText: normalized.isEmpty ? nil : normalized
        )
    }

    // MARK: - Encoding

    /// Serializes a timed-text document to the requested format.
    public static func serialize(_ document: TimedTextDocument, as format: TimedTextFormat) -> String {
        var sorted = document
        sorted.sortCues()
        switch format {
        case .srt: return serializeSRT(sorted)
        case .vtt: return serializeVTT(sorted)
        case .lrc: return serializeLRC(sorted)
        case .ass, .ssa: return serializeSRT(sorted)
        }
    }

    /// Writes a timed-text document to disk as UTF-8.
    public static func write(_ document: TimedTextDocument, to url: URL, format: TimedTextFormat) throws {
        let output = serialize(document, as: format)
        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - SRT

    private static func parseSRT(_ text: String) -> TimedTextDocument {
        var cues: [TimedTextCue] = []
        let blocks = splitBlankLineBlocks(text)
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard let arrowIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            guard let (start, end) = parseTimestampRange(lines[arrowIndex]) else { continue }
            let bodyLines = lines[(arrowIndex + 1)...]
                .map { stripHTMLTags($0) }
            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            cues.append(TimedTextCue(startTime: start, endTime: end, text: body))
        }
        var doc = TimedTextDocument(cues: cues, isLyrics: false)
        doc.sortCues()
        return doc
    }

    private static func serializeSRT(_ document: TimedTextDocument) -> String {
        var parts: [String] = []
        for (index, cue) in document.cues.enumerated() {
            let trimmed = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let start = formatTimestamp(cue.startTime, separator: ",")
            let end = formatTimestamp(cue.endTime, separator: ",")
            parts.append("\(index + 1)\n\(start) --> \(end)\n\(trimmed)")
        }
        return parts.joined(separator: "\n\n") + (parts.isEmpty ? "" : "\n")
    }

    // MARK: - WebVTT

    private static func parseVTT(_ text: String) -> TimedTextDocument {
        var cues: [TimedTextCue] = []
        var title: String?
        var languageCode: String?
        let blocks = splitBlankLineBlocks(text)
        for (blockIndex, block) in blocks.enumerated() {
            let lines = block.components(separatedBy: "\n")
            if blockIndex == 0, let first = lines.first, first.hasPrefix("WEBVTT") {
                let remainder = first.dropFirst("WEBVTT".count).trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty {
                    let cleaned = remainder.hasPrefix("-") ? String(remainder.dropFirst()).trimmingCharacters(in: .whitespaces) : remainder
                    if !cleaned.isEmpty { title = cleaned }
                }
                for headerLine in lines.dropFirst() {
                    if headerLine.lowercased().hasPrefix("language:") {
                        let code = headerLine.dropFirst("language:".count).trimmingCharacters(in: .whitespaces)
                        if !code.isEmpty { languageCode = code }
                    }
                }
                continue
            }
            if let first = lines.first {
                let upper = first.trimmingCharacters(in: .whitespaces).uppercased()
                if upper.hasPrefix("NOTE") || upper.hasPrefix("STYLE") || upper.hasPrefix("REGION") {
                    continue
                }
            }
            guard let arrowIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            guard let (start, end) = parseTimestampRange(lines[arrowIndex]) else { continue }
            let body = lines[(arrowIndex + 1)...]
                .map { stripVTTTags($0) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            cues.append(TimedTextCue(startTime: start, endTime: end, text: body))
        }
        var doc = TimedTextDocument(cues: cues, title: title, languageCode: languageCode, isLyrics: false)
        doc.sortCues()
        return doc
    }

    private static func serializeVTT(_ document: TimedTextDocument) -> String {
        var header = "WEBVTT"
        if let title = document.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            header += " - \(title)"
        }
        var headerLines = [header]
        if let language = document.languageCode?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            headerLines.append("Language: \(language)")
        }
        var blocks = [headerLines.joined(separator: "\n")]
        for cue in document.cues {
            let trimmed = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let start = formatTimestamp(cue.startTime, separator: ".")
            let end = formatTimestamp(cue.endTime, separator: ".")
            blocks.append("\(start) --> \(end)\n\(trimmed)")
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: - ASS / SSA

    private static func parseASS(_ text: String) -> TimedTextDocument {
        var title: String?
        var cues: [TimedTextCue] = []
        var inEvents = false
        var startIndex = 1
        var endIndex = 2
        var textIndex = 9
        var columnCount = 10

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inEvents = line.caseInsensitiveCompare("[Events]") == .orderedSame
                continue
            }
            if !inEvents {
                if line.lowercased().hasPrefix("title:") {
                    let value = line.dropFirst("title:".count).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { title = value }
                }
                continue
            }
            if line.lowercased().hasPrefix("format:") {
                let columns = line.dropFirst("format:".count)
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                if let s = columns.firstIndex(of: "start") { startIndex = s }
                if let e = columns.firstIndex(of: "end") { endIndex = e }
                if let t = columns.firstIndex(of: "text") { textIndex = t }
                columnCount = columns.count
                continue
            }
            guard line.lowercased().hasPrefix("dialogue:") else { continue }
            let payload = String(line.dropFirst("dialogue:".count)).trimmingCharacters(in: .whitespaces)
            let fields = splitASSFields(payload, maxFields: max(columnCount, textIndex + 1))
            guard fields.indices.contains(startIndex),
                  fields.indices.contains(endIndex),
                  fields.indices.contains(textIndex),
                  let start = parseTimestamp(fields[startIndex]),
                  let end = parseTimestamp(fields[endIndex]) else { continue }
            let cleaned = stripASSOverrides(fields[textIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            cues.append(TimedTextCue(startTime: start, endTime: max(start, end), text: cleaned))
        }

        var doc = TimedTextDocument(cues: cues, title: title, isLyrics: false)
        doc.sortCues()
        return doc
    }

    private static func splitASSFields(_ payload: String, maxFields: Int) -> [String] {
        var result: [String] = []
        var currentStart = payload.startIndex
        while result.count < maxFields - 1,
              let comma = payload[currentStart...].firstIndex(of: ",") {
            result.append(String(payload[currentStart..<comma]).trimmingCharacters(in: .whitespaces))
            currentStart = payload.index(after: comma)
        }
        result.append(String(payload[currentStart...]))
        return result
    }

    private static func stripASSOverrides(_ raw: String) -> String {
        var output = ""
        var depth = 0
        for char in raw {
            if char == "{" {
                depth += 1
            } else if char == "}" && depth > 0 {
                depth -= 1
            } else if depth == 0 {
                output.append(char)
            }
        }
        return output
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
    }

    // MARK: - LRC

    private static func parseLRC(_ text: String) -> TimedTextDocument {
        var title: String?
        var artist: String?
        var languageCode: String?
        var offsetSeconds: TimeInterval = 0

        // Entries include empty-text lines, which act as explicit end markers in LRC files.
        var entries: [(time: TimeInterval, text: String)] = []

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            var timestamps: [TimeInterval] = []
            var cursor = line.startIndex
            var consumedAnyTag = false

            while cursor < line.endIndex, line[cursor] == "[",
                  let closing = line[cursor...].firstIndex(of: "]") {
                let tagContent = String(line[line.index(after: cursor)..<closing])
                if let time = parseLRCTimestamp(tagContent) {
                    timestamps.append(time)
                    consumedAnyTag = true
                    cursor = line.index(after: closing)
                } else if timestamps.isEmpty, let colon = tagContent.firstIndex(of: ":") {
                    let key = tagContent[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = tagContent[tagContent.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    switch key {
                    case "ti": if !value.isEmpty { title = value }
                    case "ar": if !value.isEmpty { artist = value }
                    case "la": if !value.isEmpty { languageCode = value }
                    case "offset":
                        if let ms = Double(value) {
                            // Standard LRC offset is in ms: positive shifts lyrics earlier.
                            offsetSeconds = -ms / 1000.0
                        }
                    default: break
                    }
                    consumedAnyTag = true
                    cursor = line.index(after: closing)
                    break
                } else {
                    break
                }
            }

            guard consumedAnyTag, !timestamps.isEmpty else { continue }
            let rawText = String(line[cursor...]).trimmingCharacters(in: .whitespaces)
            let cleanedText = stripEnhancedLRCTags(rawText)
            for time in timestamps {
                entries.append((max(0, time + offsetSeconds), cleanedText))
            }
        }

        entries.sort { $0.time < $1.time }

        var cues: [TimedTextCue] = []
        for index in entries.indices {
            let entry = entries[index]
            guard !entry.text.isEmpty else { continue }
            let endTime: TimeInterval
            if let next = entries[(index + 1)...].first(where: { $0.time > entry.time }) {
                endTime = next.time
            } else {
                endTime = entry.time + 5.0
            }
            cues.append(TimedTextCue(startTime: entry.time, endTime: max(entry.time + 0.25, endTime), text: entry.text))
        }

        return TimedTextDocument(
            cues: cues,
            title: title,
            languageCode: languageCode,
            artist: artist,
            isLyrics: true
        )
    }

    private static func serializeLRC(_ document: TimedTextDocument) -> String {
        var lines: [String] = []
        if let title = document.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append("[ti:\(title)]")
        }
        if let artist = document.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
            lines.append("[ar:\(artist)]")
        }
        if let language = document.languageCode?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            lines.append("[la:\(language)]")
        }
        for (index, cue) in document.cues.enumerated() {
            let trimmed = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let stamp = formatLRCTimestamp(cue.startTime)
            for subline in trimmed.components(separatedBy: "\n") {
                lines.append("[\(stamp)]\(subline)")
            }
            let nextStart = (index + 1 < document.cues.count) ? document.cues[index + 1].startTime : nil
            if let nextStart {
                if cue.endTime < nextStart - 0.5 {
                    lines.append("[\(formatLRCTimestamp(cue.endTime))]")
                }
            } else if cue.endTime > cue.startTime {
                lines.append("[\(formatLRCTimestamp(cue.endTime))]")
            }
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    private static func parseLRCTimestamp(_ raw: String) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Accept mm:ss.xx, mm:ss.xxx, mm:ss:xx, or mm:ss
        let parts = trimmed.components(separatedBy: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let minutes = Double(parts[0]), minutes >= 0 else { return nil }
        if parts.count == 3 {
            guard let seconds = Double(parts[1]), let frac = Double(parts[2]) else { return nil }
            let divisor = parts[2].count >= 3 ? 1000.0 : 100.0
            return minutes * 60.0 + seconds + frac / divisor
        }
        let secString = parts[1].replacingOccurrences(of: ",", with: ".")
        guard let seconds = Double(secString), seconds >= 0 else { return nil }
        return minutes * 60.0 + seconds
    }

    private static func formatLRCTimestamp(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let totalCentiseconds = Int((clamped * 100.0).rounded())
        let minutes = totalCentiseconds / 6000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }

    private static func stripEnhancedLRCTags(_ text: String) -> String {
        // Strips inline word timestamps like <00:12.34>
        guard text.contains("<") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "<",
               let close = text[index...].firstIndex(of: ">") {
                let inside = String(text[text.index(after: index)..<close])
                if parseLRCTimestamp(inside) != nil {
                    index = text.index(after: close)
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    // MARK: - Shared timestamp & text helpers

    private static func parseTimestampRange(_ line: String) -> (TimeInterval, TimeInterval)? {
        guard let range = line.range(of: "-->") else { return nil }
        let lhs = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let rhsToken = line[range.upperBound...]
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? ""
        guard let start = parseTimestamp(lhs), let end = parseTimestamp(rhsToken) else { return nil }
        return (start, max(start, end))
    }

    /// Parses `HH:MM:SS,mmm`, `HH:MM:SS.mmm`, `MM:SS.mmm`, or `H:MM:SS.cc`.
    public static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 2 {
            guard let minutes = Double(parts[0]), let seconds = Double(parts[1]),
                  minutes >= 0, seconds >= 0 else { return nil }
            return minutes * 60.0 + seconds
        }
        guard let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]),
              hours >= 0, minutes >= 0, seconds >= 0 else { return nil }
        return hours * 3600.0 + minutes * 60.0 + seconds
    }

    /// Formats `time` as `HH:MM:SS<separator>mmm`.
    public static func formatTimestamp(_ time: TimeInterval, separator: String = ".") -> String {
        let clamped = max(0, time)
        let totalMillis = Int((clamped * 1000.0).rounded())
        let hours = totalMillis / 3_600_000
        let minutes = (totalMillis / 60_000) % 60
        let seconds = (totalMillis / 1_000) % 60
        let millis = totalMillis % 1_000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, seconds, separator, millis)
    }

    private static func splitBlankLineBlocks(_ text: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: "\n"))
                    current.removeAll()
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            blocks.append(current.joined(separator: "\n"))
        }
        return blocks
    }

    private static func stripHTMLTags(_ text: String) -> String {
        stripAngleBracketTags(text)
    }

    private static func stripVTTTags(_ text: String) -> String {
        stripAngleBracketTags(text)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func stripAngleBracketTags(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var result = ""
        var inTag = false
        for char in text {
            if char == "<" {
                inTag = true
            } else if char == ">", inTag {
                inTag = false
            } else if !inTag {
                result.append(char)
            }
        }
        return result
    }

    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    private static func decodeString(from data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        if let shiftJIS = String(data: data, encoding: .shiftJIS) { return shiftJIS }
        if let win1252 = String(data: data, encoding: .windowsCP1252) { return win1252 }
        return String(decoding: data, as: UTF8.self)
    }

    private static func detectFormat(from data: Data) -> TimedTextFormat {
        let preview = stripBOM(decodeString(from: data.prefix(512))).trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.hasPrefix("WEBVTT") { return .vtt }
        if preview.contains("[Script Info]") || preview.contains("[Events]") { return .ass }
        if preview.contains("-->") { return .srt }
        return .lrc
    }
}
