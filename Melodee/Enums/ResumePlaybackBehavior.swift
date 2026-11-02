import Foundation

/// What happens when playing a file that was previously stopped partway through.
enum ResumePlaybackBehavior: String, CaseIterable, Identifiable {
    case ask
    case startFromBeginning
    case continueFromLastPosition

    static let storageKey = "ResumePlaybackBehavior"

    var id: String { rawValue }

    static var current: ResumePlaybackBehavior {
        UserDefaults.standard.string(forKey: storageKey).flatMap(ResumePlaybackBehavior.init(rawValue:)) ?? .ask
    }
}

/// A file the user chose to play that has a saved position, waiting for them to pick where to start.
struct ResumePlaybackPrompt: Identifiable {
    enum Source {
        case fileBrowser
        case queue
    }

    let id = UUID()
    var file: FSFile
    var addToQueue: Bool
    var playTime: TimeInterval
    var source: Source
}
