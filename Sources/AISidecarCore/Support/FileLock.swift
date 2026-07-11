import Darwin
import Foundation

/// Cross-process advisory lock for metadata shared by the CLI and app.
struct FileLock {
    var path: String

    func withExclusiveLock<Result>(_ body: () throws -> Result) throws -> Result {
        let descriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXFileLockError(operation: "open", path: path, errorNumber: errno)
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXFileLockError(operation: "lock", path: path, errorNumber: errno)
        }
        defer { flock(descriptor, LOCK_UN) }

        return try body()
    }
}

private struct POSIXFileLockError: LocalizedError {
    var operation: String
    var path: String
    var errorNumber: Int32

    var errorDescription: String? {
        "Unable to \(operation) file lock \(path): \(String(cString: strerror(errorNumber)))"
    }
}
