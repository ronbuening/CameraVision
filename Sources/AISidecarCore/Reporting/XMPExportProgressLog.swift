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
    public let path: String

    private let fileHandle: FileHandle
    private let encoder: JSONEncoder

    public init(path: String, fileManager: FileManager = .default) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        self.path = url.path
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            _ = fileManager.createFile(atPath: url.path, contents: nil)
        }
        self.fileHandle = try FileHandle(forWritingTo: url)
        try self.fileHandle.seekToEnd()
    }

    deinit {
        try? fileHandle.close()
    }

    /// Append and flush one target record before the batch advances.
    public func append(_ record: XMPExportProgressRecord) throws {
        do {
            let data = try encoder.encode(record)
            fileHandle.write(data)
            fileHandle.write(Data("\n".utf8))
            try fileHandle.synchronize()
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to append XMP export progress log \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    /// Close the underlying file handle, surfacing close failures as write errors.
    public func close() throws {
        do {
            try fileHandle.close()
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to close XMP export progress log \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}
