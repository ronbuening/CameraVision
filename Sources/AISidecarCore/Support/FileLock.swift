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
        while true {
            let descriptor = try openCreating()
            do {
                try applyLock(descriptor: descriptor, operation: operation)
            } catch {
                close(descriptor)
                throw error
            }
            // Revalidate that the locked descriptor still names `path`: if an
            // external actor unlinked or replaced the lock file between open
            // and flock, a waiter would otherwise hold a lock on an orphaned
            // inode while a newcomer locks the replacement, splitting the
            // mutex. (A holder whose inode is unlinked mid-critical-section
            // remains unprotected — advisory path locks cannot detect that.)
            if isCurrentInode(descriptor: descriptor) {
                return FileLockHandle(descriptor: descriptor)
            }
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
    }

    private func openCreating() throws -> Int32 {
        while true {
            let descriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            if descriptor >= 0 {
                return descriptor
            }
            let errorNumber = errno
            if errorNumber != EINTR {
                throw POSIXFileLockError(operation: "open", path: path, errorNumber: errorNumber)
            }
        }
    }

    private func isCurrentInode(descriptor: Int32) -> Bool {
        var descriptorInfo = Darwin.stat()
        var pathInfo = Darwin.stat()
        guard fstat(descriptor, &descriptorInfo) == 0, stat(path, &pathInfo) == 0 else {
            return false
        }
        return descriptorInfo.st_dev == pathInfo.st_dev && descriptorInfo.st_ino == pathInfo.st_ino
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
