import Darwin
import Foundation

/// Cross-process advisory lock for metadata shared by the CLI and app.
struct FileLock {
    var path: String

    func withExclusiveLock<Result>(_ body: () throws -> Result) throws -> Result {
        let handle = try lockCreatingFile(operation: LOCK_EX)
        defer { withExtendedLifetime(handle) {} }
        return try body()
    }

    /// Hold a shared lock on an existing artifact inode until the returned handle is released.
    func lockSharedExisting() throws -> FileLockHandle {
        guard let descriptor = try openExisting() else {
            throw POSIXFileLockError(operation: "open", path: path, errorNumber: ENOENT)
        }
        do {
            try applyLock(descriptor: descriptor, operation: LOCK_SH)
            return FileLockHandle(descriptor: descriptor)
        } catch {
            close(descriptor)
            throw error
        }
    }

    /// Try to lock an existing artifact without waiting for another process's active lease.
    func tryLockExclusiveExisting() throws -> FileLockAttempt {
        guard let descriptor = try openExisting() else {
            return .missing
        }

        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let errorNumber = errno
            if errorNumber == EINTR {
                continue
            }
            if errorNumber == EWOULDBLOCK {
                close(descriptor)
                return .busy
            }
            close(descriptor)
            throw POSIXFileLockError(operation: "lock", path: path, errorNumber: errorNumber)
        }
        return .acquired(FileLockHandle(descriptor: descriptor))
    }

    private func lockCreatingFile(operation: Int32) throws -> FileLockHandle {
        let descriptor: Int32
        while true {
            let candidate = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            if candidate >= 0 {
                descriptor = candidate
                break
            }
            let errorNumber = errno
            if errorNumber != EINTR {
                throw POSIXFileLockError(operation: "open", path: path, errorNumber: errorNumber)
            }
        }

        do {
            try applyLock(descriptor: descriptor, operation: operation)
            return FileLockHandle(descriptor: descriptor)
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func openExisting() throws -> Int32? {
        while true {
            let descriptor = open(path, O_RDONLY)
            if descriptor >= 0 {
                return descriptor
            }
            let errorNumber = errno
            if errorNumber == EINTR {
                continue
            }
            if errorNumber == ENOENT {
                return nil
            }
            throw POSIXFileLockError(operation: "open", path: path, errorNumber: errorNumber)
        }
    }

    private func applyLock(descriptor: Int32, operation: Int32) throws {
        while flock(descriptor, operation) != 0 {
            let errorNumber = errno
            if errorNumber != EINTR {
                throw POSIXFileLockError(operation: "lock", path: path, errorNumber: errorNumber)
            }
        }
    }
}

enum FileLockAttempt {
    case acquired(FileLockHandle)
    case busy
    case missing
}

/// Lifetime token for an advisory lock held on one stable inode.
final class FileLockHandle: @unchecked Sendable {
    private let descriptor: Int32

    fileprivate init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
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
