import XCTest

@testable import AISidecarCore

final class LocalWeightedConsensusTests: XCTestCase {
    func testBroadLocalConsensusRecordsSupportMassAgreementAndSupportingNeighbors() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(decisions: [
                phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Subject|Wildlife|Birds"),
                phase3DirectDecision(assetID: "asset-000002", canonicalPath: "Subject|Wildlife|Birds"),
            ]),
            input: phase3InputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG",
                "seq/IMG_0003.JPG",
            ]),
            configuration: phase3Configuration()
        )

        let consensus = try XCTUnwrap(
            result.localConsensus.first {
                $0.targetAssetID == "asset-000003" && $0.canonicalPath == "Subject|Wildlife|Birds"
            })
        XCTAssertEqual(consensus.localWeightedAgreement, 1)
        XCTAssertEqual(consensus.supportMass, 1.4)
        XCTAssertEqual(consensus.eligibleMass, 1.4)
        XCTAssertEqual(consensus.supportingNeighborCount, 2)
        XCTAssertTrue(consensus.decisionEligible)
        XCTAssertTrue(consensus.blockReasons.isEmpty)
        XCTAssertTrue(
            result.perAssetDecisions.contains {
                $0.assetID == "asset-000003"
                    && $0.stage == .localAffinityPropagation
                    && $0.canonicalPath == "Subject|Wildlife|Birds"
            })
    }

    func testMidSpecificLocalConsensusRequiresTwoSupportingNeighbors() throws {
        let oneNeighbor = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(decisions: [
                phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Behavior|Flying")
            ]),
            input: phase3InputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG",
            ]),
            configuration: phase3Configuration()
        )
        let blocked = try XCTUnwrap(
            oneNeighbor.localConsensus.first {
                $0.targetAssetID == "asset-000002" && $0.canonicalPath == "Behavior|Flying"
            })
        XCTAssertFalse(blocked.decisionEligible)
        XCTAssertTrue(blocked.blockReasons.contains(.lowSupportingNeighborCount))

        let twoNeighbors = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(decisions: [
                phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Behavior|Flying"),
                phase3DirectDecision(assetID: "asset-000002", canonicalPath: "Behavior|Flying"),
            ]),
            input: phase3InputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG",
                "seq/IMG_0003.JPG",
            ]),
            configuration: phase3Configuration()
        )
        let eligible = try XCTUnwrap(
            twoNeighbors.localConsensus.first {
                $0.targetAssetID == "asset-000003" && $0.canonicalPath == "Behavior|Flying"
            })
        XCTAssertTrue(eligible.decisionEligible)
        XCTAssertEqual(eligible.supportingNeighborCount, 2)
        XCTAssertTrue(
            twoNeighbors.perAssetDecisions.contains {
                $0.assetID == "asset-000003"
                    && $0.stage == .localAffinityPropagation
                    && $0.canonicalPath == "Behavior|Flying"
            })
    }
}
