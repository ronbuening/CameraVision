import Foundation
import XCTest
@testable import AISidecarCore

final class BatchConsensusEngineTests: XCTestCase {
    func testLocalConsensusPropagatesBroadAncestorThroughHighAffinityNeighbors() throws {
        let vocabulary = try loadedVocabulary()
        let canonicalization = CandidateCanonicalizationResult(
            sessionContext: [],
            observations: [],
            skips: [],
            batchCandidates: [],
            perAssetDecisions: [
                directDecision(assetID: "asset-000001", canonicalPath: "Subject|Wildlife|Birds"),
                directDecision(assetID: "asset-000002", canonicalPath: "Subject|Wildlife|Birds")
            ]
        )

        let result = BatchConsensusEngine(vocabulary: vocabulary).apply(
            canonicalization: canonicalization,
            input: inputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG",
                "seq/IMG_0003.JPG"
            ]),
            configuration: batchConfiguration()
        )

        let propagated = try XCTUnwrap(result.perAssetDecisions.first {
            $0.assetID == "asset-000003" && $0.stage == .localAffinityPropagation
        })
        XCTAssertEqual(propagated.canonicalPath, "Subject|Wildlife")
        XCTAssertEqual(propagated.flatKeyword, "Wildlife")
        XCTAssertEqual(propagated.supportingAssetIDs, ["asset-000001", "asset-000002"])
        XCTAssertEqual(propagated.localConsensus?.decisionEligible, true)
        XCTAssertEqual(propagated.localConsensus?.supportingNeighborCount, 2)
        XCTAssertEqual(result.affinity.edges.count, 3)

        let wildlifeSummary = try XCTUnwrap(result.batchCandidates.first {
            $0.canonicalPath == "Subject|Wildlife"
        })
        XCTAssertEqual(wildlifeSummary.directAssetSupportCount, 3)
        XCTAssertEqual(wildlifeSummary.eligibleAssetCount, 3)
        XCTAssertEqual(wildlifeSummary.agreementFrequency, 1)
    }

    func testLowAffinityAndDirectConflictsBlockLocalPropagation() throws {
        let vocabulary = try loadedVocabulary()
        let lowAffinity = BatchConsensusEngine(vocabulary: vocabulary).apply(
            canonicalization: CandidateCanonicalizationResult(
                sessionContext: [],
                observations: [],
                skips: [],
                batchCandidates: [],
                perAssetDecisions: [
                    directDecision(assetID: "asset-000001", canonicalPath: "Subject|Wildlife|Birds")
                ]
            ),
            input: inputBatch([
                "seq/IMG_0001.JPG",
                "seq/Other.JPG"
            ]),
            configuration: batchConfiguration()
        )
        XCTAssertFalse(lowAffinity.perAssetDecisions.contains { $0.stage == .localAffinityPropagation })

        let conflict = BatchConsensusEngine(vocabulary: vocabulary).apply(
            canonicalization: CandidateCanonicalizationResult(
                sessionContext: [],
                observations: [],
                skips: [],
                batchCandidates: [],
                perAssetDecisions: [
                    directDecision(assetID: "asset-000001", canonicalPath: "Subject|Wildlife|Birds"),
                    directDecision(assetID: "asset-000002", canonicalPath: "Subject|Mammals")
                ]
            ),
            input: inputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG"
            ]),
            configuration: batchConfiguration()
        )

        XCTAssertFalse(conflict.perAssetDecisions.contains {
            $0.assetID == "asset-000002" && $0.stage == .localAffinityPropagation
        })
        XCTAssertTrue(conflict.localConsensus.contains {
            $0.targetAssetID == "asset-000002"
                && $0.canonicalPath == "Subject|Wildlife"
                && $0.blockReasons.contains(.blockedDirectConflict)
        })
    }

    func testRequiresReviewEntriesDoNotPropagateFromModelEvidence() throws {
        let vocabulary = try loadedVocabulary()
        let result = BatchConsensusEngine(vocabulary: vocabulary).apply(
            canonicalization: CandidateCanonicalizationResult(
                sessionContext: [],
                observations: [],
                skips: [],
                batchCandidates: [],
                perAssetDecisions: [
                    directDecision(assetID: "asset-000001", canonicalPath: "Subject|Review")
                ]
            ),
            input: inputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG"
            ]),
            configuration: batchConfiguration()
        )

        XCTAssertFalse(result.perAssetDecisions.contains {
            $0.assetID == "asset-000002" && $0.canonicalPath == "Subject|Review"
        })
    }

    func testSessionContextRequiresExplicitPropagationFlagAndRecordsUserEvidence() throws {
        let vocabulary = try loadedVocabulary()
        var context = NormalizationSessionContextRecord(
            contextType: .subject,
            originalText: "Wildlife",
            foldedText: "wildlife",
            matchedCanonicalPath: "Subject|Wildlife",
            unknownPolicyResult: "matched",
            directApplyPolicy: .allow,
            propagationAllowed: false,
            exportResult: "propagation_not_allowed"
        )
        let blocked = BatchConsensusEngine(vocabulary: vocabulary).apply(
            canonicalization: CandidateCanonicalizationResult(
                sessionContext: [context],
                observations: [],
                skips: [],
                batchCandidates: [],
                perAssetDecisions: []
            ),
            input: inputBatch(["seq/IMG_0001.JPG"]),
            configuration: batchConfiguration()
        )
        XCTAssertFalse(blocked.perAssetDecisions.contains { $0.stage == .userSessionContext })

        context.propagationAllowed = true
        let allowed = BatchConsensusEngine(vocabulary: vocabulary).apply(
            canonicalization: CandidateCanonicalizationResult(
                sessionContext: [context],
                observations: [],
                skips: [],
                batchCandidates: [],
                perAssetDecisions: []
            ),
            input: inputBatch(["seq/IMG_0001.JPG"]),
            configuration: batchConfiguration()
        )
        let decision = try XCTUnwrap(allowed.perAssetDecisions.first { $0.stage == .userSessionContext })
        XCTAssertEqual(decision.canonicalPath, "Subject|Wildlife")
        XCTAssertEqual(decision.contextType, .subject)
        XCTAssertEqual(decision.governingRule, "user_session_context_subject")
        XCTAssertEqual(allowed.sessionContext.first?.exportResult, "applied")
    }

    func testGlobalBackstopRequiresMinimumEligibleAndSupportingAssets() throws {
        let vocabulary = try loadedVocabulary()
        let direct = [
            directDecision(assetID: "asset-000001", canonicalPath: "Scene|Outdoor"),
            directDecision(assetID: "asset-000002", canonicalPath: "Scene|Outdoor"),
            directDecision(assetID: "asset-000003", canonicalPath: "Scene|Outdoor"),
            directDecision(assetID: "asset-000004", canonicalPath: "Scene|Outdoor")
        ]
        let result = BatchConsensusEngine(vocabulary: vocabulary).apply(
            canonicalization: CandidateCanonicalizationResult(
                sessionContext: [],
                observations: [],
                skips: [],
                batchCandidates: [],
                perAssetDecisions: direct
            ),
            input: inputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG",
                "seq/IMG_0003.JPG",
                "seq/IMG_0004.JPG",
                "seq/IMG_0005.JPG"
            ]),
            configuration: batchConfiguration()
        )

        let global = result.perAssetDecisions.filter { $0.stage == .globalBackstopPropagation }
        XCTAssertEqual(global.map(\.assetID), ["asset-000005"])
        XCTAssertTrue(global.allSatisfy { $0.canonicalPath == "Scene|Outdoor" })
    }

    func testObservedTagsModeAllowsLocalPropagationButSuppressesGlobalBackstop() throws {
        let vocabulary = try observedVocabulary()
        var configuration = batchConfiguration()
        configuration.vocabularyMode = .observedTags
        let localResult = BatchConsensusEngine(vocabulary: vocabulary).apply(
            canonicalization: CandidateCanonicalizationResult(
                sessionContext: [],
                observations: [],
                skips: [],
                batchCandidates: [],
                perAssetDecisions: [
                    observedDirectDecision(assetID: "asset-000001", canonicalPath: "Great Blue Heron"),
                    observedDirectDecision(assetID: "asset-000002", canonicalPath: "Great Blue Heron")
                ]
            ),
            input: inputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG",
                "seq/IMG_0003.JPG"
            ]),
            configuration: configuration
        )

        let local = try XCTUnwrap(localResult.perAssetDecisions.first {
            $0.assetID == "asset-000003"
                && $0.stage == .localAffinityPropagation
                && $0.canonicalPath == "Great Blue Heron"
        })
        XCTAssertEqual(local.candidateKind, .observedModelTag)
        XCTAssertEqual(local.flatKeyword, "Great Blue Heron")
        XCTAssertNil(local.hierarchicalKeyword)
        XCTAssertNil(local.namespace)

        let globalBackstopCandidate = [
            observedDirectDecision(assetID: "asset-000001", canonicalPath: "Great Blue Heron"),
            observedDirectDecision(assetID: "asset-000002", canonicalPath: "Great Blue Heron"),
            observedDirectDecision(assetID: "asset-000001", canonicalPath: "Outdoor"),
            observedDirectDecision(assetID: "asset-000002", canonicalPath: "Outdoor"),
            observedDirectDecision(assetID: "asset-000003", canonicalPath: "Outdoor"),
            observedDirectDecision(assetID: "asset-000004", canonicalPath: "Outdoor")
        ]
        let globalResult = BatchConsensusEngine(vocabulary: vocabulary).apply(
            canonicalization: CandidateCanonicalizationResult(
                sessionContext: [],
                observations: [],
                skips: [],
                batchCandidates: [],
                perAssetDecisions: globalBackstopCandidate
            ),
            input: inputBatch([
                "seq/IMG_0001.JPG",
                "seq/IMG_0002.JPG",
                "seq/IMG_0003.JPG",
                "seq/IMG_0004.JPG",
                "seq/IMG_0005.JPG"
            ]),
            configuration: configuration
        )

        XCTAssertFalse(globalResult.perAssetDecisions.contains { $0.stage == .globalBackstopPropagation })
    }

    private func loadedVocabulary() throws -> LoadedVocabulary {
        try VocabularyLoader.load(data: vocabularyData(entries: [
            VocabularyEntry(
                canonicalPath: "Subject",
                flatKeyword: "Subject",
                namespace: .subject,
                parentPath: nil,
                synonyms: [],
                requiresReview: false,
                autoApplyAllowed: false,
                directApplyPolicy: .withhold,
                propagationScope: PropagationScope.none,
                specificity: .broad
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Wildlife",
                flatKeyword: "Wildlife",
                namespace: .subject,
                parentPath: "Subject",
                synonyms: ["wildlife"],
                requiresReview: false,
                autoApplyAllowed: true,
                directApplyPolicy: .allow,
                mutuallyExclusiveGroup: "subject-kind",
                propagationScope: .local,
                specificity: .broad
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Wildlife|Birds",
                flatKeyword: "Birds",
                namespace: .subject,
                parentPath: "Subject|Wildlife",
                synonyms: ["bird"],
                requiresReview: false,
                autoApplyAllowed: false,
                directApplyPolicy: .allow,
                propagationScope: PropagationScope.none,
                specificity: .mid
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Mammals",
                flatKeyword: "Mammals",
                namespace: .subject,
                parentPath: "Subject",
                synonyms: ["mammal"],
                requiresReview: false,
                autoApplyAllowed: true,
                directApplyPolicy: .allow,
                mutuallyExclusiveGroup: "subject-kind",
                propagationScope: .local,
                specificity: .broad
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Review",
                flatKeyword: "Review",
                namespace: .subject,
                parentPath: "Subject",
                synonyms: [],
                requiresReview: true,
                autoApplyAllowed: false,
                directApplyPolicy: .allow,
                propagationScope: .local,
                specificity: .broad
            ),
            VocabularyEntry(
                canonicalPath: "Scene",
                flatKeyword: "Scene",
                namespace: .scene,
                parentPath: nil,
                synonyms: [],
                requiresReview: false,
                autoApplyAllowed: false,
                directApplyPolicy: .withhold,
                propagationScope: PropagationScope.none,
                specificity: .broad
            ),
            VocabularyEntry(
                canonicalPath: "Scene|Outdoor",
                flatKeyword: "Outdoor",
                namespace: .scene,
                parentPath: "Scene",
                synonyms: ["outdoor"],
                requiresReview: false,
                autoApplyAllowed: true,
                directApplyPolicy: .allow,
                propagationScope: .global,
                specificity: .broad
            )
        ]), sourcePath: "memory://batch-consensus.json")
    }

    private func observedVocabulary() throws -> LoadedVocabulary {
        try VocabularyLoader.load(data: vocabularyData(entries: [
            VocabularyEntry(
                canonicalPath: "Great Blue Heron",
                flatKeyword: "Great Blue Heron",
                namespace: .workflow,
                parentPath: nil,
                synonyms: [],
                requiresReview: false,
                autoApplyAllowed: true,
                directApplyPolicy: .flatOnly,
                mutuallyExclusiveGroup: nil,
                exportFlatKeyword: true,
                exportHierarchicalKeyword: false,
                propagationScope: .local,
                specificity: .broad
            ),
            VocabularyEntry(
                canonicalPath: "Outdoor",
                flatKeyword: "Outdoor",
                namespace: .workflow,
                parentPath: nil,
                synonyms: [],
                requiresReview: false,
                autoApplyAllowed: true,
                directApplyPolicy: .flatOnly,
                mutuallyExclusiveGroup: nil,
                exportFlatKeyword: true,
                exportHierarchicalKeyword: false,
                propagationScope: .global,
                specificity: .broad
            )
        ]), sourcePath: "memory://observed-tags.json")
    }

    private func batchConfiguration() -> ResolvedNormalizationConfiguration {
        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .controlledVocabulary
        configuration.normalizationMode = .batchConservative
        configuration.affinityMode = .metadataWeighted
        configuration.affinityProfile = .conservative
        configuration.minAffinityForConsensus = 0.35
        return configuration
    }

    private func directDecision(assetID: String, canonicalPath: String) -> PerAssetNormalizationDecision {
        PerAssetNormalizationDecision(
            assetID: assetID,
            stage: .directModelObservation,
            status: .accepted,
            candidateKind: .canonicalVocabulary,
            canonicalPath: canonicalPath,
            flatKeyword: canonicalPath.split(separator: "|").last.map(String.init),
            hierarchicalKeyword: canonicalPath,
            directApplyPolicy: .allow,
            requiresReview: false,
            exportFlatKeyword: true,
            exportHierarchicalKeyword: true,
            supportUnits: 1,
            supportingAssetIDs: [assetID],
            observationCount: 1
        )
    }

    private func observedDirectDecision(assetID: String, canonicalPath: String) -> PerAssetNormalizationDecision {
        PerAssetNormalizationDecision(
            assetID: assetID,
            stage: .directModelObservation,
            status: .accepted,
            candidateKind: .observedModelTag,
            canonicalPath: canonicalPath,
            flatKeyword: canonicalPath,
            hierarchicalKeyword: nil,
            namespace: nil,
            directApplyPolicy: .flatOnly,
            requiresReview: false,
            exportFlatKeyword: true,
            exportHierarchicalKeyword: false,
            supportUnits: 1,
            supportingAssetIDs: [assetID],
            observationCount: 1,
            skipReasons: [.directApplyFlatOnly]
        )
    }

    private func inputBatch(_ relativePaths: [String]) -> NormalizationResolvedInputBatch {
        let assets = relativePaths.enumerated().map { index, relativePath in
            asset(String(format: "asset-%06d", index + 1), relativePath)
        }
        return NormalizationResolvedInputBatch(
            workflow: .fromJSON,
            inputPath: "/sidecars",
            inputBasePath: "/sidecars",
            scanRoot: "/sidecars",
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

    private func asset(_ assetID: String, _ relativePath: String) -> NormalizationSourceAsset {
        let source = makeSource(
            fileName: URL(fileURLWithPath: relativePath).lastPathComponent,
            relativePath: relativePath,
            path: "/photos/\(relativePath)"
        )
        var inputs = AssetAffinityInputBuilder.make(assetID: assetID, source: source)
        inputs.sameBaseNameGroupID = assetID.replacingOccurrences(of: "asset", with: "group")
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
}
