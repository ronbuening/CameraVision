import Foundation

/// Stable per-file progress status written to folder-run JSONL logs.
public enum ProgressStatus: String, Codable, Sendable, Equatable {
    case written
    case skippedExisting = "skipped_existing"
    case failed
    case dryRun = "dry_run"
}

/// One self-contained JSONL progress record for a completed source or scan error.
public struct ProgressRecord: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var sourcePath: String?
    public var relativePath: String?
    public var sidecarPath: String?
    public var status: ProgressStatus
    public var errors: [SidecarError]
    public var durationMs: Int

    enum CodingKeys: String, CodingKey {
        case timestamp
        case sourcePath = "source_path"
        case relativePath = "relative_path"
        case sidecarPath = "sidecar_path"
        case status
        case errors
        case durationMs = "duration_ms"
    }

    public init(
        timestamp: Date = Date(),
        sourcePath: String?,
        relativePath: String?,
        sidecarPath: String?,
        status: ProgressStatus,
        errors: [SidecarError] = [],
        durationMs: Int
    ) {
        self.timestamp = timestamp
        self.sourcePath = sourcePath
        self.relativePath = relativePath
        self.sidecarPath = sidecarPath
        self.status = status
        self.errors = errors
        self.durationMs = durationMs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(sidecarPath, forKey: .sidecarPath)
        try container.encode(status, forKey: .status)
        try container.encode(errors, forKey: .errors)
        try container.encode(durationMs, forKey: .durationMs)
    }
}

/// Append-only JSONL progress log for folder runs.
///
/// Each append reaches the kernel's file cache before the batch advances, preserving
/// process-interruption recovery. Explicit flush, close, and the 25-record cadence
/// synchronize pending records for bounded power-loss durability.
public final class ProgressLog: @unchecked Sendable {
    private let writer: JSONLWriter<ProgressRecord>

    public var path: String { writer.path }

    public init(path: String, fileManager: FileManager = .default) throws {
        self.writer = try JSONLWriter(path: path, label: "progress log", fileManager: fileManager)
    }

    /// Append one completed-file record before the batch advances.
    public func append(_ record: ProgressRecord) throws {
        try writer.append(record)
    }

    /// Synchronize pending records without closing the log.
    public func flush() throws {
        try writer.flush()
    }

    /// Synchronize pending records and close the underlying file handle.
    public func close() throws {
        try writer.close()
    }
}
