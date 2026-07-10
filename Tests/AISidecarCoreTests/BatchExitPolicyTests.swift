import XCTest

@testable import AISidecarCore

final class BatchExitPolicyTests: XCTestCase {
    func testSuccessExitsZero() {
        XCTAssertNil(BatchExitPolicy.exitStatus(failureCount: 0, interrupted: false))
    }

    func testAnyFailureExitsOne() {
        XCTAssertEqual(BatchExitPolicy.exitStatus(failureCount: 1, interrupted: false), 1)
    }

    func testInterruptionWinsOverFailures() {
        XCTAssertEqual(BatchExitPolicy.exitStatus(failureCount: 3, interrupted: true), 130)
        XCTAssertEqual(BatchExitPolicy.exitStatus(failureCount: 0, interrupted: true), 130)
    }
}
