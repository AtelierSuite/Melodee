import Foundation
import SwiftUI

enum FileType: String, Codable {
    case audio
    case video
    case image
    case text
    case pdf
    case zip
    case playlist
    case notSet

    func icon() -> Image {
        switch self {
        case .audio: return Image(systemName: "music.note")
        case .video: return Image(systemName: "film")
        case .image: return Image(systemName: "photo")
        case .pdf: return Image(systemName: "doc.richtext")
        case .text: return Image(systemName: "doc.text")
        case .zip: return Image(systemName: "doc.zipper")
        case .playlist: return Image(systemName: "music.note.list")
        case .notSet: return Image(systemName: "doc")
        }
    }

    var iconColor: Color {
        switch self {
        case .audio: return .blue
        case .video: return .purple
        case .image: return .orange
        case .pdf: return .red
        case .text: return .teal
        case .zip: return .secondary
        case .playlist: return .pink
        case .notSet: return .secondary
        }
    }
}
