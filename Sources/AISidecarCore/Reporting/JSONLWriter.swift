import Foundation

/// Append-only JSONL writer shared by the folder-run, XMP export, and normalization progress logs.
///
/// Each append is encoded, written with a trailing newline, and flushed before the batch advances so
/// interruption recovery can derive completed work directly from the log. The `label` is woven into
/// write/close error messages so each concrete log keeps its original, stable wording.
final class JSONLWriter<Record: Encodable> {
    let path: String
    private let label: String
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder

    /// Create or reopen the JSONL file at its final artifact path, seeking to the end for appends.
    init(path: String, label: String, fileManager: FileManager = .default) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        self.path = url.path
        self.label = label
        self.encoder = JSONCoding.jsonlEncoder()

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

    /// Append and flush one record before the batch advances.
    func append(_ record: Record) throws {
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
                message: "Unable to append \(label) \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    /// Close the underlying file handle, surfacing close failures as write errors.
    func close() throws {
        do {
            try fileHandle.close()
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to close \(label) \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}
