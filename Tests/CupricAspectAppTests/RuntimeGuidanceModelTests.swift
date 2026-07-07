import AISidecarCore
import XCTest
@testable import CupricAspectApp

/// B0-3 (FR4-058, AC4-034): the launch-time runtime check derives the three
/// guidance states from the tag listing without a live Ollama.
@MainActor
final class RuntimeGuidanceModelTests: XCTestCase {
    private func waitForSettled(_ model: RuntimeGuidanceModel, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while model.status == .checking || model.status == .unknown {
            guard Date() < deadline else { return XCTFail("timed out waiting for check") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testUnreachableEndpointYieldsUnreachableGuidance() async throws {
        let model = RuntimeGuidanceModel(configPath: "/nonexistent/wi-test-config.json", listVisionTags: { _ in
            throw SidecarError(
                code: .modelEndpointUnreachable,
                stage: .model,
                message: "connection refused",
                recoverable: true
            )
        })
        model.check(environment: [:])
        try await waitForSettled(model)
        XCTAssertEqual(model.status, .unreachable(message: "connection refused"))
        XCTAssertTrue(model.needsAttention)
    }

    func testEmptyVisionListNamesStarterPullCommand() async throws {
        let model = RuntimeGuidanceModel(configPath: "/nonexistent/wi-test-config.json", listVisionTags: { _ in [] })
        model.check(environment: [:])
        try await waitForSettled(model)
        XCTAssertEqual(model.status, .noVisionModels)
        XCTAssertTrue(model.needsAttention)
        // The starter suggestion is the resolved configured tag, never blank.
        XCTAssertFalse(model.configuredModel.isEmpty)
        XCTAssertEqual(model.pullCommand, "ollama pull \(model.configuredModel)")
    }

    func testInstalledVisionModelsNeedNoAttention() async throws {
        let model = RuntimeGuidanceModel(configPath: "/nonexistent/wi-test-config.json", listVisionTags: { _ in ["gemma4:26b-a4b-it-qat"] })
        model.check(environment: [:])
        try await waitForSettled(model)
        XCTAssertEqual(model.status, .ready(visionTagCount: 1))
        XCTAssertFalse(model.needsAttention)
    }
}
