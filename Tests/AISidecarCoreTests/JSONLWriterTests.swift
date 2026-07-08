import XCTest
@testable import AISidecarCore

/// R1-3: append I/O failures surface as SidecarError instead of process crashes.
final class JSONLWriterTests: XCTestCase {
    func testAppendAfterCloseThrowsWriteFailedInsteadOfCrashing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jsonl-writer-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("progress.jsonl").path

        let writer = try JSONLWriter<ProgressRecord>(path: path, label: "progress log")
        try writer.close()

        let record = ProgressRecord(
            sourcePath: "/photos/A.NEF",
            relativePath: "A.NEF",
            sidecarPath: "/out/A.NEF.ai.json",
            status: .written,
            durationMs: 1
        )
        XCTAssertThrowsError(try writer.append(record)) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .writeFailed)
            XCTAssertTrue((error as? SidecarError)?.message.contains("progress log") ?? false)
        }
    }
}
