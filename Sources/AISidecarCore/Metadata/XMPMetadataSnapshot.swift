import Foundation

/// Parsed view of managed XMP fields plus semantic unmanaged-content state.
public struct XMPMetadataSnapshot: Codable, Sendable, Equatable {
    public var targetPath: String
    public var exists: Bool
    public var flatKeywords: [String]
    public var hierarchicalKeywords: [String]
    public var unmanagedContentFingerprint: XMPUnmanagedContentFingerprint
    public var rating: String?
    public var label: String?
    public var urgency: String?
    public var pick: String?
    public var good: String?

    enum CodingKeys: String, CodingKey {
        case targetPath = "target_path"
        case exists
        case flatKeywords = "flat_keywords"
        case hierarchicalKeywords = "hierarchical_keywords"
        case unmanagedContentFingerprint = "unmanaged_content_fingerprint"
        case rating
        case label
        case urgency
        case pick
        case good
    }

    public init(
        targetPath: String,
        exists: Bool,
        flatKeywords: [String],
        hierarchicalKeywords: [String],
        unmanagedContentFingerprint: XMPUnmanagedContentFingerprint,
        rating: String? = nil,
        label: String? = nil,
        urgency: String? = nil,
        pick: String? = nil,
        good: String? = nil
    ) {
        self.targetPath = targetPath
        self.exists = exists
        self.flatKeywords = flatKeywords
        self.hierarchicalKeywords = hierarchicalKeywords
        self.unmanagedContentFingerprint = unmanagedContentFingerprint
        self.rating = rating
        self.label = label
        self.urgency = urgency
        self.pick = pick
        self.good = good
    }

    /// Build a snapshot for a target that has no readable sidecar yet.
    public static func empty(targetPath: String, exists: Bool) -> XMPMetadataSnapshot {
        XMPMetadataSnapshot(
            targetPath: targetPath,
            exists: exists,
            flatKeywords: [],
            hierarchicalKeywords: [],
            unmanagedContentFingerprint: .empty()
        )
    }

    static func make(targetPath: String, exists: Bool, parsed: XMPParsedDocument) throws -> XMPMetadataSnapshot {
        let keywordReader = XMPKeywordReader()
        return XMPMetadataSnapshot(
            targetPath: targetPath,
            exists: exists,
            flatKeywords: keywordReader.flatKeywords(in: parsed),
            hierarchicalKeywords: keywordReader.hierarchicalKeywords(in: parsed),
            unmanagedContentFingerprint: XMPUnmanagedContentFingerprint.make(from: parsed),
            rating: try XMPScalarReader.read(.rating, in: parsed)?.value,
            label: try XMPScalarReader.read(.label, in: parsed)?.value,
            urgency: try XMPScalarReader.read(.urgency, in: parsed)?.value,
            pick: try XMPScalarReader.read(.pick, in: parsed)?.value,
            good: try XMPScalarReader.read(.good, in: parsed)?.value
        )
    }
}
