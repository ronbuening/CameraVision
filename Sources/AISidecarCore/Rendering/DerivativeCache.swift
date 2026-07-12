import CryptoKit
import Foundation

/// Summary of derivative cache artifacts removed by a clear or purge operation.
public struct DerivativeCachePurgeResult: Sendable, Equatable {
    public var directoryPath: String
    public var removedFileCount: Int

    public init(directoryPath: String, removedFileCount: Int) {
        self.directoryPath = directoryPath
        self.removedFileCount = removedFileCount
    }
}

/// Content-addressed derivative cache with manifest-backed LRU eviction.
public final class DerivativeCache: @unchecked Sendable {
    public let directoryPath: String
    public let sizeCapBytes: Int64

    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let stateLock = NSLock()
    private var cachedManifestState: CachedManifestState?
    private var retainedArtifacts: [String: RetainedArtifact] = [:]

    public init(
        directoryPath: String,
        sizeCapBytes: Int64,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directoryPath =
            URL(fileURLWithPath: (directoryPath as NSString).expandingTildeInPath)
            .standardizedFileURL
            .path
        self.sizeCapBytes = sizeCapBytes
        self.fileManager = fileManager
        self.now = now
        self.encoder = JSONCoding.documentEncoder()
        self.decoder = JSONCoding.decoder()
    }

    /// Default application cache location for regenerable derivative artifacts.
    public static func defaultDirectoryPath(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> String
    {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/Caches/aisidecar/derivatives"
    }

    /// Default derivative cache cap required by FR1-018a, in bytes.
    public static let defaultSizeCapBytes: Int64 = 20 * 1_024 * 1_024 * 1_024

    /// Return the deterministic cache URL for a rendered derivative.
    public func artifactURL(source: SourceImage, recipeVersion: String, role: DerivativeRole, format: DerivativeFormat)
        -> URL
    {
        URL(fileURLWithPath: directoryPath)
            .appendingPathComponent(
                "\(source.identity.sha256)-\(recipeVersion)-\(role.rawValue).\(format.fileExtension)"
            )
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

        return try withManifestLock {
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
                switch removeArtifactIfUnlocked(at: url) {
                case .removed, .missing:
                    manifest.entries.removeValue(forKey: url.lastPathComponent)
                    try saveManifest(manifest)
                case .busy, .failed:
                    break
                }
                return nil
            }

            manifest.entries[url.lastPathComponent]?.lastAccessedAt = now()
            try retainArtifact(at: url)
            do {
                try saveManifest(manifest)
            } catch {
                release(fileNames: [url.lastPathComponent])
                throw error
            }
            return entry.record(cachePath: url.path)
        }
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
            let staged = try AtomicFileWriter.stageFile(to: url, fileManager: fileManager) { temporaryURL in
                try writer(temporaryURL)
                let attributes = try fileManager.attributesOfItem(atPath: temporaryURL.path)
                let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                return (byteCount: byteCount, sha256: try Self.sha256(of: temporaryURL))
            }
            defer { staged.discard() }
            let entry = CacheManifestEntry(
                fileName: url.lastPathComponent,
                role: role,
                format: format,
                width: dimensions.width,
                height: dimensions.height,
                colorSpace: colorSpace,
                appliedOrientation: appliedOrientation,
                recipeVersion: recipeVersion,
                sha256: staged.result.sha256,
                sourceIdentity: source.identity,
                byteCount: staged.result.byteCount,
                lastAccessedAt: now()
            )

            return try withManifestLock {
                var manifest = try loadManifest()
                if let existing = manifest.entries[url.lastPathComponent],
                    existing.sha256 == entry.sha256,
                    fileManager.fileExists(atPath: url.path),
                    try Self.sha256(of: url) == existing.sha256
                {
                    try retainArtifact(at: url)
                    do {
                        manifest.entries[url.lastPathComponent]?.lastAccessedAt = entry.lastAccessedAt
                        try evictIfNeeded(manifest: &manifest)
                        try saveManifest(manifest)
                    } catch {
                        release(fileNames: [url.lastPathComponent])
                        throw error
                    }
                    return existing.record(cachePath: url.path)
                }

                try commit(staged: staged, replacing: url)
                manifest.entries[url.lastPathComponent] = entry
                try retainArtifact(at: url)
                do {
                    try evictIfNeeded(manifest: &manifest)
                    try saveManifest(manifest)
                } catch {
                    release(fileNames: [url.lastPathComponent])
                    throw error
                }
                return entry.record(cachePath: url.path)
            }
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
            .appendingPathComponent(
                "\(source.fileName).aisidecar.\(record.role.rawValue).\(record.format.fileExtension)"
            )
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

    /// Remove all derivative artifacts owned by this cache.
    ///
    /// Clearing is intentionally scoped to manifest-tracked entries and files that
    /// match aisidecar's deterministic derivative names, so a misconfigured cache
    /// directory is less likely to lose unrelated user files.
    @discardableResult
    public func clear() throws -> DerivativeCachePurgeResult {
        let directory = URL(fileURLWithPath: directoryPath).standardizedFileURL
        guard fileManager.fileExists(atPath: directory.path) else {
            return DerivativeCachePurgeResult(directoryPath: directory.path, removedFileCount: 0)
        }

        releaseAllHandles()
        do {
            return try withManifestLock {
                let loadedManifest = try? loadManifest()
                var manifest = loadedManifest ?? CacheManifest()
                let cacheOwnedNames = Set(manifest.entries.keys)
                let manifestExisted = fileManager.fileExists(atPath: manifestURL.path)
                let contents = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                    options: [.skipsSubdirectoryDescendants]
                )
                var removedFileCount = 0
                var preservedUntrackedArtifact = false
                var firstRemovalError: Error?

                for url in contents {
                    let standardizedURL = url.standardizedFileURL
                    if standardizedURL == manifestLockURL.standardizedFileURL
                        || standardizedURL == manifestURL.standardizedFileURL
                    {
                        continue
                    }
                    if shouldClearExpiredTemporary(url: url) {
                        do {
                            try fileManager.removeItem(at: url)
                            removedFileCount += 1
                        } catch {
                            firstRemovalError = firstRemovalError ?? error
                        }
                        continue
                    }
                    guard shouldClearArtifact(url: url, cacheOwnedNames: cacheOwnedNames) else {
                        continue
                    }

                    switch removeArtifactIfUnlocked(at: url) {
                    case .removed:
                        manifest.entries.removeValue(forKey: url.lastPathComponent)
                        removedFileCount += 1
                    case .missing:
                        manifest.entries.removeValue(forKey: url.lastPathComponent)
                    case .busy:
                        preservedUntrackedArtifact =
                            preservedUntrackedArtifact
                            || manifest.entries[url.lastPathComponent] == nil
                    case .failed(let error):
                        preservedUntrackedArtifact =
                            preservedUntrackedArtifact
                            || manifest.entries[url.lastPathComponent] == nil
                        firstRemovalError = firstRemovalError ?? error
                    }
                }

                for fileName in Array(manifest.entries.keys) {
                    let url = directory.appendingPathComponent(fileName)
                    if !fileManager.fileExists(atPath: url.path) {
                        manifest.entries.removeValue(forKey: fileName)
                    }
                }

                if loadedManifest != nil, !manifest.entries.isEmpty || preservedUntrackedArtifact {
                    try saveManifest(manifest)
                } else if manifestExisted, !preservedUntrackedArtifact {
                    try fileManager.removeItem(at: manifestURL)
                    removedFileCount += 1
                    stateLock.withLock {
                        cachedManifestState = nil
                    }
                }

                if let firstRemovalError {
                    throw firstRemovalError
                }
                return DerivativeCachePurgeResult(directoryPath: directory.path, removedFileCount: removedFileCount)
            }
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to clear derivative cache \(directory.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    /// Purge derivative cache artifacts for explicit maintenance commands.
    @discardableResult
    public func purge() throws -> DerivativeCachePurgeResult {
        try clear()
    }

    /// Release selected active-use leases after their model or export consumer has finished.
    public func release(_ records: [DerivativeRecord]) {
        release(fileNames: records.map { URL(fileURLWithPath: $0.cachePath).lastPathComponent })
    }

    /// Release all active-use leases and restore the configured cap when possible.
    public func releaseRetained() {
        releaseAllHandles()
        try? withManifestLock {
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                return
            }
            var manifest = try loadManifest()
            if try evictIfNeeded(manifest: &manifest) {
                try saveManifest(manifest)
            }
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

    private var manifestLockURL: URL {
        URL(fileURLWithPath: directoryPath).appendingPathComponent("derivative-cache-index.lock")
    }

    private func withManifestLock<Result>(_ body: () throws -> Result) throws -> Result {
        do {
            return try FileLock(path: manifestLockURL.path).withExclusiveLock(body)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to coordinate derivative cache \(directoryPath): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func loadManifest() throws -> CacheManifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            stateLock.withLock {
                cachedManifestState = nil
            }
            return CacheManifest()
        }
        do {
            let signature = try manifestSignature()
            if let cached = stateLock.withLock({ cachedManifestState }), cached.signature == signature {
                return cached.manifest
            }
            guard let data = fileManager.contents(atPath: manifestURL.path) else {
                throw CocoaError(.fileReadUnknown)
            }
            let manifest = try decoder.decode(CacheManifest.self, from: data)
            stateLock.withLock {
                cachedManifestState = CachedManifestState(manifest: manifest, signature: signature)
            }
            return manifest
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
        stateLock.withLock {
            cachedManifestState = try? CachedManifestState(manifest: manifest, signature: manifestSignature())
        }
    }

    private func manifestSignature() throws -> ManifestSignature {
        let attributes = try fileManager.attributesOfItem(atPath: manifestURL.path)
        return ManifestSignature(
            fileIdentifier: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            modifiedAt: attributes[.modificationDate] as? Date ?? .distantPast,
            byteCount: (attributes[.size] as? NSNumber)?.int64Value ?? 0
        )
    }

    private func retainArtifact(at url: URL) throws {
        let handle = try FileLock(path: url.path).lockSharedExisting()
        stateLock.withLock {
            if var retained = retainedArtifacts[url.lastPathComponent] {
                retained.count += 1
                retainedArtifacts[url.lastPathComponent] = retained
            } else {
                retainedArtifacts[url.lastPathComponent] = RetainedArtifact(handle: handle, count: 1)
            }
        }
    }

    private func release(fileNames: [String]) {
        var released: [RetainedArtifact] = []
        stateLock.withLock {
            for fileName in fileNames {
                guard var retained = retainedArtifacts[fileName] else {
                    continue
                }
                retained.count -= 1
                if retained.count == 0 {
                    released.append(retained)
                    retainedArtifacts.removeValue(forKey: fileName)
                } else {
                    retainedArtifacts[fileName] = retained
                }
            }
        }
        withExtendedLifetime(released) {}
    }

    private func releaseAllHandles() {
        let released = stateLock.withLock { () -> [RetainedArtifact] in
            let retained = Array(retainedArtifacts.values)
            retainedArtifacts.removeAll()
            return retained
        }
        withExtendedLifetime(released) {}
    }

    @discardableResult
    private func evictIfNeeded(manifest: inout CacheManifest) throws -> Bool {
        var totalBytes = manifest.entries.values.reduce(Int64(0)) { $0 + $1.byteCount }
        guard totalBytes > sizeCapBytes else {
            return false
        }

        let candidates = manifest.entries.values
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }
        var changed = false

        for entry in candidates where totalBytes > sizeCapBytes {
            let url = URL(fileURLWithPath: directoryPath).appendingPathComponent(entry.fileName)
            switch removeArtifactIfUnlocked(at: url) {
            case .removed, .missing:
                manifest.entries.removeValue(forKey: entry.fileName)
                totalBytes -= entry.byteCount
                changed = true
            case .busy, .failed:
                continue
            }
        }
        return changed
    }

    private func commit<Result>(staged: AtomicFileWriter.StagedFile<Result>, replacing url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            switch try FileLock(path: url.path).tryLockExclusiveExisting() {
            case .acquired(let handle):
                try staged.commit()
                withExtendedLifetime(handle) {}
            case .missing:
                try staged.commit()
            case .busy:
                throw SidecarError(
                    code: .renderFailed,
                    stage: .render,
                    message: "Unable to replace active derivative cache artifact \(url.path).",
                    recoverable: true
                )
            }
        } else {
            try staged.commit()
        }
    }

    private func removeArtifactIfUnlocked(at url: URL) -> ArtifactRemovalResult {
        do {
            switch try FileLock(path: url.path).tryLockExclusiveExisting() {
            case .missing:
                return .missing
            case .busy:
                return .busy
            case .acquired(let handle):
                try fileManager.removeItem(at: url)
                withExtendedLifetime(handle) {}
                return .removed
            }
        } catch {
            if !fileManager.fileExists(atPath: url.path) {
                return .missing
            }
            return .failed(error)
        }
    }

    private func shouldClearArtifact(url: URL, cacheOwnedNames: Set<String>) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return false
        }
        let fileName = url.lastPathComponent
        return cacheOwnedNames.contains(fileName) || Self.looksLikeDerivativeArtifact(fileName)
    }

    private func shouldClearExpiredTemporary(url: URL) -> Bool {
        guard
            let destinationFileName = AtomicFileWriter.destinationFileName(
                forTemporaryFileName: url.lastPathComponent
            ),
            destinationFileName == manifestURL.lastPathComponent
                || Self.looksLikeDerivativeArtifact(destinationFileName),
            let modifiedAt = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
        else {
            return false
        }
        return modifiedAt < now().addingTimeInterval(-86_400)
    }

    private static func looksLikeDerivativeArtifact(_ fileName: String) -> Bool {
        let supportedExtension = fileName.hasSuffix(".jpg") || fileName.hasSuffix(".tiff")
        guard supportedExtension, fileName.count > 65 else {
            return false
        }

        let prefix = fileName.prefix(64)
        guard prefix.allSatisfy(\.isHexDigit), fileName.dropFirst(64).first == "-" else {
            return false
        }

        return DerivativeRole.allCases.contains { role in
            fileName.contains("-\(role.rawValue).")
        }
    }
}

private struct CachedManifestState {
    var manifest: CacheManifest
    var signature: ManifestSignature
}

private struct ManifestSignature: Equatable {
    var fileIdentifier: UInt64
    var modifiedAt: Date
    var byteCount: Int64
}

private struct RetainedArtifact {
    var handle: FileLockHandle
    var count: Int
}

private enum ArtifactRemovalResult {
    case removed
    case missing
    case busy
    case failed(Error)
}

extension DerivativeFormat {
    fileprivate var fileExtension: String {
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
