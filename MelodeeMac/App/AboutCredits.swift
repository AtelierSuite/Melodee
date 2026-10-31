//
//  AboutCredits.swift
//  Melodee
//

import AppKit

/// Lists the open source packages Melodee uses, with their licenses, in the About window.
enum AboutCredits {

    private struct Dependency: Decodable {
        let name: String
        let licenseText: String
    }

    private struct Wrapper: Decodable {
        let dependencies: [Dependency]
    }

    static func make() -> NSAttributedString {
        let credits = NSMutableAttributedString()
        guard let url = Bundle.main.url(forResource: "Licenses", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let wrapper = try? PropertyListDecoder().decode(Wrapper.self, from: data) else {
            return credits
        }
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        for (index, dependency) in wrapper.dependencies.enumerated() {
            let separator = index == 0 ? "" : "\n\n"
            credits.append(NSAttributedString(string: separator + dependency.name + "\n", attributes: headingAttributes))
            credits.append(NSAttributedString(string: dependency.licenseText, attributes: bodyAttributes))
        }
        return credits
    }
}
