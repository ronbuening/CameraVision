import Darwin
import Foundation

/// Writes an artifact by creating a sibling temporary file and renaming it into place.
enum AtomicFileWriter {
    static func write(
        _ data: Data,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        try atomicallyReplace(destination, fileManager: fileManager) { temporary in
            try data.write(to: temporary)
        }
    }

    static func writeFile(
        to destination: URL,
        fileManager: FileManager = .default,
        writer: (URL) throws -> Void
    ) throws {
        // Image encoders write directly to URLs; routing through the shared core preserves the same
        // sibling-temp rename contract used for JSON artifacts.
        try atomicallyReplace(destination, fileManager: fileManager, produce: writer)
    }

    /// Shared temp-write + atomic-rename core used by both entry points.
    ///
    /// The temporary file lives in the destination directory (FR1-012d) so the rename is atomic on
    /// the target filesystem. Any failure removes the temporary file and surfaces a recoverable
    /// `.writeFailed` error unless a `SidecarError` was already produced by `produce`.
    private static func atomicallyReplace(
        _ destination: URL,
        fileManager: FileManager,
        produce: (URL) throws -> Void
    ) throws {
        let destination = destination.standardizedFileURL
        let directory = destination.deletingLastPathComponent()
        let temporary = temporaryURL(for: destination, in: directory)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try produce(temporary)
            guard rename(temporary.path, destination.path) == 0 else {
                throw POSIXWriteError(message: String(cString: strerror(errno)))
            }
        } catch let error as SidecarError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to write \(destination.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}

private func temporaryURL(for destination: URL, in directory: URL) -> URL {
    let pathExtension = destination.pathExtension
    let baseName = pathExtension.isEmpty
        ? destination.lastPathComponent
        : destination.deletingPathExtension().lastPathComponent
    // Some Image I/O encoders inspect the destination extension, so temp files
    // keep the final extension while still living beside the final artifact.
    let fileName = pathExtension.isEmpty
        ? ".\(baseName).\(UUID().uuidString).tmp"
        : ".\(baseName).\(UUID().uuidString).\(pathExtension)"
    return directory.appendingPathComponent(fileName)
}

private struct POSIXWriteError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}
