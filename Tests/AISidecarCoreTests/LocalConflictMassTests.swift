import XCTest

@testable import AISidecarCore

final class LocalConflictMassTests: XCTestCase {
    func testDirectTargetConflictBlocksNeighborPropagation() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(decisions: [
                phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Subject|Wildlife"),
                phase3DirectDecision(assetID: "asset-000002", canonicalPath: "Subject|Mammals"),
            ]),
            input: closeGearInput(),
            configuration: phase3Configuration()
        )

        let consensus = try XCTUnwrap(
            result.localConsensus.first {
                $0.targetAssetID == "asset-000002" && $0.canonicalPath == "Subject|Wildlife"
            })
        XCTAssertFalse(consensus.decisionEligible)
        XCTAssertTrue(consensus.blockReasons.contains(.blockedDirectConflict))
        XCTAssertFalse(
            result.perAssetDecisions.contains {
                $0.assetID == "asset-000002"
                    && $0.stage == .localAffinityPropagation
                    && $0.canonicalPath == "Subject|Wildlife"
            })
    }

    func testNeighborhoodConflictMassBlocksPropagationAndRecordsConflictingPaths() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(decisions: [
                phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Subject|Wildlife"),
                phase3DirectDecision(assetID: "asset-000002", canonicalPath: "Subject|Mammals"),
            ]),
            input: closeGearInput(),
            configuration: phase3Configuration()
        )

        let consensus = try XCTUnwrap(
            result.localConsensus.first {
                $0.targetAssetID == "asset-000003" && $0.canonicalPath == "Subject|Wildlife"
            })
        XCTAssertFalse(consensus.decisionEligible)
        XCTAssertGreaterThanOrEqual(consensus.conflictSupportMass, 0.75)
        XCTAssertGreaterThanOrEqual(consensus.conflictWeightedAgreement ?? 0, 0.35)
        XCTAssertEqual(consensus.conflictingCanonicalPaths, ["Subject|Mammals"])
        XCTAssertTrue(consensus.blockReasons.contains(.blockedLocalConflictMass))
        XCTAssertFalse(
            result.perAssetDecisions.contains {
                $0.assetID == "asset-000003"
                    && $0.stage == .localAffinityPropagation
                    && $0.canonicalPath == "Subject|Wildlife"
            })
    }

    private func closeGearInput() -> NormalizationResolvedInputBatch {
        phase3InputBatch(assets: [
            phase3Asset(index: 1, relativePath: "seq/IMG_0001.JPG", camera: "nikon-z8", lens: "500pf"),
            phase3Asset(index: 2, relativePath: "seq/IMG_0002.JPG", camera: "nikon-z8", lens: "500pf"),
            phase3Asset(index: 3, relativePath: "seq/IMG_0003.JPG", camera: "nikon-z8", lens: "500pf"),
        ])
    }
}
