import Darwin
import Foundation

/// Writes an artifact by creating a sibling temporary file and renaming it into place.
enum AtomicFileWriter {
    struct StagedFile<Result> {
        let destination: URL
        let temporary: URL
        let result: Result
        let fileManager: FileManager

        func commit() throws {
            guard rename(temporary.path, destination.path) == 0 else {
                throw writeError(
                    destination: destination, underlying: POSIXWriteError(message: String(cString: strerror(errno))))
            }
        }

        func discard() {
            try? fileManager.removeItem(at: temporary)
        }
    }

    static func write(
        _ data: Data,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        try atomicallyReplace(destination, fileManager: fileManager) { temporary in
            try data.write(to: temporary)
        }
    }

    static func writeFile<Result>(
        to destination: URL,
        fileManager: FileManager = .default,
        writer: (URL) throws -> Result
    ) throws -> Result {
        // Image encoders write directly to URLs; routing through the shared core preserves the same
        // sibling-temp rename contract used for JSON artifacts.
        try atomicallyReplace(destination, fileManager: fileManager, produce: writer)
    }

    /// Produce a sibling temporary file without committing its final rename.
    ///
    /// Cache writers use this split phase so expensive image encoding remains parallel while the
    /// final artifact rename and manifest mutation share one short cross-process critical section.
    static func stageFile<Result>(
        to destination: URL,
        fileManager: FileManager = .default,
        writer: (URL) throws -> Result
    ) throws -> StagedFile<Result> {
        let destination = destination.standardizedFileURL
        let directory = destination.deletingLastPathComponent()
        let temporary = temporaryURL(for: destination, in: directory)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return StagedFile(
                destination: destination,
                temporary: temporary,
                result: try writer(temporary),
                fileManager: fileManager
            )
        } catch let error as SidecarError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw writeError(destination: destination, underlying: error)
        }
    }

    /// Recover the intended destination name from the project's sibling-temp convention.
    static func destinationFileName(forTemporaryFileName fileName: String) -> String? {
        guard fileName.hasPrefix(".") else {
            return nil
        }
        let components = fileName.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 4,
            components.first?.isEmpty == true,
            UUID(uuidString: String(components[components.count - 2])) != nil,
            let pathExtension = components.last,
            !pathExtension.isEmpty
        else {
            return nil
        }
        let baseName = components.dropFirst().dropLast(2).joined(separator: ".")
        guard !baseName.isEmpty else {
            return nil
        }
        return pathExtension == "tmp" ? baseName : "\(baseName).\(pathExtension)"
    }

    /// Shared temp-write + atomic-rename core used by both entry points.
    ///
    /// The temporary file lives in the destination directory (FR1-012d) so the rename is atomic on
    /// the target filesystem. Any failure removes the temporary file and surfaces a recoverable
    /// `.writeFailed` error unless a `SidecarError` was already produced by `produce`.
    private static func atomicallyReplace<Result>(
        _ destination: URL,
        fileManager: FileManager,
        produce: (URL) throws -> Result
    ) throws -> Result {
        let destination = destination.standardizedFileURL
        let directory = destination.deletingLastPathComponent()
        let temporary = temporaryURL(for: destination, in: directory)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let result = try produce(temporary)
            guard rename(temporary.path, destination.path) == 0 else {
                throw POSIXWriteError(message: String(cString: strerror(errno)))
            }
            return result
        } catch let error as SidecarError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw writeError(destination: destination, underlying: error)
        }
    }

    private static func writeError(destination: URL, underlying error: Error) -> SidecarError {
        SidecarError(
            code: .writeFailed,
            stage: .write,
            message: "Unable to write \(destination.path): \(error.localizedDescription)",
            recoverable: true
        )
    }
}

private func temporaryURL(for destination: URL, in directory: URL) -> URL {
    let pathExtension = destination.pathExtension
    let baseName =
        pathExtension.isEmpty
        ? destination.lastPathComponent
        : destination.deletingPathExtension().lastPathComponent
    // Some Image I/O encoders inspect the destination extension, so temp files
    // keep the final extension while still living beside the final artifact.
    let fileName =
        pathExtension.isEmpty
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
