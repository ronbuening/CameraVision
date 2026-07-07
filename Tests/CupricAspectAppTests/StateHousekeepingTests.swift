import XCTest
@testable import CupricAspectApp

/// M8: artifact pruning removes only stale entries in the artifact
/// subdirectories — never the recovery file or anything else.
final class StateHousekeepingTests: XCTestCase {
    private var stateDir: URL!

    override func setUpWithError() throws {
        stateDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("housekeeping-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: stateDir)
    }

    private func makeEntry(_ subdirectory: String, _ name: String, ageDays: Double) throws -> URL {
        let directory = stateDir.appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory.appendingPathComponent("session.json"))
        let modified = Date().addingTimeInterval(-ageDays * 86_400)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: directory.path)
        return directory
    }

    func testPruneRemovesOnlyStaleArtifactEntries() throws {
        let stale = try makeEntry("normalize-artifacts", "old-run", ageDays: 9)
        let fresh = try makeEntry("normalize-artifacts", "new-run", ageDays: 1)
        let staleExport = try makeEntry("export-sessions", "old-export", ageDays: 30)

        // Recovery file lives outside the artifact subdirectories: untouchable.
        let recoveryDir = stateDir.appendingPathComponent("recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
        let recovery = recoveryDir.appendingPathComponent("review-recovery.json")
        try Data("r".utf8).write(to: recovery)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-30 * 86_400)],
            ofItemAtPath: recoveryDir.path
        )

        let removed = StateHousekeeping.pruneArtifacts(in: stateDir)

        XCTAssertEqual(removed, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleExport.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.path), "recovery is never pruned")
    }

    func testPruneOnEmptyStateDirectoryIsHarmless() {
        XCTAssertEqual(StateHousekeeping.pruneArtifacts(in: stateDir), 0)
    }
}
