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

    /// Build the guarded fallback lookup key for model-style punctuation variants.
    static func separatorInsensitiveFold(_ value: String) -> String {
        let scalars = Array(
            value
                .precomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .unicodeScalars)
        var tokens: [String] = []
        var current = String.UnicodeScalarView()
        var index = scalars.startIndex

        func appendCurrentToken() {
            guard !current.isEmpty else {
                return
            }
            tokens.append(String(current))
            current.removeAll(keepingCapacity: true)
        }

        while index < scalars.endIndex {
            let scalar = scalars[index]
            if CharacterSet.alphanumerics.contains(scalar) {
                current.append(scalar)
            } else if scalar == "&" {
                appendCurrentToken()
                tokens.append("and")
            } else if isApostrophe(scalar),
                !current.isEmpty,
                isPossessiveMarker(after: index, in: scalars)
            {
                index = scalars.index(after: index)
                appendCurrentToken()
            } else {
                appendCurrentToken()
            }
            index = scalars.index(after: index)
        }
        appendCurrentToken()

        return tokens.joined(separator: " ")
    }

    /// Try only the final token for simple number variants so broad phrase meaning stays intact.
    static func finalTokenVariantSeparatorInsensitiveFolds(_ separatorFolded: String) -> [String] {
        let tokens = separatorFolded.split(separator: " ").map(String.init)
        guard let last = tokens.last else {
            return []
        }

        let variants = finalTokenVariants(for: last)
        return variants.map { variant in
            (tokens.dropLast() + [variant]).joined(separator: " ")
        }
    }

    private static func isApostrophe(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0027, 0x2019, 0x2018, 0x02BC, 0xFF07, 0x2032:
            return true
        default:
            return false
        }
    }

    private static func isPossessiveMarker(
        after index: Int,
        in scalars: [UnicodeScalar]
    ) -> Bool {
        let next = scalars.index(after: index)
        guard next < scalars.endIndex, scalars[next] == "s" else {
            return false
        }
        let afterNext = scalars.index(after: next)
        return afterNext == scalars.endIndex || !CharacterSet.alphanumerics.contains(scalars[afterNext])
    }

    private static func finalTokenVariants(for token: String) -> [String] {
        let variants = singularVariants(for: token) + pluralVariants(for: token)
        var seen: Set<String> = []
        return variants.filter { $0 != token && seen.insert($0).inserted }
    }

    private static func singularVariants(for token: String) -> [String] {
        guard token.count > 3 else {
            return []
        }

        var variants: [String] = []
        if token.hasSuffix("ies") {
            variants.append(String(token.dropLast(3)) + "y")
        }
        if token.hasSuffix("ves") {
            let base = token.dropLast(3)
            variants.append(String(base) + "f")
            variants.append(String(base) + "fe")
        }
        if token.hasSuffix("ches") || token.hasSuffix("shes") || token.hasSuffix("xes")
            || token.hasSuffix("zes") || token.hasSuffix("ses")
        {
            variants.append(String(token.dropLast(2)))
        }
        if token.hasSuffix("s"), !token.hasSuffix("ss") {
            variants.append(String(token.dropLast()))
        }

        return variants
    }

    private static func pluralVariants(for token: String) -> [String] {
        guard token.count > 3, !token.hasSuffix("s") else {
            return []
        }

        if token.hasSuffix("y"), hasConsonantBeforeTerminalY(token) {
            return [String(token.dropLast()) + "ies"]
        }
        if token.hasSuffix("fe") {
            return [String(token.dropLast(2)) + "ves"]
        }
        if token.hasSuffix("f") {
            return [String(token.dropLast()) + "ves"]
        }
        if token.hasSuffix("ch") || token.hasSuffix("sh") || token.hasSuffix("x") || token.hasSuffix("z") {
            return [token + "es"]
        }
        return [token + "s"]
    }

    private static func hasConsonantBeforeTerminalY(_ token: String) -> Bool {
        let beforeYIndex = token.index(token.endIndex, offsetBy: -2)
        return !"aeiou".contains(token[beforeYIndex])
    }
}
