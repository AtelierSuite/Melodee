import Foundation

/// Common track languages offered in the subtitle and lyrics editor's language picker.
struct SubtitleLanguage: Identifiable, Hashable, Sendable {

    let code: String
    var id: String { code }

    var displayName: String {
        if code.isEmpty {
            return String(localized: "Subtitles.Language.Unspecified")
        }
        return Locale.current.localizedString(forIdentifier: code)?.capitalized(with: .current) ?? code
    }

    static let commonCodes: [String] = [
        "",
        "en",
        "ja",
        "ko",
        "zh-Hans",
        "zh-Hant",
        "vi",
        "es",
        "fr",
        "de",
        "it",
        "pt",
        "ru",
        "ar",
        "hi",
        "th"
    ]

    /// Returns common languages plus `selectedCode` if it's a custom code not already in the list.
    static func options(including selectedCode: String?) -> [SubtitleLanguage] {
        var codes = commonCodes
        if let selected = selectedCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selected.isEmpty,
           !codes.contains(where: { $0.caseInsensitiveCompare(selected) == .orderedSame }) {
            codes.append(selected)
        }
        return codes.map { SubtitleLanguage(code: $0) }
    }
}
