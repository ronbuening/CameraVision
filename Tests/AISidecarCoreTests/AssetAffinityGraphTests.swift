import XCTest
@testable import AISidecarCore

final class AssetAffinityGraphTests: XCTestCase {
    func testSameBaseNameMembersCollapseToOneAffinityNode() {
        var raw = phase3Asset(index: 1, relativePath: "Bird.NEF", sameBaseNameGroupID: "group-000001")
        var jpeg = phase3Asset(index: 2, relativePath: "Bird.JPG", sameBaseNameGroupID: "group-000001")
        let other = phase3Asset(index: 3, relativePath: "Other.JPG", sameBaseNameGroupID: "group-000002")
        raw.affinityInputs.sameBaseNameGroupID = "group-000001"
        jpeg.affinityInputs.sameBaseNameGroupID = "group-000001"
        let groups = [
            phase3Group(index: 1, assets: [raw, jpeg]),
            phase3Group(index: 2, assets: [other])
        ]

        let graph = AssetAffinityGraphBuilder().build(
            input: phase3InputBatch(assets: [raw, jpeg, other], groups: groups),
            profile: AssetAffinityProfile.resolved(name: .conservative, minAffinityForConsensus: nil),
            mode: .metadataWeighted
        )

        XCTAssertEqual(graph.nodes.count, 2)
        XCTAssertEqual(graph.nodes[0].memberAssetIDs, ["asset-000001", "asset-000002"])
        XCTAssertEqual(graph.nodeIDByAssetID["asset-000001"], "group-000001")
        XCTAssertEqual(graph.nodeIDByAssetID["asset-000002"], "group-000001")
    }

    func testGraphStoresOnlyThresholdPassingEdgesWithDeterministicGearBoostedScores() throws {
        var profile = AssetAffinityProfile.resolved(name: .conservative, minAffinityForConsensus: nil)
        profile.minAffinityToStoreEdge = 0.71
        let assets = [
            phase3Asset(index: 1, relativePath: "seq/IMG_0001.JPG", camera: "nikon-z8", lens: "500pf"),
            phase3Asset(index: 2, relativePath: "seq/IMG_0002.JPG", camera: "nikon-z8", lens: "500pf"),
            phase3Asset(index: 3, relativePath: "seq/IMG_0100.JPG")
        ]
        let input = phase3InputBatch(assets: assets)

        let first = AssetAffinityGraphBuilder().build(input: input, profile: profile, mode: .metadataWeighted)
        let second = AssetAffinityGraphBuilder().build(input: input, profile: profile, mode: .metadataWeighted)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.edges.count, 1)
        let edge = try XCTUnwrap(first.edges.first)
        XCTAssertEqual(edge.fromNodeID, "group-000001")
        XCTAssertEqual(edge.toNodeID, "group-000002")
        XCTAssertGreaterThan(edge.affinity, 0.7)
        XCTAssertEqual(edge.components.basisSignals, ["filename_sequence"])
        XCTAssertGreaterThan(edge.components.gearScore, 0)
        XCTAssertFalse(edge.components.gearOnly)
    }
}
