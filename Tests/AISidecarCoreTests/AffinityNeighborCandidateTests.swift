import XCTest
@testable import AISidecarCore

final class AffinityNeighborCandidateTests: XCTestCase {
    func testSmallBatchesUseDeterministicAllPairs() {
        let profile = AssetAffinityProfile.resolved(name: .conservative, minAffinityForConsensus: nil)
        let nodes = (1...4).map {
            scoringNode(index: $0, relativePath: String(format: "seq/IMG_%04d.JPG", $0))
        }

        let pairs = CandidateNeighborGenerator().candidatePairs(nodes: nodes, profile: profile)

        XCTAssertEqual(pairs.count, 6)
        XCTAssertEqual(pairs[0].0.node.nodeID, "group-000001")
        XCTAssertEqual(pairs[0].1.node.nodeID, "group-000002")
        XCTAssertEqual(pairs[5].0.node.nodeID, "group-000003")
        XCTAssertEqual(pairs[5].1.node.nodeID, "group-000004")
    }

    func testLargeBatchesUseBoundedDeterministicFilenameAndListWindows() {
        let profile = AssetAffinityProfile.resolved(name: .conservative, minAffinityForConsensus: nil)
        let nodes = (1...501).map {
            scoringNode(
                index: $0,
                relativePath: String(format: "seq/IMG_%04d.JPG", $0),
                fileListIndex: $0 - 1
            )
        }

        let firstRun = CandidateNeighborGenerator().candidatePairs(nodes: nodes, profile: profile)
        let secondRun = CandidateNeighborGenerator().candidatePairs(nodes: nodes.reversed(), profile: profile)

        XCTAssertEqual(firstRun.map(pairKey), secondRun.map(pairKey))
        XCTAssertFalse(firstRun.isEmpty)
        XCTAssertLessThan(firstRun.count, 501 * 500 / 2)
        XCTAssertTrue(firstRun.map(pairKey).contains("group-000001->group-000002"))
        XCTAssertFalse(firstRun.map(pairKey).contains("group-000001->group-000501"))
    }

    private func scoringNode(
        index: Int,
        relativePath: String,
        fileListIndex: Int? = nil
    ) -> ScoringNode {
        let asset = phase3Asset(index: index, relativePath: relativePath, fileListIndex: fileListIndex)
        return ScoringNode(
            node: NormalizationAffinityNodeRecord(
                nodeID: String(format: "group-%06d", index),
                groupID: String(format: "group-%06d", index),
                memberAssetIDs: [asset.assetID]
            ),
            inputs: asset.affinityInputs
        )
    }

    private func pairKey(_ pair: (ScoringNode, ScoringNode)) -> String {
        "\(pair.0.node.nodeID)->\(pair.1.node.nodeID)"
    }
}
