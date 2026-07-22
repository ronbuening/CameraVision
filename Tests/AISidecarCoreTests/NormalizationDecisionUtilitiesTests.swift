import XCTest

@testable import AISidecarCore

final class NormalizationDecisionUtilitiesTests: XCTestCase {
    func testAssignDecisionIDsOverwritesExistingIDsWithoutChangingOrder() {
        var decisions = [
            PerAssetNormalizationDecision(decisionID: "old-beta", assetID: "asset-beta"),
            PerAssetNormalizationDecision(decisionID: "old-alpha", assetID: "asset-alpha"),
        ]

        assignDecisionIDs(&decisions)

        XCTAssertEqual(decisions.map(\.decisionID), ["decision-000001", "decision-000002"])
        XCTAssertEqual(decisions.map(\.assetID), ["asset-beta", "asset-alpha"])
    }
}
