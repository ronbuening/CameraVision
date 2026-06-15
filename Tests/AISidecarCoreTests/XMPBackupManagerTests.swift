import Foundation
import XCTest
@testable import AISidecarCore

final class XMPBackupManagerTests: XCTestCase {
    func testCreatesDeterministicBackupAndRestoresIt() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Bird.xmp")
        try "original".write(to: target, atomically: true, encoding: .utf8)
        let manager = XMPBackupManager(
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        )

        let backup = try manager.backupExistingSidecar(at: target.path)
        try "changed".write(to: target, atomically: true, encoding: .utf8)
        let restored = try manager.restore(backup)

        XCTAssertEqual(backup.backupPath, root.appendingPathComponent("Bird.xmp.bak-2027-01-15T08:00:00Z").path)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: backup.backupPath), encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original")
        XCTAssertNotNil(restored.restoredAt)
    }

    func testMissingBackupRestoreFailsClosed() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let manager = XMPBackupManager()

        XCTAssertThrowsError(try manager.restore(XMPBackupRecord(
            targetXMPPath: root.appendingPathComponent("Bird.xmp").path,
            backupPath: root.appendingPathComponent("Missing.xmp.bak-2027-01-15T08:00:00Z").path,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .sourceMissing)
        }
    }

    private func fixedDateProvider(_ date: Date) -> @Sendable () -> Date {
        { date }
    }
}
