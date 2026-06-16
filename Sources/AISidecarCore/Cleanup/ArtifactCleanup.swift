import Foundation

/// AISidecar-owned artifact categories that the cleanup command may remove.
public enum CleanupArtifactKind: String, Codable, Sendable, Equatable, CaseIterable {
    case rawAISidecar = "raw_ai_sidecar"
    case analyzeProgressLog = "analyze_progress_log"
    case analyzeBatchSummary = "analyze_batch_summary"
    case xmpExportProgressLog = "xmp_export_progress_log"
    case xmpExportReport = "xmp_export_report"
    case xmpExportSummary = "xmp_export_summary"
    case normalizationProgressLog = "normalization_progress_log"
    case normalizationReport = "normalization_report"
    case normalizationSummary = "normalization_summary"
    case normalizationApplyProgressLog = "normalization_apply_progress_log"
    case normalizationApplyReport = "normalization_apply_report"
    case normalizationApplySummary = "normalization_apply_summary"
}

/// Per-file result emitted by an artifact cleanup pass.
public struct CleanupArtifactRecord: Codable, Sendable, Equatable {
    public var kind: CleanupArtifactKind
    public var path: String
    public var relativePath: String
    public var removed: Bool
    public var error: SidecarError?

    enum CodingKeys: String, CodingKey {
        case kind
        case path
        case relativePath = "relative_path"
        case removed
        case error
    }

    public init(
        kind: CleanupArtifactKind,
        path: String,
        relativePath: String,
        removed: Bool,
        error: SidecarError? = nil
    ) {
        self.kind = kind
        self.path = path
        self.relativePath = relativePath
        self.removed = removed
        self.error = error
    }
}

/// Summary document for an AISidecar artifact cleanup pass.
public struct CleanupReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = "ai-sidecar-cleanup-report/1.0"

    public var schemaVersion: String
    public var rootPath: String
    public var recursive: Bool
    public var dryRun: Bool
    public var plannedCount: Int
    public var removedCount: Int
    public var failedCount: Int
    public var artifacts: [CleanupArtifactRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case rootPath = "root_path"
        case recursive
        case dryRun = "dry_run"
        case plannedCount = "planned_count"
        case removedCount = "removed_count"
        case failedCount = "failed_count"
        case artifacts
    }

    public init(
        schemaVersion: String = Self.currentSchemaVersion,
        rootPath: String,
        recursive: Bool,
        dryRun: Bool,
        plannedCount: Int,
        removedCount: Int,
        failedCount: Int,
        artifacts: [CleanupArtifactRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.rootPath = rootPath
        self.recursive = recursive
        self.dryRun = dryRun
        self.plannedCount = plannedCount
        self.removedCount = removedCount
        self.failedCount = failedCount
        self.artifacts = artifacts
    }
}

/// Scans a folder for AISidecar-owned raw sidecars and run artifacts, then optionally removes them.
public struct ArtifactCleanup {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Plan or execute cleanup under `rootPath`.
    ///
    /// Matching is intentionally filename-based and narrow. Cleanup should not
    /// delete source images, XMP sidecars, backups, derivative cache artifacts,
    /// debug derivatives, or normalization session JSON that can be applied later.
    public func run(rootPath: String, recursive: Bool, dryRun: Bool) throws -> CleanupReport {
        let root = absoluteURL(for: rootPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SidecarError.configInvalid("Cleanup root must be an existing folder: \(root.path)")
        }

        let candidates = try cleanupCandidates(in: root, recursive: recursive)
        var records: [CleanupArtifactRecord] = []
        records.reserveCapacity(candidates.count)

        for candidate in candidates {
            var record = CleanupArtifactRecord(
                kind: candidate.kind,
                path: candidate.url.path,
                relativePath: candidate.relativePath,
                removed: false
            )
            if !dryRun {
                do {
                    try fileManager.removeItem(at: candidate.url)
                    record.removed = true
                } catch {
                    record.error = SidecarError(
                        code: .writeFailed,
                        stage: .write,
                        message: "Unable to remove cleanup artifact \(candidate.url.path): \(error.localizedDescription)",
                        recoverable: true
                    )
                }
            }
            records.append(record)
        }

        return CleanupReport(
            rootPath: root.path,
            recursive: recursive,
            dryRun: dryRun,
            plannedCount: records.count,
            removedCount: records.filter(\.removed).count,
            failedCount: records.filter { $0.error != nil }.count,
            artifacts: records
        )
    }

    /// Classify filenames that are safe for artifact cleanup.
    public static func classify(fileName: String) -> CleanupArtifactKind? {
        let lowercased = fileName.lowercased()
        if lowercased.hasSuffix(".ai.json") {
            return .rawAISidecar
        }
        if lowercased.hasPrefix("batch-progress-"), lowercased.hasSuffix(".jsonl") {
            return .analyzeProgressLog
        }
        if lowercased.hasPrefix("batch-summary-"), lowercased.hasSuffix(".json") {
            return .analyzeBatchSummary
        }
        if lowercased.hasPrefix("xmp-export-progress-"), lowercased.hasSuffix(".jsonl") {
            return .xmpExportProgressLog
        }
        if lowercased.hasPrefix("xmp-export-report-"), lowercased.hasSuffix(".json") {
            return .xmpExportReport
        }
        if lowercased.hasPrefix("xmp-export-summary-"), lowercased.hasSuffix(".md") {
            return .xmpExportSummary
        }
        if lowercased.hasPrefix("normalization-progress-"), lowercased.hasSuffix(".jsonl") {
            return .normalizationProgressLog
        }
        if lowercased.hasPrefix("normalization-report-"), lowercased.hasSuffix(".json") {
            return .normalizationReport
        }
        if lowercased.hasPrefix("normalization-summary-"), lowercased.hasSuffix(".md") {
            return .normalizationSummary
        }
        if lowercased.hasPrefix("normalization-apply-progress-"), lowercased.hasSuffix(".jsonl") {
            return .normalizationApplyProgressLog
        }
        if lowercased.hasPrefix("normalization-apply-report-"), lowercased.hasSuffix(".json") {
            return .normalizationApplyReport
        }
        if lowercased.hasPrefix("normalization-apply-summary-"), lowercased.hasSuffix(".md") {
            return .normalizationApplySummary
        }
        return nil
    }

    private func cleanupCandidates(in root: URL, recursive: Bool) throws -> [CleanupCandidate] {
        let urls: [URL]
        if recursive {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }
            urls = enumerator.compactMap { $0 as? URL }
        } else {
            urls = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        }

        return urls.compactMap { url in
            guard isRegularFile(url), let kind = Self.classify(fileName: url.lastPathComponent) else {
                return nil
            }
            return CleanupCandidate(
                kind: kind,
                url: url.standardizedFileURL,
                relativePath: relativePath(for: url, root: root)
            )
        }
        .sorted { lhs, rhs in
            lhs.relativePath < rhs.relativePath
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func absoluteURL(for path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expanded, isDirectory: true)
            .standardizedFileURL
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard path.hasPrefix(prefix) else {
            return url.lastPathComponent
        }
        return String(path.dropFirst(prefix.count))
    }
}

private struct CleanupCandidate {
    var kind: CleanupArtifactKind
    var url: URL
    var relativePath: String
}
