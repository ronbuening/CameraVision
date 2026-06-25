import XCTest
@testable import AISidecarCore

final class GlobalBackstopConsensusTests: XCTestCase {
    func testGlobalBackstopRequiresMinimumEligibleAndSupportingAssets() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(decisions: [
                phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Scene|Outdoor", flatKeyword: "Outdoor"),
                phase3DirectDecision(assetID: "asset-000002", canonicalPath: "Scene|Outdoor", flatKeyword: "Outdoor"),
                phase3DirectDecision(assetID: "asset-000003", canonicalPath: "Scene|Outdoor", flatKeyword: "Outdoor"),
                phase3DirectDecision(assetID: "asset-000004", canonicalPath: "Scene|Outdoor", flatKeyword: "Outdoor")
            ]),
            input: phase3InputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG",
                "seq/IMG_0003.JPG",
                "seq/IMG_0004.JPG",
                "seq/IMG_0005.JPG"
            ]),
            configuration: phase3Configuration()
        )

        let propagated = result.perAssetDecisions.filter { $0.stage == .globalBackstopPropagation }
        XCTAssertEqual(propagated.map(\.assetID), ["asset-000005"])
        XCTAssertEqual(propagated.map(\.canonicalPath), ["Scene|Outdoor"])
        XCTAssertEqual(propagated.first?.supportingAssetIDs, [
            "asset-000001",
            "asset-000002",
            "asset-000003",
            "asset-000004"
        ])
        XCTAssertEqual(propagated.first?.governingRule, "global_backstop_broad")
    }

    func testTinyBatchCannotSatisfyGlobalBackstopByPercentageAlone() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(decisions: [
                phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Scene|Outdoor", flatKeyword: "Outdoor"),
                phase3DirectDecision(assetID: "asset-000002", canonicalPath: "Scene|Outdoor", flatKeyword: "Outdoor"),
                phase3DirectDecision(assetID: "asset-000003", canonicalPath: "Scene|Outdoor", flatKeyword: "Outdoor")
            ]),
            input: phase3InputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG",
                "seq/IMG_0003.JPG",
                "seq/IMG_0004.JPG"
            ]),
            configuration: phase3Configuration()
        )

        XCTAssertFalse(result.perAssetDecisions.contains { $0.stage == .globalBackstopPropagation })
    }

    func testGlobalBackstopDoesNotPropagateLocalOnlyOrMidSpecificEntries() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(decisions: [
                phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Behavior|Flying"),
                phase3DirectDecision(assetID: "asset-000002", canonicalPath: "Behavior|Flying"),
                phase3DirectDecision(assetID: "asset-000003", canonicalPath: "Behavior|Flying"),
                phase3DirectDecision(assetID: "asset-000004", canonicalPath: "Behavior|Flying")
            ]),
            input: phase3InputBatch([
                "far/A.JPG",
                "far/B.JPG",
                "far/C.JPG",
                "far/D.JPG",
                "far/E.JPG"
            ]),
            configuration: phase3Configuration(affinityMode: .off)
        )

        XCTAssertFalse(result.perAssetDecisions.contains { $0.stage == .globalBackstopPropagation })
    }
}
