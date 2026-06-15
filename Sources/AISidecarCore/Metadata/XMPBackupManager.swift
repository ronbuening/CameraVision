import Foundation

/// Backup created before modifying an existing XMP sidecar.
public struct XMPBackupRecord: Codable, Sendable, Equatable {
    public var targetXMPPath: String
    public var backupPath: String
    public var createdAt: Date
    public var restoredAt: Date?

    enum CodingKeys: String, CodingKey {
        case targetXMPPath = "target_xmp_path"
        case backupPath = "backup_path"
        case createdAt = "created_at"
        case restoredAt = "restored_at"
    }

    public init(targetXMPPath: String, backupPath: String, createdAt: Date, restoredAt: Date? = nil) {
        self.targetXMPPath = targetXMPPath
        self.backupPath = backupPath
        self.createdAt = createdAt
        self.restoredAt = restoredAt
    }
}

/// Creates and restores deterministic XMP sidecar backups for Phase 2 writes.
public struct XMPBackupManager {
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    public init(fileManager: FileManager = .default, now: @escaping @Sendable () -> Date = Date.init) {
        self.fileManager = fileManager
        self.now = now
    }

    /// Copy the target sidecar to `<name>.xmp.bak-<ISO-8601-timestamp>`.
    public func backupExistingSidecar(at targetXMPPath: String) throws -> XMPBackupRecord {
        let targetURL = URL(fileURLWithPath: targetXMPPath).standardizedFileURL
        guard fileManager.fileExists(atPath: targetURL.path) else {
            throw SidecarError(
                code: .sourceMissing,
                stage: .write,
                message: "Cannot back up missing XMP sidecar: \(targetURL.path)",
                recoverable: true
            )
        }

        let createdAt = now()
        let backupURL = targetURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(targetURL.lastPathComponent).bak-\(timestampString(for: createdAt))")
            .standardizedFileURL

        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                throw SidecarError(
                    code: .sidecarExists,
                    stage: .write,
                    message: "XMP backup already exists: \(backupURL.path)",
                    recoverable: true
                )
            }
            try fileManager.copyItem(at: targetURL, to: backupURL)
            return XMPBackupRecord(targetXMPPath: targetURL.path, backupPath: backupURL.path, createdAt: createdAt)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to back up \(targetURL.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    /// Restore the backup over the target using the same sibling-temp atomic write contract as sidecars.
    public func restore(_ record: XMPBackupRecord) throws -> XMPBackupRecord {
        let targetURL = URL(fileURLWithPath: record.targetXMPPath).standardizedFileURL
        let backupURL = URL(fileURLWithPath: record.backupPath).standardizedFileURL
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw SidecarError(
                code: .sourceMissing,
                stage: .write,
                message: "Cannot restore missing XMP backup: \(backupURL.path)",
                recoverable: true
            )
        }

        do {
            try AtomicFileWriter.writeFile(to: targetURL, fileManager: fileManager) { temporaryURL in
                try fileManager.copyItem(at: backupURL, to: temporaryURL)
            }
            var restored = record
            restored.restoredAt = now()
            return restored
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to restore XMP backup \(backupURL.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func timestampString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
