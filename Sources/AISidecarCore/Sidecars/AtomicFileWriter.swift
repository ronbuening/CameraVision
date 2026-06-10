import Darwin
import Foundation

/// Writes an artifact by creating a sibling temporary file and renaming it into place.
enum AtomicFileWriter {
    static func write(
        _ data: Data,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        let destination = destination.standardizedFileURL
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: temporary)
            // FR1-012d requires the temporary file to live in the destination
            // directory so rename is atomic on the target filesystem.
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

private struct POSIXWriteError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}
