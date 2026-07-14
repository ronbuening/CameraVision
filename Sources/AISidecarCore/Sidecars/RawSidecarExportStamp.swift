import Foundation

/// CORE-4 (FR4-049): the additive `xmp_export` block written into a raw
/// `.ai.json` sidecar after a successful XMP export, so "exported by this
/// pipeline" is derivable from files alone.
///
/// The stamp preserves every other byte of meaning in the document: it is
/// applied through the raw document's merge-preserving schema-evolution path,
/// so fields from newer schema versions survive untouched (PW-011/012).
/// Analyze paths never write it — a fresh analysis rewrites the sidecar and
/// thereby truthfully clears any stale export stamp.
public enum RawSidecarExportStamp {
    public static let key = "xmp_export"

    public struct Contents: Sendable, Equatable {
        public var targetXMPPath: String
        public var xmpSHA256: String
        public var writerRecipeVersion: String
        public var engineVersion: String
        public var exportedAt: Date

        public init(
            targetXMPPath: String,
            xmpSHA256: String,
            writerRecipeVersion: String,
            engineVersion: String,
            exportedAt: Date
        ) {
            self.targetXMPPath = targetXMPPath
            self.xmpSHA256 = xmpSHA256
            self.writerRecipeVersion = writerRecipeVersion
            self.engineVersion = engineVersion
            self.exportedAt = exportedAt
        }
    }

    /// Write (or replace) the stamp in the sidecar at `sidecarPath`.
    public static func stamp(
        sidecarPath: String,
        contents: Contents,
        fileManager: FileManager = .default
    ) throws {
        let url = URL(fileURLWithPath: sidecarPath)
        let data = try Data(contentsOf: url)
        let document = try RawJSONSidecarDocument(data: data)
        guard var object = try document.jsonValue().objectValue else {
            throw SidecarError(
                code: .validationFailed,
                stage: .write,
                message: "Raw sidecar is not a JSON object: \(sidecarPath)",
                recoverable: true
            )
        }
        let formatter = ISO8601DateFormatter()
        object[key] = .object([
            "target_xmp_path": .string(contents.targetXMPPath),
            "xmp_sha256": .string(contents.xmpSHA256),
            "writer_recipe_version": .string(contents.writerRecipeVersion),
            "engine_version": .string(contents.engineVersion),
            "exported_at": .string(formatter.string(from: contents.exportedAt)),
        ])
        let output = try JSONCoding.documentEncoder(iso8601Dates: false).encode(JSONValue.object(object))
        try AtomicFileWriter.write(output, to: url, fileManager: fileManager)
    }

    /// True when the sidecar carries a stamp (presence check only).
    public static func isStamped(sidecarPath: String, fileManager: FileManager = .default) -> Bool {
        guard let data = fileManager.contents(atPath: sidecarPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object[key] != nil
    }
}
