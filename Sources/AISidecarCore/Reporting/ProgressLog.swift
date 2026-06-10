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
/// Each append is flushed before the batch advances so interruption recovery can
/// derive completed work directly from the log.
public final class ProgressLog {
    public let path: String

    private let fileHandle: FileHandle
    private let encoder: JSONEncoder

    public init(path: String, fileManager: FileManager = .default) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        self.path = url.path
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: url.path) {
            _ = fileManager.createFile(atPath: url.path, contents: nil)
        }
        self.fileHandle = try FileHandle(forWritingTo: url)
        try self.fileHandle.seekToEnd()
    }

    deinit {
        try? fileHandle.close()
    }

    /// Append and flush one completed-file record before the batch advances.
    public func append(_ record: ProgressRecord) throws {
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
                message: "Unable to append progress log \(path): \(error.localizedDescription)",
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
                message: "Unable to close progress log \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}
