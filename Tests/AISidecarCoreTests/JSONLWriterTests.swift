import XCTest

@testable import AISidecarCore

/// R1-3: append I/O failures surface as SidecarError instead of process crashes.
final class JSONLWriterTests: XCTestCase {
    func testSynchronizesEveryTwentyFiveRecordsAndPendingRecordsOnClose() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jsonl-writer-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("progress.jsonl").path
        let syncCounter = ThreadSafeCounter()
        let writer = try JSONLWriter<ProgressRecord>(
            path: path,
            label: "progress log",
            synchronizationObserver: { syncCounter.increment() }
        )

        for index in 0..<24 {
            try writer.append(makeRecord(index: index))
        }
        XCTAssertEqual(syncCounter.value, 0)

        try writer.append(makeRecord(index: 24))
        XCTAssertEqual(syncCounter.value, 1)

        try writer.append(makeRecord(index: 25))
        try writer.close()
        XCTAssertEqual(syncCounter.value, 2)
    }

    func testFlushSynchronizesPendingRecordsWithoutClosingWriter() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jsonl-writer-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("progress.jsonl").path
        let syncCounter = ThreadSafeCounter()
        let writer = try JSONLWriter<ProgressRecord>(
            path: path,
            label: "progress log",
            synchronizationObserver: { syncCounter.increment() }
        )

        try writer.append(makeRecord(index: 0))
        try writer.flush()
        try writer.flush()
        XCTAssertEqual(syncCounter.value, 1)

        try writer.append(makeRecord(index: 1))
        try writer.close()
        XCTAssertEqual(syncCounter.value, 2)
    }

    func testInterruptionCallbackFlushesPendingRecords() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jsonl-writer-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("progress.jsonl").path
        let syncCounter = ThreadSafeCounter()
        let writer = try JSONLWriter<ProgressRecord>(
            path: path,
            label: "progress log",
            synchronizationObserver: { syncCounter.increment() }
        )
        let monitor = InterruptionMonitor()
        let registration = monitor.onInterruption {
            try? writer.flush()
        }

        try writer.append(makeRecord(index: 0))
        monitor.requestInterruption()

        XCTAssertEqual(syncCounter.value, 1)
        registration.cancel()
        try writer.close()
        XCTAssertEqual(syncCounter.value, 1)
    }

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

    private func makeRecord(index: Int) -> ProgressRecord {
        ProgressRecord(
            timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
            sourcePath: "/photos/\(index).NEF",
            relativePath: "\(index).NEF",
            sidecarPath: "/out/\(index).NEF.ai.json",
            status: .written,
            durationMs: index
        )
    }
}

private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
