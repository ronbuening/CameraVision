import XCTest
@testable import AISidecarCore

final class AssetAffinityScorerTests: XCTestCase {
    func testProfileDecayAndScoreBandsAreDeterministic() {
        let profile = AssetAffinityProfile.resolved(name: .conservative, minAffinityForConsensus: nil)

        XCTAssertEqual(CaptureTimeAffinityScorer.score(deltaSeconds: 120, profile: profile) ?? 0, 0.5, accuracy: 0.000001)
        XCTAssertEqual(CaptureTimeAffinityScorer.score(deltaSeconds: 1_801, profile: profile), 0)
        XCTAssertEqual(GPSAffinityScorer.score(distanceMeters: 25, profile: profile) ?? 0, 0.5, accuracy: 0.000001)
        XCTAssertEqual(AffinityScoreFormatter.rounded(0.1234567), 0.123457)
        XCTAssertEqual(AffinityScoreFormatter.band(for: 0.75), "very_strong")
        XCTAssertEqual(AffinityScoreFormatter.band(for: 0.35), "moderate")
        XCTAssertEqual(AffinityScoreFormatter.band(for: 0.149999), "ignored")
    }

    func testFilenameSequenceAndFileListAdjacencyUseFilenameDecay() {
        let profile = AssetAffinityProfile.resolved(name: .conservative, minAffinityForConsensus: nil)
        let first = affinityInputs(assetID: "asset-000001", relativePath: "seq/IMG_0001.JPG")
        let sixth = affinityInputs(assetID: "asset-000002", relativePath: "seq/IMG_0006.JPG")
        let filename = FilenameSequenceAffinityScorer.score(lhs: first, rhs: sixth, profile: profile)

        XCTAssertEqual(filename.basis, "filename_sequence")
        XCTAssertEqual(filename.score ?? 0, 0.5, accuracy: 0.000001)

        var listA = affinityInputs(assetID: "asset-000003", relativePath: "a/Bird.JPG")
        var listB = affinityInputs(assetID: "asset-000004", relativePath: "b/Other.JPG")
        listA.fileListIndex = 0
        listB.fileListIndex = 2
        let list = FilenameSequenceAffinityScorer.score(lhs: listA, rhs: listB, profile: profile)

        XCTAssertEqual(list.basis, "explicit_file_list_adjacency")
        XCTAssertGreaterThan(list.score ?? 0, 0.75)
    }

    func testGraphStoresFilenameEdgesButBlocksGearOnlyAffinity() {
        var closeConfig = ResolvedNormalizationConfiguration.builtInDefaults
        closeConfig.normalizationMode = .batchConservative
        closeConfig.affinityMode = .metadataWeighted
        let profile = AssetAffinityProfile.resolved(
            name: closeConfig.affinityProfile,
            minAffinityForConsensus: closeConfig.minAffinityForConsensus
        )
        let closeGraph = AssetAffinityGraphBuilder().build(
            input: inputBatch([
                asset("asset-000001", "seq/IMG_0001.JPG"),
                asset("asset-000002", "seq/IMG_0002.JPG")
            ]),
            profile: profile,
            mode: .metadataWeighted
        )

        XCTAssertEqual(closeGraph.edges.count, 1)
        XCTAssertEqual(closeGraph.edges[0].affinity, 0.7)
        XCTAssertEqual(closeGraph.edges[0].components.basisSignals, ["filename_sequence"])
        XCTAssertFalse(closeGraph.edges[0].components.gearOnly)

        let gearOnlyGraph = AssetAffinityGraphBuilder().build(
            input: inputBatch([
                asset("asset-000001", "A.JPG", camera: "nikon-z8", lens: "500pf"),
                asset("asset-000002", "B.JPG", camera: "nikon-z8", lens: "500pf")
            ]),
            profile: profile,
            mode: .metadataWeighted
        )
        XCTAssertTrue(gearOnlyGraph.edges.isEmpty)
    }

    func testLargeBatchCandidateGenerationUsesBoundedDeterministicWindows() {
        let profile = AssetAffinityProfile.resolved(name: .conservative, minAffinityForConsensus: nil)
        let nodes = (0..<505).map { index in
            ScoringNode(
                node: NormalizationAffinityNodeRecord(
                    nodeID: String(format: "group-%06d", index + 1),
                    groupID: String(format: "group-%06d", index + 1),
                    memberAssetIDs: [String(format: "asset-%06d", index + 1)]
                ),
                inputs: affinityInputs(
                    assetID: String(format: "asset-%06d", index + 1),
                    relativePath: String(format: "seq/IMG_%04d.JPG", index + 1)
                )
            )
        }

        let pairs = CandidateNeighborGenerator().candidatePairs(nodes: nodes, profile: profile)

        XCTAssertFalse(pairs.isEmpty)
        XCTAssertLessThan(pairs.count, 505 * 504 / 2)
        XCTAssertEqual(pairs.first?.0.node.nodeID, "group-000001")
        XCTAssertEqual(pairs.first?.1.node.nodeID, "group-000002")
    }

    private func inputBatch(_ assets: [NormalizationSourceAsset]) -> NormalizationResolvedInputBatch {
        NormalizationResolvedInputBatch(
            workflow: .fileList,
            inputPath: "/list.txt",
            inputBasePath: "/",
            scanRoot: "/",
            sourceAssets: assets,
            sourceAISidecars: [],
            sameBaseNameGroups: assets.enumerated().map { index, asset in
                NormalizationSourceGroup(
                    groupID: String(format: "group-%06d", index + 1),
                    groupDirectory: asset.affinityInputs.relativeDirectory,
                    groupBasename: asset.affinityInputs.filenameStem,
                    targetRelativePath: "\(asset.affinityInputs.filenameStem).xmp",
                    memberAssetIDs: [asset.assetID],
                    selectedAssetIDs: [asset.assetID],
                    skippedAssetIDs: []
                )
            },
            warnings: [],
            failures: []
        )
    }

    private func asset(
        _ assetID: String,
        _ relativePath: String,
        camera: String? = nil,
        lens: String? = nil
    ) -> NormalizationSourceAsset {
        let source = makeSource(
            fileName: URL(fileURLWithPath: relativePath).lastPathComponent,
            relativePath: relativePath,
            path: "/photos/\(relativePath)"
        )
        var inputs = AssetAffinityInputBuilder.make(assetID: assetID, source: source)
        inputs.sameBaseNameGroupID = assetID.replacingOccurrences(of: "asset", with: "group")
        inputs.cameraIdentityClass = camera
        inputs.lensIdentityClass = lens
        return NormalizationSourceAsset(
            assetID: assetID,
            sourcePath: source.path,
            sourceRelativePath: source.relativePath,
            fileName: source.fileName,
            sourceType: source.detectedType,
            sourceIdentity: source.identity,
            sourceSidecarPath: nil,
            sourceSidecarRelativePath: nil,
            sourceIdentityStatus: nil,
            fileListIndex: nil,
            affinityInputs: inputs
        )
    }

    private func affinityInputs(assetID: String, relativePath: String) -> AssetAffinityInputs {
        AssetAffinityInputBuilder.make(
            assetID: assetID,
            source: makeSource(
                fileName: URL(fileURLWithPath: relativePath).lastPathComponent,
                relativePath: relativePath,
                path: "/photos/\(relativePath)"
            )
        )
    }
}
