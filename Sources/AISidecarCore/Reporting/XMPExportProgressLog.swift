import Foundation

/// Stable status for one completed XMP target export attempt.
public enum XMPExportTargetStatus: String, Codable, Sendable, Equatable {
    case written
    case created
    case unchanged
    case failed
    case dryRun = "dry_run"
    case interrupted
}

/// Self-contained JSONL progress record for a completed XMP target.
public struct XMPExportProgressRecord: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var targetXMPPath: String
    public var targetRelativePath: String
    public var status: XMPExportTargetStatus
    public var sourceMembers: [SourceMemberPlan]
    public var addedFlatKeywords: [String]
    public var addedHierarchicalKeywords: [String]
    public var backup: XMPBackupRecord?
    public var validation: XMPMergeValidationResult?
    public var errors: [SidecarError]
    public var durationMs: Int

    enum CodingKeys: String, CodingKey {
        case timestamp
        case targetXMPPath = "target_xmp_path"
        case targetRelativePath = "target_relative_path"
        case status
        case sourceMembers = "source_members"
        case addedFlatKeywords = "added_flat_keywords"
        case addedHierarchicalKeywords = "added_hierarchical_keywords"
        case backup
        case validation
        case errors
        case durationMs = "duration_ms"
    }

    public init(
        timestamp: Date = Date(),
        targetXMPPath: String,
        targetRelativePath: String,
        status: XMPExportTargetStatus,
        sourceMembers: [SourceMemberPlan],
        addedFlatKeywords: [String],
        addedHierarchicalKeywords: [String],
        backup: XMPBackupRecord? = nil,
        validation: XMPMergeValidationResult? = nil,
        errors: [SidecarError] = [],
        durationMs: Int
    ) {
        self.timestamp = timestamp
        self.targetXMPPath = targetXMPPath
        self.targetRelativePath = targetRelativePath
        self.status = status
        self.sourceMembers = sourceMembers
        self.addedFlatKeywords = addedFlatKeywords
        self.addedHierarchicalKeywords = addedHierarchicalKeywords
        self.backup = backup
        self.validation = validation
        self.errors = errors
        self.durationMs = durationMs
    }
}

/// Append-only JSONL writer for XMP target progress records.
public final class XMPExportProgressLog {
    private let writer: JSONLWriter<XMPExportProgressRecord>

    public var path: String { writer.path }

    public init(path: String, fileManager: FileManager = .default) throws {
        self.writer = try JSONLWriter(path: path, label: "XMP export progress log", fileManager: fileManager)
    }

    /// Append and flush one target record before the batch advances.
    public func append(_ record: XMPExportProgressRecord) throws {
        try writer.append(record)
    }

    /// Close the underlying file handle, surfacing close failures as write errors.
    public func close() throws {
        try writer.close()
    }
}
