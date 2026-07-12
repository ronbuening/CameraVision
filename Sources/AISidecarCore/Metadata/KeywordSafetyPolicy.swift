import Foundation

/// Shared coordinate/GPS-metadata checks for keyword text at every route into XMP.
enum KeywordSafetyPolicy {
    static func isUnsafeKeyword(_ term: String) -> Bool {
        if containsCoordinateSyntax(term) {
            return true
        }

        let lowercased = term.lowercased()
        let words = lexicalWords(in: lowercased)
        if words.contains(where: { $0.hasPrefix("geotag") || $0.hasPrefix("geolocation") })
            || !words.isDisjoint(with: coordinateWords)
            || lowercased.contains("exif location")
        {
            return true
        }

        guard words.contains("gps") else {
            return false
        }
        if !words.isDisjoint(with: gpsMetadataWords) {
            return true
        }
        return words.isDisjoint(with: visibleGPSDeviceWords)
    }

    static func evidenceReliesOnLocationMetadata(_ evidence: String?) -> Bool {
        guard let evidence else {
            return false
        }
        let lowercased = evidence.lowercased()
        if locationEvidencePhrases.contains(where: lowercased.contains) {
            return true
        }
        return isUnsafeKeyword(evidence)
    }

    static func containsCoordinateSyntax(_ term: String) -> Bool {
        let range = NSRange(term.startIndex..<term.endIndex, in: term)
        return coordinateExpressions.contains { expression in
            expression.firstMatch(in: term, range: range) != nil
        }
    }

    private static func lexicalWords(in value: String) -> Set<String> {
        Set(value.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    private static let coordinateWords: Set<String> = [
        "coordinate", "coordinates", "latitude", "latitudes", "longitude", "longitudes",
    ]

    private static let gpsMetadataWords: Set<String> = [
        "based", "context", "data", "derived", "exif", "fix", "fixes", "location", "locations",
        "metadata", "point", "points", "position", "positions", "reading", "readings", "tag", "tags",
    ]

    private static let visibleGPSDeviceWords: Set<String> = [
        "antenna", "device", "handheld", "logger", "module", "receiver", "tracker", "unit", "watch",
    ]

    private static let locationEvidencePhrases = [
        "exif location",
        "location context",
        "range map",
        "common in this location",
        "common near this location",
    ]

    private static let coordinateExpressions: [NSRegularExpression] = [
        #"(?<!\d)[+-]?\d{1,3}\.\d+\s*[,/ ]\s*[+-]?\d{1,3}\.\d+(?!\d)"#,
        #"\b\d{1,3}(?:\.\d+)?\s*[°º]?\s*[NS]\b.*\b\d{1,3}(?:\.\d+)?\s*[°º]?\s*[EW]\b"#,
        #"\d{1,3}\s*[°º]\s*\d{1,2}\s*['′’]\s*\d{1,2}(?:\.\d+)?\s*[\"″”]?\s*[NSEW]"#,
        #"\b[NS]\s*\d{1,3}(?:\.\d+)?\b.*\b[EW]\s*\d{1,3}(?:\.\d+)?\b"#,
        #"(?<!\d)[+-]?\d{1,3}(?:\.\d+)?\s*,\s*[+-]\d{1,3}(?:\.\d+)?(?!\d)"#,
        #"\butm\b\s*\d{1,2}\s*[a-z]?\b"#,
    ].map { pattern in
        // These are fixed source literals; failure would be a programmer error caught by tests.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
