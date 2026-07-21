import Foundation

/// Append-only JSONL writer shared by the folder-run, XMP export, and normalization progress logs.
///
/// Each append is encoded and written with a trailing newline before the batch advances, so signal and process-crash
/// recovery can derive completed work directly from the kernel's file cache. The file is
/// synchronized every 25 records, on explicit flush, and on close, limiting power-loss exposure to the most
/// recent cadence window. The `label` is woven into I/O error messages so each concrete log keeps its stable
/// wording.
final class JSONLWriter<Record: Encodable>: @unchecked Sendable {
    let path: String
    private let label: String
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder
    private let lock = NSLock()
    private let synchronizationObserver: (@Sendable () -> Void)?
    private var pendingRecordCount = 0
    private var hasPendingWrites = false
    private var isClosed = false

    private static var synchronizationCadence: Int { 25 }

    /// Create or reopen the JSONL file at its final artifact path, seeking to the end for appends.
    init(
        path: String,
        label: String,
        fileManager: FileManager = .default,
        synchronizationObserver: (@Sendable () -> Void)? = nil
    ) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        self.path = url.path
        self.label = label
        self.encoder = JSONCoding.jsonlEncoder()
        self.synchronizationObserver = synchronizationObserver

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

    /// Append one record and synchronize when the 25-record durability cadence is reached.
    func append(_ record: Record) throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            let data = try encoder.encode(record)
            try fileHandle.write(contentsOf: data)
            hasPendingWrites = true
            try fileHandle.write(contentsOf: Data("\n".utf8))
            pendingRecordCount += 1
            if pendingRecordCount >= Self.synchronizationCadence {
                try synchronizePendingWrites()
            }
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

    /// Synchronize pending records without closing the file handle.
    func flush() throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            try synchronizePendingWrites()
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to flush \(label) \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    /// Synchronize pending records and close the file handle, surfacing failures as write errors.
    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else {
            return
        }
        do {
            try synchronizePendingWrites()
            try fileHandle.close()
            isClosed = true
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to close \(label) \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func synchronizePendingWrites() throws {
        guard hasPendingWrites else {
            return
        }
        try fileHandle.synchronize()
        pendingRecordCount = 0
        hasPendingWrites = false
        synchronizationObserver?()
    }
}
