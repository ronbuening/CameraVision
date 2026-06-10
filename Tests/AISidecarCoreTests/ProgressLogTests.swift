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

    func testBatchSummaryDerivesCountsAndInterruptionError() {
        let scanResult = ScanResult(
            inputPath: "/photos",
            scanRoot: "/photos",
            recursive: true,
            identityPolicy: .sha256,
            images: [
                makeSource(fileName: "A.NEF", relativePath: "A.NEF"),
                makeSource(fileName: "B.NEF", relativePath: "B.NEF")
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
            )
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
}
