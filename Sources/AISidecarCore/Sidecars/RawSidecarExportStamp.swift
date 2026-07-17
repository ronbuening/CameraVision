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
        public var rating: String?
        public var label: String?
        public var urgency: String?
        public var qualityTier: QualityTier?

        public init(
            targetXMPPath: String,
            xmpSHA256: String,
            writerRecipeVersion: String,
            engineVersion: String,
            exportedAt: Date,
            rating: String? = nil,
            label: String? = nil,
            urgency: String? = nil,
            qualityTier: QualityTier? = nil
        ) {
            self.targetXMPPath = targetXMPPath
            self.xmpSHA256 = xmpSHA256
            self.writerRecipeVersion = writerRecipeVersion
            self.engineVersion = engineVersion
            self.exportedAt = exportedAt
            self.rating = rating
            self.label = label
            self.urgency = urgency
            self.qualityTier = qualityTier
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
        var stamp = object[key]?.objectValue ?? [:]
        stamp["target_xmp_path"] = .string(contents.targetXMPPath)
        stamp["xmp_sha256"] = .string(contents.xmpSHA256)
        stamp["writer_recipe_version"] = .string(contents.writerRecipeVersion)
        stamp["engine_version"] = .string(contents.engineVersion)
        stamp["exported_at"] = .string(formatter.string(from: contents.exportedAt))
        if let rating = contents.rating {
            stamp["rating"] = .string(rating)
        } else {
            stamp.removeValue(forKey: "rating")
        }
        if let label = contents.label {
            stamp["label"] = .string(label)
        } else {
            stamp.removeValue(forKey: "label")
        }
        if let urgency = contents.urgency {
            stamp["urgency"] = .string(urgency)
        } else {
            stamp.removeValue(forKey: "urgency")
        }
        if let qualityTier = contents.qualityTier {
            stamp["quality_tier"] = .string(qualityTier.rawValue)
        } else {
            stamp.removeValue(forKey: "quality_tier")
        }
        object[key] = .object(stamp)
        let output = try JSONCoding.documentEncoder(iso8601Dates: false).encode(JSONValue.object(object))
        try AtomicFileWriter.write(output, to: url, fileManager: fileManager)
    }

    /// Read a structurally valid export stamp from a decoded raw sidecar.
    ///
    /// Legacy stamps are valid and return `nil` for quality fields. A malformed
    /// required or present optional field rejects the stamp so callers never
    /// treat partial or ill-typed provenance as trusted state.
    public static func contents(from document: RawJSONSidecarDocument) -> Contents? {
        guard
            let object = try? document.jsonValue().objectValue,
            let stamp = object[key]?.objectValue,
            let targetXMPPath = nonemptyString(stamp["target_xmp_path"]),
            let xmpSHA256 = nonemptyString(stamp["xmp_sha256"]),
            let writerRecipeVersion = nonemptyString(stamp["writer_recipe_version"]),
            let engineVersion = nonemptyString(stamp["engine_version"]),
            let exportedAtText = nonemptyString(stamp["exported_at"]),
            let exportedAt = parseISO8601Date(exportedAtText),
            let rating = optionalRating(stamp),
            let label = optionalLabel(stamp),
            let urgency = optionalUrgency(stamp),
            let qualityTier = optionalQualityTier(stamp)
        else {
            return nil
        }

        return Contents(
            targetXMPPath: targetXMPPath,
            xmpSHA256: xmpSHA256,
            writerRecipeVersion: writerRecipeVersion,
            engineVersion: engineVersion,
            exportedAt: exportedAt,
            rating: rating,
            label: label,
            urgency: urgency,
            qualityTier: qualityTier
        )
    }

    /// Read a structurally valid export stamp directly from a raw-sidecar path.
    public static func contents(
        sidecarPath: String,
        fileManager: FileManager = .default
    ) -> Contents? {
        guard
            let data = fileManager.contents(atPath: sidecarPath),
            let document = try? RawJSONSidecarDocument(data: data)
        else {
            return nil
        }
        return contents(from: document)
    }

    /// True when the sidecar carries a stamp (presence check only).
    public static func isStamped(sidecarPath: String, fileManager: FileManager = .default) -> Bool {
        guard let data = fileManager.contents(atPath: sidecarPath),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return object[key] != nil
    }

    private static func nonemptyString(_ value: JSONValue?) -> String? {
        guard let string = value?.stringValue, !string.isEmpty else {
            return nil
        }
        return string
    }

    /// The outer optional distinguishes a missing value from a malformed value.
    private static func optionalString(_ object: [String: JSONValue], key: String) -> String?? {
        guard let value = object[key] else {
            return .some(nil)
        }
        guard let string = value.stringValue else {
            return nil
        }
        return .some(string)
    }

    private static func optionalRating(_ object: [String: JSONValue]) -> String?? {
        guard let rating = optionalString(object, key: "rating") else {
            return nil
        }
        guard let rating else {
            return .some(nil)
        }
        guard let value = Int(rating), (-1...5).contains(value), String(value) == rating else {
            return nil
        }
        return .some(rating)
    }

    private static func optionalLabel(_ object: [String: JSONValue]) -> String?? {
        guard let label = optionalString(object, key: "label") else {
            return nil
        }
        guard let label else {
            return .some(nil)
        }
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !label.contains("|")
        else {
            return nil
        }
        return .some(label)
    }

    private static func optionalUrgency(_ object: [String: JSONValue]) -> String?? {
        guard let urgency = optionalString(object, key: "urgency") else {
            return nil
        }
        guard let urgency else {
            return .some(nil)
        }
        guard let value = Int(urgency), (1...8).contains(value), String(value) == urgency else {
            return nil
        }
        return .some(urgency)
    }

    /// The outer optional distinguishes a missing value from a malformed value.
    private static func optionalQualityTier(_ object: [String: JSONValue]) -> QualityTier?? {
        guard let value = object["quality_tier"] else {
            return .some(nil)
        }
        guard let string = value.stringValue, let tier = QualityTier(rawValue: string) else {
            return nil
        }
        return .some(tier)
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
