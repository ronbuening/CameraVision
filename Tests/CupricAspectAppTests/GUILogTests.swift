import AISidecarCore
import XCTest
@testable import CupricAspectApp

/// B0-4 (FR4-059, AC4-035): the shared file sink persists structured pipeline
/// log lines under the state directory and stays size-bounded via rotation.
final class GUILogTests: XCTestCase {
    private final class MoveFailingFileManager: FileManager, @unchecked Sendable {
        private(set) var moveAttempts = 0

        override func moveItem(at srcURL: URL, to dstURL: URL) throws {
            moveAttempts += 1
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("guilog-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoggerWritesStructuredErrorLinesToFile() throws {
        let sink = FileLogSink(directory: directory)
        let logger = sink.makeLogger()
        try logger.log(LogRecord(
            level: .error,
            event: "analyze.failed",
            message: "model response invalid",
            errors: [SidecarError(
                code: .modelSchemaViolation,
                stage: .model,
                message: "schema violation",
                recoverable: true
            )]
        ))
        let contents = try String(contentsOf: sink.logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("analyze.failed"))
        XCTAssertTrue(contents.contains("E_MODEL_SCHEMA_VIOLATION"), "structured code must be readable")
    }

    func testRotationBoundsTheLogAndKeepsOneGeneration() throws {
        let sink = FileLogSink(directory: directory, sizeCapBytes: 200)
        for index in 0..<20 {
            sink.write("line \(index) with some padding to cross the cap sooner")
        }
        let currentSize = try FileManager.default
            .attributesOfItem(atPath: sink.logURL.path)[.size] as? Int ?? 0
        XCTAssertLessThanOrEqual(currentSize, 200 + 64, "current log stays near the cap")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sink.previousLogURL.path),
            "one rotated generation is kept"
        )
        // Newest line is always in the current file.
        let contents = try String(contentsOf: sink.logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("line 19"))
    }

    func testUpdateSizeCapAppliesFromTheNextWrite() throws {
        let sink = FileLogSink(directory: directory, sizeCapBytes: 1_000_000)
        for index in 0..<10 {
            sink.write("pre-cap-change line \(index)")
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sink.previousLogURL.path),
            "nothing rotates under the generous initial cap"
        )
        sink.updateSizeCap(bytes: 100_000)
        // The oversized-current check is per write: pad past the new cap.
        let padding = String(repeating: "x", count: 100_000)
        sink.write(padding)
        sink.write("post-rotation line")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sink.previousLogURL.path))
        let contents = try String(contentsOf: sink.logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("post-rotation line"))
        XCTAssertFalse(contents.contains("pre-cap-change line 0"), "old lines rotated out")
    }

    func testFailedRotationKeepsSizeAccountingAndRetries() throws {
        let fileManager = MoveFailingFileManager()
        let sink = FileLogSink(directory: directory, sizeCapBytes: 100, fileManager: fileManager)

        sink.write(String(repeating: "a", count: 80))
        sink.write(String(repeating: "b", count: 30))
        XCTAssertEqual(fileManager.moveAttempts, 1)
        let oversized = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: sink.logURL.path)[.size] as? Int
        )
        XCTAssertGreaterThan(oversized, 100)

        sink.write("c")

        XCTAssertEqual(fileManager.moveAttempts, 2, "failed rotation must be retried on the next write")
        let contents = try String(contentsOf: sink.logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains(String(repeating: "a", count: 80)))
        XCTAssertTrue(contents.contains(String(repeating: "b", count: 30)))
        XCTAssertTrue(contents.contains("c"))
    }

    func testStoredSizeCapReadsPreferenceWithDefaultFallback() throws {
        let suiteName = "guilog-cap-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertEqual(GUILog.storedSizeCapMB(defaults: defaults), GUILog.defaultSizeCapMB)
        defaults.set(25, forKey: PreferenceKeys.logSizeCapMB)
        XCTAssertEqual(GUILog.storedSizeCapMB(defaults: defaults), 25)
    }

    func testMinimumLevelFiltersBelowThreshold() throws {
        let sink = FileLogSink(directory: directory)
        let logger = sink.makeLogger(minimumLevel: .warn)
        try logger.log(LogRecord(level: .debug, event: "noise", message: "dropped"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sink.logURL.path))
        try logger.log(LogRecord(level: .error, event: "kept", message: "written"))
        let contents = try String(contentsOf: sink.logURL, encoding: .utf8)
        XCTAssertFalse(contents.contains("noise"))
        XCTAssertTrue(contents.contains("kept"))
    }
}
