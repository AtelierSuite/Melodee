import Foundation

protocol FilesystemObject: Hashable {
    var name: String { get set }
    var path: String { get set }
}
