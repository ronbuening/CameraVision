import Foundation
import XCTest
@testable import AISidecarCore

final class ArtifactCleanupTests: XCTestCase {
    func testDryRunPlansOwnedArtifactsWithoutRemovingProtectedFiles() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let removable = [
            "Bird.JPG.ai.json",
            "batch-progress-2026-06-16T120000Z.jsonl",
            "batch-summary-2026-06-16T120000Z.json",
            "xmp-export-progress-2026-06-16T120000Z.jsonl",
            "xmp-export-report-2026-06-16T120000Z.json",
            "xmp-export-summary-2026-06-16T120000Z.md",
            "normalization-progress-2026-06-16T120000Z.jsonl",
            "normalization-report-2026-06-16T120000Z.json",
            "normalization-summary-2026-06-16T120000Z.md",
            "normalization-apply-progress-2026-06-16T120000Z.jsonl",
            "normalization-apply-report-2026-06-16T120000Z.json",
            "normalization-apply-summary-2026-06-16T120000Z.md"
        ]
        let protected = [
            "Bird.JPG",
            "Bird.xmp",
            "Bird.JPG.aisidecar.whole_image.jpg",
            "derivative-cache-index.json",
            "\(String(repeating: "a", count: 64))-render-v2-gemma4-26b-default-whole_image.jpg",
            "model-input-export-2026-06-16T120000Z.json",
            "normalization-session-2026-06-16T120000Z.json",
            "notes.json",
            ".Hidden.JPG.ai.json"
        ]
        try (removable + protected).forEach { try write("artifact", named: $0, in: root) }

        let report = try ArtifactCleanup().run(rootPath: root.path, recursive: false, dryRun: true)

        XCTAssertEqual(report.schemaVersion, CleanupReport.currentSchemaVersion)
        XCTAssertEqual(report.rootPath, root.path)
        XCTAssertFalse(report.recursive)
        XCTAssertTrue(report.dryRun)
        XCTAssertEqual(report.plannedCount, removable.count)
        XCTAssertEqual(report.removedCount, 0)
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertEqual(Set(report.artifacts.map(\.relativePath)), Set(removable))
        XCTAssertTrue(report.artifacts.allSatisfy { !$0.removed && $0.error == nil })
        for name in removable + protected {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path), name)
        }
    }

    func testCleanupRemovesOwnedArtifactsAndHonorsRecursiveFlag() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let topLevel = "Bird.JPG.ai.json"
        let nested = "nested/Nested.JPG.ai.json"
        try write("top", named: topLevel, in: root)
        try write("nested", named: nested, in: root)

        let nonRecursive = try ArtifactCleanup().run(rootPath: root.path, recursive: false, dryRun: false)

        XCTAssertEqual(nonRecursive.plannedCount, 1)
        XCTAssertEqual(nonRecursive.removedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(topLevel).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(nested).path))

        let recursive = try ArtifactCleanup().run(rootPath: root.path, recursive: true, dryRun: false)

        XCTAssertEqual(recursive.plannedCount, 1)
        XCTAssertEqual(recursive.removedCount, 1)
        XCTAssertTrue(recursive.recursive)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(nested).path))
    }

    private func write(_ contents: String, named relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
}
