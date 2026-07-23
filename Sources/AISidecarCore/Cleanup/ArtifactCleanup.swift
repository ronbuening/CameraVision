import Foundation

/// AISidecar-owned artifact categories that the cleanup command may remove.
public enum CleanupArtifactKind: String, Codable, Sendable, Equatable, CaseIterable {
    case rawAISidecar = "raw_ai_sidecar"
    case qualityAISidecar = "quality_ai_sidecar"
    case analyzeProgressLog = "analyze_progress_log"
    case analyzeBatchSummary = "analyze_batch_summary"
    case qualityProgressLog = "quality_progress_log"
    case qualityBatchSummary = "quality_batch_summary"
    case xmpExportProgressLog = "xmp_export_progress_log"
    case xmpExportReport = "xmp_export_report"
    case xmpExportSummary = "xmp_export_summary"
    case normalizationProgressLog = "normalization_progress_log"
    case normalizationReport = "normalization_report"
    case normalizationSummary = "normalization_summary"
    case normalizationApplyProgressLog = "normalization_apply_progress_log"
    case normalizationApplyReport = "normalization_apply_report"
    case normalizationApplySummary = "normalization_apply_summary"
    case atomicWriterTemp = "atomic_writer_temp"
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
    private let now: @Sendable () -> Date

    public init(
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.now = now
    }

    /// Plan or execute cleanup under `rootPath`.
    ///
    /// Matching is intentionally filename-based and narrow. Cleanup should not
    /// delete source images, XMP sidecars, backups, derivative cache artifacts,
    /// debug derivatives, or normalization session JSON that can be applied later.
    public func run(rootPath: String, recursive: Bool, dryRun: Bool) throws -> CleanupReport {
        let root = absoluteURL(for: rootPath, fileManager: fileManager, isDirectory: true)
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
                        message:
                            "Unable to remove cleanup artifact \(candidate.url.path): \(error.localizedDescription)",
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
        if isAtomicWriterTemp(fileName) {
            return .atomicWriterTemp
        }
        let lowercased = fileName.lowercased()
        if lowercased.hasSuffix(SidecarNaming.qualitySuffix) {
            return .qualityAISidecar
        }
        if lowercased.hasSuffix(SidecarNaming.taggingSuffix) {
            return .rawAISidecar
        }
        if lowercased.hasPrefix(ArtifactNames.batchProgressPrefix), lowercased.hasSuffix(".jsonl") {
            return .analyzeProgressLog
        }
        if lowercased.hasPrefix(ArtifactNames.batchSummaryPrefix), lowercased.hasSuffix(".json") {
            return .analyzeBatchSummary
        }
        if lowercased.hasPrefix(ArtifactNames.qualityProgressPrefix), lowercased.hasSuffix(".jsonl") {
            return .qualityProgressLog
        }
        if lowercased.hasPrefix(ArtifactNames.qualitySummaryPrefix), lowercased.hasSuffix(".json") {
            return .qualityBatchSummary
        }
        if lowercased.hasPrefix(ArtifactNames.xmpExportProgressPrefix), lowercased.hasSuffix(".jsonl") {
            return .xmpExportProgressLog
        }
        if lowercased.hasPrefix(ArtifactNames.xmpExportReportPrefix), lowercased.hasSuffix(".json") {
            return .xmpExportReport
        }
        if lowercased.hasPrefix(ArtifactNames.xmpExportSummaryPrefix), lowercased.hasSuffix(".md") {
            return .xmpExportSummary
        }
        if lowercased.hasPrefix(ArtifactNames.normalizationProgressPrefix), lowercased.hasSuffix(".jsonl") {
            return .normalizationProgressLog
        }
        if lowercased.hasPrefix(ArtifactNames.normalizationReportPrefix), lowercased.hasSuffix(".json") {
            return .normalizationReport
        }
        if lowercased.hasPrefix(ArtifactNames.normalizationSummaryPrefix), lowercased.hasSuffix(".md") {
            return .normalizationSummary
        }
        if lowercased.hasPrefix(ArtifactNames.normalizationApplyProgressPrefix), lowercased.hasSuffix(".jsonl") {
            return .normalizationApplyProgressLog
        }
        if lowercased.hasPrefix(ArtifactNames.normalizationApplyReportPrefix), lowercased.hasSuffix(".json") {
            return .normalizationApplyReport
        }
        if lowercased.hasPrefix(ArtifactNames.normalizationApplySummaryPrefix), lowercased.hasSuffix(".md") {
            return .normalizationApplySummary
        }
        return nil
    }

    private func cleanupCandidates(in root: URL, recursive: Bool) throws -> [CleanupCandidate] {
        let urls: [URL]
        if recursive {
            guard
                let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsPackageDescendants]
                )
            else {
                return []
            }
            var collected: [URL] = []
            for case let url as URL in enumerator {
                if url.lastPathComponent.hasPrefix("."), isDirectory(url) {
                    enumerator.skipDescendants()
                    continue
                }
                collected.append(url)
            }
            urls = collected
        } else {
            urls = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            )
        }

        return urls.compactMap { url in
            guard isRegularFile(url),
                let kind = Self.classify(fileName: url.lastPathComponent)
            else {
                return nil
            }
            if url.lastPathComponent.hasPrefix("."), kind != .atomicWriterTemp {
                return nil
            }
            if kind == .atomicWriterTemp, !isExpiredAtomicWriterTemp(url) {
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

    private func isExpiredAtomicWriterTemp(_ url: URL) -> Bool {
        guard let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else {
            return false
        }
        return modifiedAt < now().addingTimeInterval(-86_400)
    }

    private static func isAtomicWriterTemp(_ fileName: String) -> Bool {
        guard fileName.hasPrefix(".") else {
            return false
        }
        let components = fileName.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 4,
            components.first?.isEmpty == true,
            components.dropFirst().dropLast(2).contains(where: { !$0.isEmpty }),
            components.last?.isEmpty == false
        else {
            return false
        }
        return UUID(uuidString: String(components[components.count - 2])) != nil
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
