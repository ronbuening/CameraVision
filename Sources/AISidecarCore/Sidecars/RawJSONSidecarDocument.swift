import Foundation

/// Decoded Phase 1 sidecar plus its original JSON document for schema-safe rewrites.
///
/// PW-012 allows additive minor-version fields. This wrapper lets readers update
/// known `RawJSONSidecar` fields while preserving unknown JSON carried by newer
/// 1.x writers.
public struct RawJSONSidecarDocument: Sendable, Equatable {
    public var sidecar: RawJSONSidecar

    private var originalJSON: JSONValue

    public init(sidecar: RawJSONSidecar) throws {
        self.sidecar = sidecar
        self.originalJSON = try Self.jsonValue(for: sidecar)
        try Self.validateSchemaVersion(sidecar.schemaVersion)
    }

    /// Decode a raw sidecar document, rejecting schemas outside the supported major version.
    public init(data: Data) throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = json.objectValue else {
            throw SidecarError(
                code: .schemaUnsupported,
                stage: .write,
                message: "Raw sidecar document must be a JSON object.",
                recoverable: false
            )
        }
        guard let schemaVersion = object["schema_version"]?.stringValue else {
            throw SidecarError(
                code: .schemaUnsupported,
                stage: .write,
                message: "Raw sidecar document is missing schema_version.",
                recoverable: false
            )
        }
        try Self.validateSchemaVersion(schemaVersion)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.sidecar = try decoder.decode(RawJSONSidecar.self, from: data)
        self.originalJSON = json
    }

    /// Encode the sidecar after merging known-field updates with preserved unknown JSON.
    public func encodedData() throws -> Data {
        let replacement = try Self.jsonValue(for: sidecar)
        let merged = Self.mergePreservingUnknowns(original: originalJSON, replacement: replacement)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(merged)
    }

    /// Return the merged JSON object without serializing it to bytes.
    public func jsonValue() throws -> JSONValue {
        let replacement = try Self.jsonValue(for: sidecar)
        return Self.mergePreservingUnknowns(original: originalJSON, replacement: replacement)
    }

    private static let supportedSchemaName = "ai-sidecar-json"
    private static let supportedMajorVersion = 1

    private static func validateSchemaVersion(_ schemaVersion: String) throws {
        guard
            let slashIndex = schemaVersion.firstIndex(of: "/"),
            schemaVersion[..<slashIndex] == supportedSchemaName
        else {
            throw unsupportedSchema(schemaVersion)
        }

        let version = schemaVersion[schemaVersion.index(after: slashIndex)...]
        let majorText = version.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first
        guard let majorText, let major = Int(majorText), major == supportedMajorVersion else {
            throw unsupportedSchema(schemaVersion)
        }
    }

    private static func unsupportedSchema(_ schemaVersion: String) -> SidecarError {
        SidecarError(
            code: .schemaUnsupported,
            stage: .write,
            message: "Unsupported raw sidecar schema version: \(schemaVersion).",
            recoverable: false
        )
    }

    private static func jsonValue(for sidecar: RawJSONSidecar) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(sidecar)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func mergePreservingUnknowns(original: JSONValue, replacement: JSONValue) -> JSONValue {
        switch (original, replacement) {
        case (.object(let originalObject), .object(let replacementObject)):
            var merged = originalObject
            for (key, value) in replacementObject {
                if let originalValue = originalObject[key] {
                    merged[key] = mergePreservingUnknowns(original: originalValue, replacement: value)
                } else {
                    merged[key] = value
                }
            }
            return .object(merged)
        case (.array(let originalArray), .array(let replacementArray)):
            let values = replacementArray.enumerated().map { index, value in
                guard originalArray.indices.contains(index) else {
                    return value
                }
                return mergePreservingUnknowns(original: originalArray[index], replacement: value)
            }
            return .array(values)
        default:
            return replacement
        }
    }
}
