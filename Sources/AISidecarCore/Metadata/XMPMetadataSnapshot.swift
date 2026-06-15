import Foundation

/// Parsed view of managed XMP keyword fields plus semantic unmanaged-content state.
public struct XMPMetadataSnapshot: Codable, Sendable, Equatable {
    public var targetPath: String
    public var exists: Bool
    public var flatKeywords: [String]
    public var hierarchicalKeywords: [String]
    public var unmanagedContentFingerprint: XMPUnmanagedContentFingerprint

    enum CodingKeys: String, CodingKey {
        case targetPath = "target_path"
        case exists
        case flatKeywords = "flat_keywords"
        case hierarchicalKeywords = "hierarchical_keywords"
        case unmanagedContentFingerprint = "unmanaged_content_fingerprint"
    }

    public init(
        targetPath: String,
        exists: Bool,
        flatKeywords: [String],
        hierarchicalKeywords: [String],
        unmanagedContentFingerprint: XMPUnmanagedContentFingerprint
    ) {
        self.targetPath = targetPath
        self.exists = exists
        self.flatKeywords = flatKeywords
        self.hierarchicalKeywords = hierarchicalKeywords
        self.unmanagedContentFingerprint = unmanagedContentFingerprint
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

    static func make(targetPath: String, exists: Bool, parsed: XMPParsedDocument) -> XMPMetadataSnapshot {
        let reader = XMPKeywordReader()
        return XMPMetadataSnapshot(
            targetPath: targetPath,
            exists: exists,
            flatKeywords: reader.flatKeywords(in: parsed),
            hierarchicalKeywords: reader.hierarchicalKeywords(in: parsed),
            unmanagedContentFingerprint: XMPUnmanagedContentFingerprint.make(from: parsed)
        )
    }
}
