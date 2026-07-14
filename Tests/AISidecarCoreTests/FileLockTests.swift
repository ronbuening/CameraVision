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

    func testSharedArtifactLeaseBlocksExclusiveDeletionLockUntilReleased() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aisidecar-file-lock-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let artifact = root.appendingPathComponent("artifact.jpg")
        try Data("artifact".utf8).write(to: artifact)
        var shared: FileLockHandle? = try FileLock(path: artifact.path).lockSharedExisting()

        if case .busy = try FileLock(path: artifact.path).tryLockExclusiveExisting() {
            // Expected while the shared lease is alive.
        } else {
            XCTFail("Expected an active shared artifact lease to block exclusive eviction.")
        }

        shared = nil

        guard case .acquired(let exclusive) = try FileLock(path: artifact.path).tryLockExclusiveExisting() else {
            return XCTFail("Expected exclusive eviction lock after releasing the shared lease.")
        }
        withExtendedLifetime(exclusive) {}
        XCTAssertNil(shared)
    }

    func testClosingOneSharedHandleKeepsTheOtherLeaseActive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aisidecar-file-lock-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let artifact = root.appendingPathComponent("artifact.jpg")
        try Data("artifact".utf8).write(to: artifact)
        var first: FileLockHandle? = try FileLock(path: artifact.path).lockSharedExisting()
        var second: FileLockHandle? = try FileLock(path: artifact.path).lockSharedExisting()

        second = nil

        if case .busy = try FileLock(path: artifact.path).tryLockExclusiveExisting() {
            // The first independently-opened lease still protects the inode.
        } else {
            XCTFail("Expected the remaining shared handle to keep eviction blocked.")
        }

        first = nil
        guard case .acquired(let exclusive) = try FileLock(path: artifact.path).tryLockExclusiveExisting() else {
            return XCTFail("Expected exclusive lock after both shared handles closed.")
        }
        withExtendedLifetime(exclusive) {}
        XCTAssertNil(first)
        XCTAssertNil(second)
    }
}
