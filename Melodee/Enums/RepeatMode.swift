import Foundation
import MediaPlayer

enum RepeatMode: String {
    case none
    case single
    case all

    init(remoteRepeatType: MPRepeatType) {
        switch remoteRepeatType {
        case .one: self = .single
        case .all: self = .all
        default: self = .none
        }
    }

    var remoteRepeatType: MPRepeatType {
        switch self {
        case .none: return .off
        case .single: return .one
        case .all: return .all
        }
    }
}
