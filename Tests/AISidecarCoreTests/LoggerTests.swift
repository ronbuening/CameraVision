import XCTest
@testable import AISidecarCore

final class LoggerTests: XCTestCase {
    func testTextLogIsHumanReadable() throws {
        let record = sampleRecord()
        let line = try Logger.render(record, format: .text)

        XCTAssertTrue(line.contains("INFO analyze.complete: Finished image"))
        XCTAssertTrue(line.contains("source_path=/photos/a.nef"))
        XCTAssertTrue(line.contains("sidecar_path=/photos/a.nef.ai.json"))
        XCTAssertTrue(line.contains("status=ok"))
        XCTAssertTrue(line.contains("errors=E_RENDER_FAILED"))
    }

    func testJSONLogIsSingleLineWithStableFieldNames() throws {
        let record = sampleRecord()
        let line = try Logger.render(record, format: .json)

        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.contains("\"source_path\""))
        XCTAssertTrue(line.contains("\"sidecar_path\""))
        XCTAssertTrue(line.contains("\"errors\""))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LogRecord.self, from: Data(line.utf8))

        XCTAssertEqual(decoded.level, .info)
        XCTAssertEqual(decoded.event, "analyze.complete")
        XCTAssertEqual(decoded.message, "Finished image")
        XCTAssertEqual(decoded.sourcePath, "/photos/a.nef")
        XCTAssertEqual(decoded.sidecarPath, "/photos/a.nef.ai.json")
        XCTAssertEqual(decoded.status, "ok")
        XCTAssertEqual(decoded.errors.first?.code, .renderFailed)
    }

    private func sampleRecord() -> LogRecord {
        LogRecord(
            timestamp: Date(timeIntervalSince1970: 0),
            level: .info,
            event: "analyze.complete",
            message: "Finished image",
            sourcePath: "/photos/a.nef",
            sidecarPath: "/photos/a.nef.ai.json",
            status: "ok",
            errors: [
                SidecarError(
                    code: .renderFailed,
                    stage: .render,
                    message: "Render failed",
                    recoverable: true
                )
            ]
        )
    }
}
