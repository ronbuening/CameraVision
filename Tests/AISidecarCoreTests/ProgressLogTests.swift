import XCTest

@testable import AISidecarCore

final class ProgressLogTests: XCTestCase {
    func testProgressLogAppendsOneJSONObjectPerLine() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("batch-progress-2026-06-10T120000Z.jsonl")
        let log = try ProgressLog(path: path.path)

        try log.append(
            ProgressRecord(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                sourcePath: "/photos/A.NEF",
                relativePath: "A.NEF",
                sidecarPath: "/out/A.NEF.ai.json",
                status: .written,
                durationMs: 12
            )
        )
        try log.append(
            ProgressRecord(
                timestamp: Date(timeIntervalSince1970: 1_700_000_001),
                sourcePath: "/photos/B.NEF",
                relativePath: "B.NEF",
                sidecarPath: "/out/B.NEF.ai.json",
                status: .skippedExisting,
                durationMs: 3
            )
        )
        try log.close()

        let lines = String(decoding: try Data(contentsOf: path), as: UTF8.self)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let first = try decoder.decode(ProgressRecord.self, from: Data(lines[0].utf8))
        let second = try decoder.decode(ProgressRecord.self, from: Data(lines[1].utf8))
        XCTAssertEqual(first.status, .written)
        XCTAssertEqual(second.status, .skippedExisting)
        XCTAssertEqual(first.sidecarPath, "/out/A.NEF.ai.json")
    }

    func testProgressRecordElidesWriteMsWhenAbsentAndRoundTripsWhenPresent() throws {
        let encoder = JSONCoding.jsonlEncoder()
        let base = ProgressRecord(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sourcePath: "/photos/A.NEF",
            relativePath: "A.NEF",
            sidecarPath: "/out/A.NEF.ai.json",
            status: .written,
            durationMs: 12
        )
        let withoutWriteMs = String(decoding: try encoder.encode(base), as: UTF8.self)
        XCTAssertFalse(
            withoutWriteMs.contains("write_ms"),
            "Absent write_ms must be elided so pre-existing record bytes are unchanged"
        )

        var measured = base
        measured.writeMs = 4
        let data = try encoder.encode(measured)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"write_ms\":4"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(ProgressRecord.self, from: data).writeMs, 4)
        XCTAssertNil(
            try decoder.decode(ProgressRecord.self, from: Data(withoutWriteMs.utf8)).writeMs)
    }

    func testBatchSummaryDerivesCountsAndInterruptionError() {
        let scanResult = ScanResult(
            inputPath: "/photos",
            scanRoot: "/photos",
            recursive: true,
            identityPolicy: .sha256,
            images: [
                makeSource(fileName: "A.NEF", relativePath: "A.NEF"),
                makeSource(fileName: "B.NEF", relativePath: "B.NEF"),
            ],
            errors: []
        )
        let records = [
            ProgressRecord(
                sourcePath: "/photos/A.NEF",
                relativePath: "A.NEF",
                sidecarPath: "/out/A.NEF.ai.json",
                status: .written,
                durationMs: 1
            ),
            ProgressRecord(
                sourcePath: "/photos/B.NEF",
                relativePath: "B.NEF",
                sidecarPath: "/out/B.NEF.ai.json",
                status: .failed,
                errors: [
                    SidecarError(
                        code: .sidecarExists,
                        stage: .write,
                        message: "exists",
                        recoverable: true
                    )
                ],
                durationMs: 1
            ),
        ]

        let summary = BatchSummary.derive(
            from: scanResult,
            records: records,
            outputDir: "/out",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            interrupted: true
        )

        XCTAssertEqual(summary.schemaVersion, "ai-sidecar-batch-summary/1.0")
        XCTAssertEqual(summary.totalImages, 2)
        XCTAssertEqual(summary.written, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.dryRun, 0)
        XCTAssertEqual(summary.errors.map(\.code), [.sidecarExists, .interrupted])
    }

    func testBatchSummaryWriterPreservesExactWrappedFailureMessage() {
        let path = "/reports/batch-summary.json"
        let writer = BatchSummaryWriter(dataWriter: { _, _, _ in throw InjectedReportWriteError() })
        let summary = BatchSummary(
            inputPath: "/photos",
            scanRoot: "/photos",
            recursive: true,
            outputDir: nil,
            totalImages: 0,
            written: 0,
            skipped: 0,
            failed: 0,
            dryRun: 0,
            errors: []
        )

        XCTAssertThrowsError(try writer.write(summary, to: path)) { error in
            XCTAssertEqual(
                (error as? SidecarError)?.message,
                "Unable to encode batch summary /reports/batch-summary.json: injected report write failure"
            )
        }
    }
}

private struct InjectedReportWriteError: LocalizedError {
    var errorDescription: String? { "injected report write failure" }
}
