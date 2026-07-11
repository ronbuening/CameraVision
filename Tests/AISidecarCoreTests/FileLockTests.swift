import Foundation
import XCTest
@testable import AISidecarCore

final class FileLockTests: XCTestCase {
    func testExclusiveLockSerializesTwoHandles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aisidecar-file-lock-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let path = root.appendingPathComponent("shared.lock").path
        let firstEntered = expectation(description: "first lock entered")
        let allowFirstToExit = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "FileLockTests", attributes: .concurrent)

        queue.async {
            try? FileLock(path: path).withExclusiveLock {
                firstEntered.fulfill()
                allowFirstToExit.wait()
            }
        }
        wait(for: [firstEntered], timeout: 1)

        queue.async {
            _ = try? FileLock(path: path).withExclusiveLock {
                secondEntered.signal()
            }
        }
        XCTAssertEqual(secondEntered.wait(timeout: .now() + 0.1), .timedOut)

        allowFirstToExit.signal()
        XCTAssertEqual(secondEntered.wait(timeout: .now() + 1), .success)
    }
}
