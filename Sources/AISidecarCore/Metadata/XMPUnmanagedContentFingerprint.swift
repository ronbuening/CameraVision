import CryptoKit
import Foundation

/// Semantic fingerprint for XMP content outside the Phase 2 managed keyword fields.
public struct XMPUnmanagedContentFingerprint: Codable, Sendable, Equatable {
    public static let algorithmVersion = "xmp-unmanaged-content-fingerprint/1.0"

    public var algorithmVersion: String
    public var canonicalEntries: [String]
    public var sha256: String

    enum CodingKeys: String, CodingKey {
        case algorithmVersion = "algorithm_version"
        case canonicalEntries = "canonical_entries"
        case sha256
    }

    public init(
        algorithmVersion: String = Self.algorithmVersion,
        canonicalEntries: [String],
        sha256: String
    ) {
        self.algorithmVersion = algorithmVersion
        self.canonicalEntries = canonicalEntries
        self.sha256 = sha256
    }

    /// Build the empty semantic fingerprint used for missing or newly empty documents.
    public static func empty() -> XMPUnmanagedContentFingerprint {
        make(canonicalEntries: [])
    }

    static func make(canonicalEntries: [String]) -> XMPUnmanagedContentFingerprint {
        let sortedEntries = canonicalEntries.sorted()
        var hasher = SHA256()
        update(&hasher, Self.algorithmVersion)
        update(&hasher, "\n")
        for entry in sortedEntries {
            update(&hasher, entry)
            update(&hasher, "\n")
        }
        return XMPUnmanagedContentFingerprint(
            canonicalEntries: sortedEntries,
            sha256: hexString(hasher.finalize())
        )
    }

    static func make(from parsed: XMPParsedDocument) -> XMPUnmanagedContentFingerprint {
        guard let root = parsed.document.rootElement() else {
            return .empty()
        }
        var entries: [String] = []
        appendEntries(for: root, currentPath: [segment(for: root, occurrence: 0)], entries: &entries)
        return make(canonicalEntries: entries)
    }

    private static func appendEntries(for element: XMLElement, currentPath: [String], entries: inout [String]) {
        guard !XMPXML.isManagedProperty(element) else {
            return
        }

        let pathString = currentPath.joined(separator: "/")
        entries.append("element|\(pathString)|uri=\(element.uri ?? "")|local=\(element.xmlLocalName)")

        let attributes = (element.attributes ?? [])
            .filter { !XMPXML.isManagedAttribute($0) }
            .sorted { lhs, rhs in
                attributeSortKey(lhs) < attributeSortKey(rhs)
            }
        for attribute in attributes {
            entries.append(
                "attribute|\(pathString)|uri=\(attribute.uri ?? "")|local=\(attribute.xmlLocalName)|value=\(attribute.stringValue ?? "")"
            )
        }

        let elementChildren = XMPXML.elementChildren(of: element).filter { !XMPXML.isManagedProperty($0) }
        let hasElementChildren = !elementChildren.isEmpty
        let text = (element.children ?? [])
            .filter { $0.kind == .text }
            .compactMap(\.stringValue)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !hasElementChildren, !text.isEmpty {
            entries.append("text|\(pathString)|value=\(text)")
        }

        var occurrenceBySignature: [String: Int] = [:]
        for child in elementChildren {
            let signature = "\(child.uri ?? "")|\(child.xmlLocalName)"
            let occurrence = occurrenceBySignature[signature, default: 0]
            occurrenceBySignature[signature] = occurrence + 1
            appendEntries(
                for: child,
                currentPath: currentPath + [segment(for: child, occurrence: occurrence)],
                entries: &entries
            )
        }
    }

    private static func segment(for element: XMLElement, occurrence: Int) -> String {
        "{\(element.uri ?? "")}\(element.xmlLocalName)[\(occurrence)]"
    }

    private static func attributeSortKey(_ attribute: XMLNode) -> String {
        "\(attribute.uri ?? "")|\(attribute.xmlLocalName)|\(attribute.stringValue ?? "")"
    }
}

private func update(_ hasher: inout SHA256, _ string: String) {
    hasher.update(data: Data(string.utf8))
}

private func hexString<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
}
