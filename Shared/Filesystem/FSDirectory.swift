import Foundation

struct FSDirectory: FilesystemObject {

    var name: String
    var path: String
    var files: [any FilesystemObject]

    static func == (lhs: FSDirectory, rhs: FSDirectory) -> Bool {
        lhs.path == rhs.path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    func containingFolderPath() -> String {
        let url = URL(filePath: path)
        return url.deletingLastPathComponent().path(percentEncoded: false)
    }

    func containingFolderName() -> String {
        let url = URL(filePath: containingFolderPath())
        return url.lastPathComponent
    }
}
