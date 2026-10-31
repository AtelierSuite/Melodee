import Foundation

extension Bundle {

    func plist(named filename: String) -> [String: String]? {
        let filename = filename.replacingOccurrences(of: ".plist", with: "")
        if let path = self.path(forResource: filename, ofType: "plist") {
            return NSDictionary(contentsOfFile: path)! as? [String: String]
        } else {
            return nil
        }
    }

}
