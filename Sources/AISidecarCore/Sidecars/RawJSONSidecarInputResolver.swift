import Foundation

/// Source identity outcome recorded for a resolved raw sidecar input.
public enum SourceIdentityStatus: String, Codable, Sendable, Equatable {
    case matched
    case mismatched
    case skipped
}

/// Raw sidecar and source-image information prepared for Phase 2 export.
public struct ResolvedRawSidecarInput: Sendable, Equatable {
    public var sidecarPath: URL
    public var document: RawJSONSidecarDocument
    /// Associated quality-only sidecar, if present. For quality-only input these alias the primary fields.
    public var qualitySidecarPath: URL?
    public var qualityDocument: RawJSONSidecarDocument?
    public var sourcePath: URL?
    public var sourceIdentityStatus: SourceIdentityStatus
    public var relativePath: String?
    public var warnings: [SidecarError]

    public init(
        sidecarPath: URL,
        document: RawJSONSidecarDocument,
        qualitySidecarPath: URL? = nil,
        qualityDocument: RawJSONSidecarDocument? = nil,
        sourcePath: URL?,
        sourceIdentityStatus: SourceIdentityStatus,
        relativePath: String?,
        warnings: [SidecarError]
    ) {
        self.sidecarPath = sidecarPath
        self.document = document
        self.qualitySidecarPath = qualitySidecarPath
        self.qualityDocument = qualityDocument
        self.sourcePath = sourcePath
        self.sourceIdentityStatus = sourceIdentityStatus
        self.relativePath = relativePath
        self.warnings = warnings
    }
}

/// Recoverable per-file failure from a folder `--from-json` scan.
public struct RawJSONSidecarInputFailure: Sendable, Equatable {
    public var sidecarPath: URL
    public var relativePath: String?
    public var error: SidecarError

    public init(sidecarPath: URL, relativePath: String?, error: SidecarError) {
        self.sidecarPath = sidecarPath
        self.relativePath = relativePath
        self.error = error
    }
}

/// Batch result for Phase 2 raw sidecar input planning.
public struct RawJSONSidecarInputBatch: Sendable, Equatable {
    public var inputs: [ResolvedRawSidecarInput]
    public var failures: [RawJSONSidecarInputFailure]

    public init(inputs: [ResolvedRawSidecarInput], failures: [RawJSONSidecarInputFailure]) {
        self.inputs = inputs
        self.failures = failures
    }
}

/// Scans and resolves `write-xmp --from-json` inputs before candidate extraction and XMP planning.
///
/// Folder scans keep bad sidecars as per-file failures so later export reporting
/// can continue the batch. Direct file input throws immediately because there is
/// no surrounding batch to preserve.
public struct RawJSONSidecarInputResolver {
    private let fileManager: FileManager
    private let reader: RawJSONSidecarReader

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.reader = RawJSONSidecarReader(fileManager: fileManager)
    }

    /// Resolve raw sidecar inputs for Phase 2 `--from-json` mode.
    public func resolve(
        fromJSONPath: String,
        configuration: ResolvedXMPExportConfiguration
    ) throws -> RawJSONSidecarInputBatch {
        let inputURL = absoluteURL(for: fromJSONPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            throw validationError("Raw sidecar input path does not exist: \(inputURL.path)", recoverable: false)
        }

        if isDirectory.boolValue {
            return try resolveFolder(inputURL, configuration: configuration)
        }

        guard isRawSidecar(inputURL), isRegularFile(inputURL) else {
            throw validationError(
                "Direct --from-json input must be a .ai.json file: \(inputURL.path)", recoverable: false)
        }

        var candidateURLs = [inputURL]
        let sibling = siblingSidecarURL(for: inputURL)
        if isRegularFile(sibling) {
            candidateURLs.append(sibling)
        }
        let inputs = try candidateURLs.map {
            try resolveCandidate($0, relativePath: $0.lastPathComponent, configuration: configuration)
        }
        return RawJSONSidecarInputBatch(inputs: groupedSidecarInputs(inputs), failures: [])
    }

    /// Re-read one stored sidecar reference and whichever current pair member still exists.
    ///
    /// Apply-session already verifies source identity against the frozen session. This path
    /// deliberately resolves only current contributor documents so `--allow-stale` and
    /// source-verification skips are not contradicted by a second identity gate. Read-only
    /// display surfaces (the GUI's quality panel) use the same path so what they show is
    /// what apply-time grading would consume.
    public func resolveCurrentSidecarPair(at sidecarPath: String) -> RawJSONSidecarInputBatch {
        let referenceURL = absoluteURL(for: sidecarPath)
        guard isRawSidecar(referenceURL) else {
            return RawJSONSidecarInputBatch(
                inputs: [],
                failures: [
                    RawJSONSidecarInputFailure(
                        sidecarPath: referenceURL,
                        relativePath: referenceURL.lastPathComponent,
                        error: validationError(
                            "Stored raw sidecar reference must be a .ai.json file: \(referenceURL.path)",
                            recoverable: true
                        )
                    )
                ]
            )
        }

        let siblingURL = siblingSidecarURL(for: referenceURL)
        let candidateURLs = [referenceURL, siblingURL]
            .reduce(into: [URL]()) { result, candidate in
                guard isRegularFile(candidate), !result.contains(candidate) else {
                    return
                }
                result.append(candidate)
            }
        guard !candidateURLs.isEmpty else {
            return RawJSONSidecarInputBatch(
                inputs: [],
                failures: [
                    RawJSONSidecarInputFailure(
                        sidecarPath: referenceURL,
                        relativePath: referenceURL.lastPathComponent,
                        error: validationError(
                            "Stored raw sidecar and its quality pair are unavailable: \(referenceURL.path)",
                            recoverable: true
                        )
                    )
                ]
            )
        }

        var inputs: [ResolvedRawSidecarInput] = []
        var failures: [RawJSONSidecarInputFailure] = []
        for candidate in candidateURLs {
            do {
                inputs.append(
                    ResolvedRawSidecarInput(
                        sidecarPath: candidate,
                        document: try reader.read(from: candidate),
                        sourcePath: nil,
                        sourceIdentityStatus: .skipped,
                        relativePath: candidate.lastPathComponent,
                        warnings: []
                    )
                )
            } catch {
                failures.append(
                    RawJSONSidecarInputFailure(
                        sidecarPath: candidate,
                        relativePath: candidate.lastPathComponent,
                        error: error as? SidecarError
                            ?? validationError(
                                "Unable to re-read current raw sidecar \(candidate.path): "
                                    + error.localizedDescription,
                                recoverable: true
                            )
                    )
                )
            }
        }
        return RawJSONSidecarInputBatch(
            inputs: groupedSidecarInputs(inputs),
            failures: failures.sorted {
                comparePaths($0.sidecarPath.path, $1.sidecarPath.path)
            }
        )
    }

    private func resolveFolder(
        _ root: URL,
        configuration: ResolvedXMPExportConfiguration
    ) throws -> RawJSONSidecarInputBatch {
        let root = root.standardizedFileURL
        let discovery = try candidateSidecars(in: root, recursive: configuration.recursive)
        var inputs: [ResolvedRawSidecarInput] = []
        var failures = discovery.failures

        for candidate in discovery.urls {
            let relativePath = relativePath(for: candidate, root: root)
            do {
                inputs.append(
                    try resolveCandidate(candidate, relativePath: relativePath, configuration: configuration)
                )
            } catch let error as SidecarError {
                failures.append(
                    RawJSONSidecarInputFailure(sidecarPath: candidate, relativePath: relativePath, error: error)
                )
            }
        }

        failures.sort {
            comparePaths($0.relativePath ?? $0.sidecarPath.path, $1.relativePath ?? $1.sidecarPath.path)
        }
        return RawJSONSidecarInputBatch(inputs: groupedSidecarInputs(inputs), failures: failures)
    }

    private func resolveCandidate(
        _ sidecarURL: URL,
        relativePath: String,
        configuration: ResolvedXMPExportConfiguration
    ) throws -> ResolvedRawSidecarInput {
        let sidecarURL = sidecarURL.standardizedFileURL
        let document = try reader.read(from: sidecarURL)
        let sourcePath = try resolveSourcePath(
            for: document.sidecar,
            sidecarURL: sidecarURL,
            configuration: configuration
        )
        let verification = try verifySourceIdentity(
            sourcePath: sourcePath,
            recordedIdentity: document.sidecar.source.identity,
            policy: configuration.sourceVerification
        )

        return ResolvedRawSidecarInput(
            sidecarPath: sidecarURL,
            document: document,
            sourcePath: sourcePath,
            sourceIdentityStatus: verification.status,
            relativePath: relativePath,
            warnings: verification.warnings
        )
    }

    private func resolveSourcePath(
        for sidecar: RawJSONSidecar,
        sidecarURL: URL,
        configuration: ResolvedXMPExportConfiguration
    ) throws -> URL? {
        let sourceRelativePath = sidecar.source.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sourceRoot = configuration.sourceRoot, !sourceRelativePath.isEmpty {
            let candidate = absoluteURL(for: sourceRoot).appendingPathComponent(sourceRelativePath).standardizedFileURL
            if isRegularFile(candidate) {
                return candidate
            }
        }

        if sidecar.source.path.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: sidecar.source.path).standardizedFileURL
            if isRegularFile(candidate) {
                return candidate
            }
        }

        let sibling = siblingSourceURL(for: sidecarURL)
        if isRegularFile(sibling) {
            return sibling
        }

        // FR2-000d allows staging from raw sidecars when the later XMP target
        // can be derived from source.relative_path and --output-dir.
        if configuration.sourceVerification == .skip,
            configuration.outputDir != nil,
            !sourceRelativePath.isEmpty
        {
            return nil
        }

        throw SidecarError(
            code: .sourceMissing,
            stage: .scan,
            message: "Unable to resolve source image for raw sidecar: \(sidecarURL.path)",
            recoverable: true
        )
    }

    private func verifySourceIdentity(
        sourcePath: URL?,
        recordedIdentity: SourceIdentity,
        policy: XMPSourceVerificationPolicy
    ) throws -> (status: SourceIdentityStatus, warnings: [SidecarError]) {
        guard policy != .skip else {
            return (.skipped, [])
        }
        guard let sourcePath else {
            throw SidecarError(
                code: .sourceMissing,
                stage: .scan,
                message: "Source identity cannot be verified because the source image is unresolved.",
                recoverable: true
            )
        }

        let currentIdentity: SourceIdentity
        do {
            currentIdentity = try SourceIdentityCalculator.compute(
                for: sourcePath,
                policy: recordedIdentity.policy,
                fileManager: fileManager
            )
        } catch {
            let sidecarError = sourceIdentityMismatch(
                "Unable to compute source identity for \(sourcePath.path): \(error.localizedDescription)"
            )
            if policy == .warn {
                return (.mismatched, [sidecarError])
            }
            throw sidecarError
        }

        guard currentIdentity == recordedIdentity else {
            let sidecarError = sourceIdentityMismatch("Source identity mismatch for \(sourcePath.path).")
            if policy == .warn {
                return (.mismatched, [sidecarError])
            }
            throw sidecarError
        }

        return (.matched, [])
    }

    private func candidateSidecars(
        in root: URL,
        recursive: Bool
    ) throws -> (urls: [URL], failures: [RawJSONSidecarInputFailure]) {
        if recursive {
            let enumerationFailures = SynchronousInputFailureAccumulator()
            guard
                let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsPackageDescendants],
                    errorHandler: { url, error in
                        let url = url.standardizedFileURL
                        enumerationFailures.append(
                            RawJSONSidecarInputFailure(
                                sidecarPath: url,
                                relativePath: relativePath(for: url, root: root),
                                error: validationError(
                                    "Unable to read directory during raw sidecar scan: \(url.path): \(error.localizedDescription)",
                                    recoverable: true
                                )
                            )
                        )
                        return true
                    }
                )
            else {
                throw validationError("Unable to enumerate raw sidecar folder: \(root.path)", recoverable: false)
            }

            var urls: [URL] = []
            for case let url as URL in enumerator {
                let url = url.standardizedFileURL
                if shouldIgnore(url: url, root: root) {
                    if isDirectory(url) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if isRegularFile(url), isRawSidecar(url) {
                    urls.append(url)
                }
            }
            return (sorted(urls, root: root), enumerationFailures.values)
        }

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsPackageDescendants]
            )
        } catch {
            throw validationError(
                "Unable to enumerate raw sidecar folder \(root.path): \(error.localizedDescription)",
                recoverable: false
            )
        }
        return (
            sorted(
                urls
                    .map(\.standardizedFileURL)
                    .filter { !shouldIgnore(url: $0, root: root) }
                    .filter { isRegularFile($0) && isRawSidecar($0) },
                root: root
            ),
            []
        )
    }

    private func isRawSidecar(_ url: URL) -> Bool {
        sidecarKind(for: url) != nil
    }

    private func shouldIgnore(url: URL, root: URL) -> Bool {
        let components = relativePath(for: url, root: root).split(separator: "/").map(String.init)
        return components.contains { $0.hasPrefix(".") }
    }

    private func siblingSourceURL(for sidecarURL: URL) -> URL {
        let sourceFileName = sidecarBaseFileName(for: sidecarURL) ?? sidecarURL.lastPathComponent
        return sidecarURL.deletingLastPathComponent().appendingPathComponent(sourceFileName).standardizedFileURL
    }

    private func siblingSidecarURL(for sidecarURL: URL) -> URL {
        guard let kind = sidecarKind(for: sidecarURL), let baseName = sidecarBaseFileName(for: sidecarURL) else {
            return sidecarURL
        }
        let siblingSuffix: String
        switch kind {
        case .tagging:
            siblingSuffix = SidecarNaming.qualitySuffix
        case .quality:
            siblingSuffix = SidecarNaming.taggingSuffix
        }
        return sidecarURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)\(siblingSuffix)")
            .standardizedFileURL
    }

    private func groupedSidecarInputs(_ inputs: [ResolvedRawSidecarInput]) -> [ResolvedRawSidecarInput] {
        let grouped = Dictionary(grouping: inputs) { sidecarPairingKey(for: $0.sidecarPath) }
        return grouped.values.compactMap { group in
            // Existing Phase 2 consumers keep the tagging document as their
            // primary input; quality data rides beside it for grading.
            let tagging = group.first { sidecarKind(for: $0.sidecarPath) == .tagging }
            let quality = group.first { sidecarKind(for: $0.sidecarPath) == .quality }
            guard var primary = tagging ?? quality else {
                return nil
            }
            if let quality {
                primary.qualitySidecarPath = quality.sidecarPath
                primary.qualityDocument = quality.document
                if quality.sidecarPath != primary.sidecarPath {
                    primary.warnings.append(contentsOf: quality.warnings)
                    if quality.sourceIdentityStatus == .mismatched {
                        primary.sourceIdentityStatus = .mismatched
                    }
                }
            }
            return primary
        }
        .sorted {
            comparePaths($0.relativePath ?? $0.sidecarPath.path, $1.relativePath ?? $1.sidecarPath.path)
        }
    }

    private func sidecarPairingKey(for url: URL) -> String {
        url.deletingLastPathComponent()
            .appendingPathComponent(sidecarBaseFileName(for: url) ?? url.lastPathComponent)
            .standardizedFileURL.path
    }

    private func sidecarBaseFileName(for url: URL) -> String? {
        guard let kind = sidecarKind(for: url) else {
            return nil
        }
        let suffix: String
        switch kind {
        case .tagging:
            suffix = SidecarNaming.taggingSuffix
        case .quality:
            suffix = SidecarNaming.qualitySuffix
        }
        return String(url.lastPathComponent.dropLast(suffix.count))
    }

    private func sidecarKind(for url: URL) -> RawSidecarKind? {
        let fileName = url.lastPathComponent.lowercased()
        if fileName.hasSuffix(SidecarNaming.qualitySuffix) {
            return .quality
        }
        if fileName.hasSuffix(SidecarNaming.taggingSuffix) {
            return .tagging
        }
        return nil
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func sorted(_ urls: [URL], root: URL) -> [URL] {
        urls.sorted {
            comparePaths(relativePath(for: $0, root: root), relativePath(for: $1, root: root))
        }
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

    private func absoluteURL(for path: String) -> URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expandedPath)
            .standardizedFileURL
    }

    private func validationError(_ message: String, recoverable: Bool) -> SidecarError {
        SidecarError(code: .validationFailed, stage: .scan, message: message, recoverable: recoverable)
    }

    private func sourceIdentityMismatch(_ message: String) -> SidecarError {
        SidecarError(code: .sourceIdentityMismatch, stage: .scan, message: message, recoverable: true)
    }
}

/// FileManager enumeration invokes its error callback synchronously. This box
/// gives that callback reference semantics without suggesting cross-task use.
private final class SynchronousInputFailureAccumulator: @unchecked Sendable {
    private(set) var values: [RawJSONSidecarInputFailure] = []

    func append(_ value: RawJSONSidecarInputFailure) {
        values.append(value)
    }
}

private func comparePaths(_ lhs: String, _ rhs: String) -> Bool {
    let lowerLHS = lhs.lowercased()
    let lowerRHS = rhs.lowercased()
    if lowerLHS == lowerRHS {
        return lhs < rhs
    }
    return lowerLHS < lowerRHS
}
