import Foundation

/// Discovers Phase 1 source images and records scan-time metadata.
///
/// The scanner implements FR1-001 through FR1-006b. It treats unsupported
/// visible files as recoverable scan errors so a folder batch can continue, but
/// missing input roots fail because there is no batch to recover.
///
/// Two entry points share one discovery pass: `scan` computes each image's
/// `SourceIdentity` (the Phase 1 contract), while `inventory` stops at file
/// metadata so interactive consumers can list large folders without hashing
/// (CORE-5; identity is computed later, only when a pipeline needs it).
public struct ImageScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Scan one file or one folder using the resolved run configuration.
    ///
    /// For file input, `scanRoot` is the file's parent and `relativePath` is the
    /// file name. For folder input, `relativePath` is rooted at the scanned
    /// folder and is the value later used for output tree mirroring.
    public func scan(
        inputPath: String,
        recursive: Bool,
        identityPolicy: SourceIdentityPolicy
    ) throws -> ScanResult {
        let discovered = try discover(inputPath: inputPath, recursive: recursive)

        var images: [SourceImage] = []
        var errors = discovered.errors
        for entry in discovered.entries {
            autoreleasepool {
                do {
                    let identity = try SourceIdentityCalculator.compute(
                        for: URL(fileURLWithPath: entry.path),
                        policy: identityPolicy,
                        fileManager: fileManager
                    )
                    images.append(
                        SourceImage(
                            path: entry.path,
                            relativePath: entry.relativePath,
                            fileName: entry.fileName,
                            fileExtension: entry.fileExtension,
                            fileSize: entry.fileSize,
                            modifiedAt: entry.modifiedAt,
                            detectedType: entry.detectedType,
                            identity: identity
                        )
                    )
                } catch {
                    errors.append(metadataOrIdentityError(path: entry.path, relativePath: entry.relativePath, error: error))
                }
            }
        }

        let sorted = sortedScan(images: images, errors: errors)
        return ScanResult(
            inputPath: discovered.inputPath,
            scanRoot: discovered.scanRoot,
            recursive: recursive,
            identityPolicy: identityPolicy,
            images: sorted.images,
            errors: sorted.errors
        )
    }

    /// Discovery-only variant of `scan`: same visibility, ignore, and
    /// supported-type rules, no identity computation (CORE-5).
    public func inventory(
        inputPath: String,
        recursive: Bool
    ) throws -> ScanInventory {
        let discovered = try discover(inputPath: inputPath, recursive: recursive)
        return ScanInventory(
            inputPath: discovered.inputPath,
            scanRoot: discovered.scanRoot,
            recursive: recursive,
            entries: discovered.entries,
            errors: discovered.errors
        )
    }

    // MARK: - Shared discovery pass

    private struct Discovery {
        var inputPath: String
        var scanRoot: String
        var entries: [ScanInventoryEntry]
        var errors: [ScanErrorRecord]
    }

    private func discover(inputPath: String, recursive: Bool) throws -> Discovery {
        let inputURL = absoluteURL(for: inputPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            throw validationError("Input path does not exist: \(inputURL.path)")
        }

        if isDirectory.boolValue {
            let root = inputURL.standardizedFileURL
            let collected = try discoverDirectoryContents(root, recursive: recursive)
            let sorted = sortedDiscovery(entries: collected.entries, errors: collected.errors)
            return Discovery(inputPath: root.path, scanRoot: root.path, entries: sorted.entries, errors: sorted.errors)
        }

        let fileURL = inputURL.resolvingSymlinksInPath().standardizedFileURL
        let root = fileURL.deletingLastPathComponent()
        // Direct hidden or sidecar inputs follow the same FR1-005 ignore rule
        // as folder contents: they are not images and are not batch failures.
        guard !shouldIgnore(url: fileURL, root: root) else {
            return Discovery(inputPath: fileURL.path, scanRoot: root.path, entries: [], errors: [])
        }

        var entries: [ScanInventoryEntry] = []
        var errors: [ScanErrorRecord] = []
        discoverCandidate(fileURL, root: root, entries: &entries, errors: &errors)
        let sorted = sortedDiscovery(entries: entries, errors: errors)
        return Discovery(inputPath: fileURL.path, scanRoot: root.path, entries: sorted.entries, errors: sorted.errors)
    }

    private func discoverDirectoryContents(
        _ root: URL,
        recursive: Bool
    ) throws -> (entries: [ScanInventoryEntry], errors: [ScanErrorRecord]) {
        var entries: [ScanInventoryEntry] = []
        var errors: [ScanErrorRecord] = []

        if recursive {
            let enumerationErrors = SynchronousScanErrorAccumulator<ScanErrorRecord>()
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsPackageDescendants],
                errorHandler: { url, error in
                    enumerationErrors.append(
                        ScanErrorRecord(
                            path: url.standardizedFileURL.path,
                            relativePath: relativePath(for: url, root: root),
                            error: validationError(
                                "Unable to read directory during scan: \(url.path): \(error.localizedDescription)",
                                recoverable: true
                            )
                        )
                    )
                    return true
                }
            ) else {
                throw validationError("Unable to enumerate input folder: \(root.path)")
            }

            for case let url as URL in enumerator {
                let shouldSkipDescendants = autoreleasepool {
                    discoverIfVisibleFile(url, root: root, entries: &entries, errors: &errors)
                }
                if shouldSkipDescendants {
                    enumerator.skipDescendants()
                }
            }
            errors.append(contentsOf: enumerationErrors.values)

            return (entries, errors)
        }

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsPackageDescendants]
            )
        } catch {
            throw validationError("Unable to read input folder: \(root.path): \(error.localizedDescription)")
        }

        for url in urls {
            _ = autoreleasepool {
                discoverIfVisibleFile(url, root: root, entries: &entries, errors: &errors)
            }
        }

        return (entries, errors)
    }

    private func discoverIfVisibleFile(
        _ candidate: URL,
        root: URL,
        entries: inout [ScanInventoryEntry],
        errors: inout [ScanErrorRecord]
    ) -> Bool {
        let candidate = candidate.standardizedFileURL
        if shouldIgnore(url: candidate, root: root) {
            // Hidden directories are skipped as containers; otherwise their
            // children could reappear as unsupported-file errors.
            return isDirectory(candidate)
        }

        if isSymbolicLink(candidate) {
            errors.append(
                ScanErrorRecord(
                    path: candidate.path,
                    relativePath: relativePath(for: candidate, root: root),
                    error: validationError("Symbolic link skipped during folder scan: \(candidate.path)", recoverable: true)
                )
            )
            return true
        }

        guard isRegularFile(candidate) else {
            return false
        }

        discoverCandidate(candidate, root: root, entries: &entries, errors: &errors)
        return false
    }

    private func discoverCandidate(
        _ candidate: URL,
        root: URL,
        entries: inout [ScanInventoryEntry],
        errors: inout [ScanErrorRecord]
    ) {
        let relativePath = relativePath(for: candidate, root: root)
        guard let type = SupportedImageType(fileExtension: candidate.pathExtension) else {
            // FR1-004 records unsupported visible files without aborting the
            // rest of the scan.
            errors.append(
                ScanErrorRecord(
                    path: candidate.path,
                    relativePath: relativePath,
                    error: SidecarError(
                        code: .unsupportedFormat,
                        stage: .scan,
                        message: "Unsupported image format: \(relativePath)",
                        recoverable: true
                    )
                )
            )
            return
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: candidate.path)
            entries.append(
                ScanInventoryEntry(
                    path: candidate.path,
                    relativePath: relativePath,
                    fileName: candidate.lastPathComponent,
                    fileExtension: candidate.pathExtension,
                    fileSize: fileSize(from: attributes),
                    modifiedAt: modificationDate(from: attributes),
                    detectedType: type
                )
            )
        } catch {
            // A readable folder may still contain a file whose metadata cannot
            // be read; keep the batch recoverable. Message matches the scan
            // path's combined wording so `scan` output is unchanged.
            errors.append(metadataOrIdentityError(path: candidate.path, relativePath: relativePath, error: error))
        }
    }

    private func metadataOrIdentityError(path: String, relativePath: String, error: Error) -> ScanErrorRecord {
        ScanErrorRecord(
            path: path,
            relativePath: relativePath,
            error: SidecarError(
                code: .validationFailed,
                stage: .scan,
                message: "Unable to read source image metadata or identity for \(relativePath): \(error.localizedDescription)",
                recoverable: true
            )
        )
    }

    // MARK: - Sorting and path helpers

    private func sortedScan(
        images: [SourceImage],
        errors: [ScanErrorRecord]
    ) -> (images: [SourceImage], errors: [ScanErrorRecord]) {
        (
            images: images.sorted { comparePaths($0.relativePath, $1.relativePath) },
            errors: errors.sorted { comparePaths($0.relativePath ?? $0.path, $1.relativePath ?? $1.path) }
        )
    }

    private func sortedDiscovery(
        entries: [ScanInventoryEntry],
        errors: [ScanErrorRecord]
    ) -> (entries: [ScanInventoryEntry], errors: [ScanErrorRecord]) {
        (
            entries: entries.sorted { comparePaths($0.relativePath, $1.relativePath) },
            errors: errors.sorted { comparePaths($0.relativePath ?? $0.path, $1.relativePath ?? $1.path) }
        )
    }

    private func absoluteURL(for path: String) -> URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expandedPath)
            .standardizedFileURL
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func shouldIgnore(url: URL, root: URL) -> Bool {
        let relativePath = relativePath(for: url, root: root)
        let components = relativePath.split(separator: "/").map(String.init)
        guard let fileName = components.last else {
            return true
        }

        // Dot-prefixed path components cover hidden files and hidden folders.
        if components.contains(where: { $0.hasPrefix(".") }) {
            return true
        }

        let lowercasedName = fileName.lowercased()
        return lowercasedName == ".ds_store"
            || lowercasedName.hasPrefix("._")
            // Existing sidecars are artifacts to ignore in Phase 1 scans, not
            // source images to analyze or unsupported files to report.
            || lowercasedName.hasSuffix(".ai.json")
            || lowercasedName.hasSuffix(".xmp")
            || ArtifactCleanup.classify(fileName: fileName) != nil
            // Sessions and diagnostic manifests are owned artifacts but are
            // intentionally protected from cleanup; scans still ignore them.
            || matchesOwnedJSON(
                lowercasedName,
                prefix: ArtifactNames.normalizationSessionPrefix
            )
            || matchesOwnedJSON(
                lowercasedName,
                prefix: ArtifactNames.modelInputExportManifestPrefix
            )
    }

    private func matchesOwnedJSON(_ lowercasedName: String, prefix: String) -> Bool {
        lowercasedName.hasPrefix(prefix) && lowercasedName.hasSuffix(".json")
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        var rootPath = root.standardizedFileURL.path
        if !rootPath.hasSuffix("/") {
            rootPath += "/"
        }
        guard path.hasPrefix(rootPath) else {
            return url.lastPathComponent
        }
        return String(path.dropFirst(rootPath.count))
    }

    private func fileSize(from attributes: [FileAttributeKey: Any]) -> Int64 {
        if let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }

    private func modificationDate(from attributes: [FileAttributeKey: Any]) -> Date {
        attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
    }

    private func validationError(_ message: String, recoverable: Bool = false) -> SidecarError {
        SidecarError(code: .validationFailed, stage: .scan, message: message, recoverable: recoverable)
    }
}

/// FileManager enumeration invokes its error callback synchronously. This box
/// gives that callback reference semantics without suggesting cross-task use.
private final class SynchronousScanErrorAccumulator<Value>: @unchecked Sendable {
    private(set) var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }
}

private func comparePaths(_ lhs: String, _ rhs: String) -> Bool {
    // Case-folded ordering keeps dry-scan output stable on case-insensitive
    // filesystems while preserving a deterministic tiebreaker.
    let lowerLHS = lhs.lowercased()
    let lowerRHS = rhs.lowercased()
    if lowerLHS == lowerRHS {
        return lhs < rhs
    }
    return lowerLHS < lowerRHS
}
