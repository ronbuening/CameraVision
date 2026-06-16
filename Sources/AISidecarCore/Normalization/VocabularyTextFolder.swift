import Foundation

/// Text folding used for vocabulary synonym and canonical-term matching.
public enum VocabularyTextFolder {
    /// Apply NFC, case folding, and whitespace collapse without stemming or diacritic folding.
    public static func fold(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }
}
