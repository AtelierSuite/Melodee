import SwiftUI

enum OnboardingFeature: String, CaseIterable, Identifiable {
    case music
    case video
    case tags
    case trimming
    case files

    var id: String { rawValue }

    var title: String {
        self == .music ? String(format: String(localized: "Onboarding.Title"), "Melodee") : localized("Title")
    }
    var description: String { localized("Description") }

    var symbol: String {
        switch self {
        case .music: "waveform"
        case .video: "play.rectangle.fill"
        case .tags: "tag.fill"
        case .trimming: "timeline.selection"
        case .files: "folder.fill"
        }
    }

    var tint: Color {
        switch self {
        case .music: .accent
        case .video: Color(red: 0.91, green: 0.24, blue: 0.52)
        case .tags: Color(red: 0.94, green: 0.30, blue: 0.30)
        case .trimming: Color(red: 0.10, green: 0.62, blue: 0.52)
        case .files: Color(red: 0.16, green: 0.52, blue: 0.95)
        }
    }

    var partner: Color {
        switch self {
        case .music: Color(red: 0.24, green: 0.16, blue: 0.62)
        case .video: Color(red: 0.52, green: 0.20, blue: 0.84)
        case .tags: Color(red: 0.97, green: 0.52, blue: 0.20)
        case .trimming: Color(red: 0.10, green: 0.46, blue: 0.74)
        case .files: Color(red: 0.10, green: 0.72, blue: 0.88)
        }
    }

    private func localized(_ suffix: String) -> String {
        let key = "Onboarding.\(rawValue.prefix(1).uppercased() + rawValue.dropFirst()).\(suffix)"
        return String(localized: String.LocalizationValue(key))
    }
}
