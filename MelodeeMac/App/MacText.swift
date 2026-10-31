//
//  MacText.swift
//  Melodee
//

import Foundation

/// Looks up Mac-only strings, which live in their own table so the iOS catalog stays untouched.
enum MacText {

    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: "Mac")
    }

    /// Looks up strings shared with the iPhone app, such as the tag field names.
    static func shared(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }
}
