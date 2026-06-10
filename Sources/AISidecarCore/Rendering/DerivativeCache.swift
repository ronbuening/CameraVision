import CryptoKit
import Foundation

/// Content-addressed derivative cache with manifest-backed LRU eviction.
public struct DerivativeCache {
    public var directoryPath: String
    public var sizeCapBytes: Int64

    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directoryPath: String,
        sizeCapBytes: Int64,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directoryPath = URL(fileURLWithPath: (directoryPath as NSString).expandingTildeInPath)
            .standardizedFileURL
            .path
        self.sizeCapBytes = sizeCapBytes
        self.fileManager = fileManager
        self.now = now
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Default application cache location for regenerable derivative artifacts.
    public static func defaultDirectoryPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/Caches/aisidecar/derivatives"
    }

    /// Default derivative cache cap required by FR1-018a, in bytes.
    public static let defaultSizeCapBytes: Int64 = 20 * 1_024 * 1_024 * 1_024

    /// Return the deterministic cache URL for a rendered derivative.
    public func artifactURL(source: SourceImage, recipeVersion: String, role: DerivativeRole, format: DerivativeFormat) -> URL {
        URL(fileURLWithPath: directoryPath)
            .appendingPathComponent("\(source.identity.sha256)-\(recipeVersion)-\(role.rawValue).\(format.fileExtension)")
            .standardizedFileURL
    }

    /// Return a valid cached artifact if one exists and its manifest hash matches the file bytes.
    public func cachedRecord(
        source: SourceImage,
        recipeVersion: String,
        role: DerivativeRole,
        format: DerivativeFormat
    ) throws -> DerivativeRecord? {
        let url = artifactURL(source: source, recipeVersion: recipeVersion, role: role, format: format)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        var manifest = try loadManifest()
        guard let entry = manifest.entries[url.lastPathComponent] else {
            return nil
        }
        let sha256 = try Self.sha256(of: url)
        guard sha256 == entry.sha256 else {
            // Cache artifacts are regenerable; removing corrupt bytes is safer
            // than returning provenance for a derivative the model did not see.
            try? fileManager.removeItem(at: url)
            manifest.entries.removeValue(forKey: url.lastPathComponent)
            try saveManifest(manifest)
            return nil
        }

        manifest.entries[url.lastPathComponent]?.lastAccessedAt = now()
        try saveManifest(manifest)
        return entry.record(cachePath: url.path)
    }

    /// Store a newly encoded artifact, update the manifest, and evict older entries.
    public func store(
        source: SourceImage,
        recipeVersion: String,
        role: DerivativeRole,
        format: DerivativeFormat,
        dimensions: PixelDimensions,
        colorSpace: ModelInputColorSpace,
        appliedOrientation: AppliedOrientation,
        writer: (URL) throws -> Void
    ) throws -> DerivativeRecord {
        let url = artifactURL(source: source, recipeVersion: recipeVersion, role: role, format: format)
        do {
            try AtomicFileWriter.writeFile(to: url, fileManager: fileManager, writer: writer)
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let sha256 = try Self.sha256(of: url)
            let entry = CacheManifestEntry(
                fileName: url.lastPathComponent,
                role: role,
                format: format,
                width: dimensions.width,
                height: dimensions.height,
                colorSpace: colorSpace,
                appliedOrientation: appliedOrientation,
                recipeVersion: recipeVersion,
                sha256: sha256,
                sourceIdentity: source.identity,
                byteCount: byteCount,
                lastAccessedAt: now()
            )
            var manifest = try loadManifest()
            manifest.entries[url.lastPathComponent] = entry
            try saveManifest(manifest)
            try evictIfNeeded(protectedFileName: url.lastPathComponent)
            return entry.record(cachePath: url.path)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to store derivative \(url.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    /// Copy an existing cache artifact beside the source for inspection.
    public func copyDebugArtifact(record: DerivativeRecord, source: SourceImage) throws -> DerivativeRecord {
        let destination = URL(fileURLWithPath: source.path)
            .deletingLastPathComponent()
            .appendingPathComponent("\(source.fileName).aisidecar.\(record.role.rawValue).\(record.format.fileExtension)")
            .standardizedFileURL
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: record.cachePath))
            try AtomicFileWriter.write(data, to: destination, fileManager: fileManager)
            var copied = record
            copied.debugPath = destination.path
            return copied
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to copy debug derivative \(destination.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    /// Compute the SHA-256 digest of artifact bytes for derivative provenance.
    public static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var manifestURL: URL {
        URL(fileURLWithPath: directoryPath).appendingPathComponent("derivative-cache-index.json")
    }

    private func loadManifest() throws -> CacheManifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return CacheManifest()
        }
        do {
            return try decoder.decode(CacheManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to read derivative cache manifest \(manifestURL.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func saveManifest(_ manifest: CacheManifest) throws {
        let data = try encoder.encode(manifest)
        try AtomicFileWriter.write(data, to: manifestURL, fileManager: fileManager)
    }

    private func evictIfNeeded(protectedFileName: String) throws {
        var manifest = try loadManifest()
        var totalBytes = manifest.entries.values.reduce(Int64(0)) { $0 + $1.byteCount }
        // Keep the artifact that satisfied the current render request even if
        // a tiny cap means the cache remains over budget after older eviction.
        let candidates = manifest.entries.values
            .filter { $0.fileName != protectedFileName }
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }

        for entry in candidates where totalBytes > sizeCapBytes {
            let url = URL(fileURLWithPath: directoryPath).appendingPathComponent(entry.fileName)
            try? fileManager.removeItem(at: url)
            manifest.entries.removeValue(forKey: entry.fileName)
            totalBytes -= entry.byteCount
        }
        try saveManifest(manifest)
    }
}

private extension DerivativeFormat {
    var fileExtension: String {
        switch self {
        case .jpeg:
            return "jpg"
        case .tiff:
            return "tiff"
        }
    }
}

private struct CacheManifest: Codable {
    var schemaVersion = "aisidecar-derivative-cache/1.0"
    var entries: [String: CacheManifestEntry] = [:]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case entries
    }
}

private struct CacheManifestEntry: Codable {
    var fileName: String
    var role: DerivativeRole
    var format: DerivativeFormat
    var width: Int
    var height: Int
    var colorSpace: ModelInputColorSpace
    var appliedOrientation: AppliedOrientation
    var recipeVersion: String
    var sha256: String
    var sourceIdentity: SourceIdentity
    var byteCount: Int64
    var lastAccessedAt: Date

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case role
        case format
        case width
        case height
        case colorSpace = "color_space"
        case appliedOrientation = "applied_orientation"
        case recipeVersion = "recipe_version"
        case sha256
        case sourceIdentity = "source_identity"
        case byteCount = "byte_count"
        case lastAccessedAt = "last_accessed_at"
    }

    func record(cachePath: String) -> DerivativeRecord {
        DerivativeRecord(
            role: role,
            cachePath: cachePath,
            format: format,
            width: width,
            height: height,
            colorSpace: colorSpace,
            appliedOrientation: appliedOrientation,
            recipeVersion: recipeVersion,
            sha256: sha256,
            sourceIdentity: sourceIdentity
        )
    }
}
