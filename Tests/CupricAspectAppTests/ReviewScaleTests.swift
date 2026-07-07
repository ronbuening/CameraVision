import AISidecarCore
import XCTest
@testable import CupricAspectApp

/// B0-6 review-scale sanity: build the M4 review over a 1,500-image synthetic
/// session and bound the hot paths the UI hits per frame. Skipped by default
/// (offline suite stays fast); run with:
///
///   CUPRIC_SCALE_TESTS=1 CUPRIC_SCALE_DIR=<full-sidecar fixture dir> \
///     swift test --filter ReviewScaleTests
///
/// where the fixture dir comes from
/// `Scripts/generate-synthetic-fixture.swift <dir> 1500 --sidecar-template
/// Tests/CupricAspectAppTests/Fixtures/sample-analyzed.ai.json`.
@MainActor
final class ReviewScaleTests: XCTestCase {
    func testFifteenHundredAssetSessionBuildsAndRendersWithoutStalls() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["CUPRIC_SCALE_TESTS"] == "1", "scale check is opt-in")
        let root = try XCTUnwrap(environment["CUPRIC_SCALE_DIR"], "set CUPRIC_SCALE_DIR")

        let state = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("review-scale-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: state) }

        let review = ReviewModel(stateDirectory: state)
        let buildStart = Date()
        review.buildSession(jsonRoot: root, sourceRoot: root)
        let deadline = Date().addingTimeInterval(120)
        while review.building || (review.session == nil && review.buildError == nil) {
            guard Date() < deadline else { return XCTFail("session build timed out") }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(review.buildError)
        let buildSeconds = Date().timeIntervalSince(buildStart)

        let rowsStart = Date()
        let rows = review.assetRows
        let rowsSeconds = Date().timeIntervalSince(rowsStart)
        XCTAssertEqual(rows.count, 1500)

        // The UI reads assetRows on every body evaluation; a per-frame budget
        // needs it well under 100 ms at this scale.
        print("SCALE: session build \(String(format: "%.2f", buildSeconds))s, assetRows \(String(format: "%.0f", rowsSeconds * 1000))ms for \(rows.count) rows")
        XCTAssertLessThan(rowsSeconds, 0.1, "assetRows recompute must stay frame-budget friendly")

        // Verdict churn (approve-all on one asset) must not degrade at scale.
        let verdictStart = Date()
        if let first = rows.first {
            review.acceptAll(assetID: first.assetID)
        }
        let verdictSeconds = Date().timeIntervalSince(verdictStart)
        XCTAssertLessThan(verdictSeconds, 0.1, "single-asset verdict update must be O(asset), not O(session)")
    }
}
