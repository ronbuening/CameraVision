import Foundation
import XCTest
@testable import AISidecarCore

final class CandidateCanonicalizerTests: XCTestCase {
    func testSynonymsCollapseToCanonicalCasingWithUnitSupportAndRoleProvenance() throws {
        let vocabulary = try loadedVocabulary()
        let extraction = try extractionResult(responses: [
            (.wholeImage, response([
                .mainSubjects: .array([
                    candidate("bird", confidence: "high")
                ])
            ])),
            (.subjectIsolated, response([
                .proposedKeywords: .array([
                    candidate("avian", confidence: "medium")
                ])
            ]))
        ])
        var configuration = normalizationConfiguration()
        configuration.normalizationMode = .singleImage

        let result = try CandidateCanonicalizer(vocabulary: vocabulary).canonicalize(
            extractionResults: [extraction],
            input: inputBatch(),
            configuration: configuration
        )

        XCTAssertEqual(result.observations.map(\.provenance.inputRole), [.wholeImage, .subjectIsolated])
        XCTAssertEqual(result.perAssetDecisions.count, 1)
        let decision = try XCTUnwrap(result.perAssetDecisions.first)
        XCTAssertEqual(decision.canonicalPath, "Subject|Wildlife|Birds")
        XCTAssertEqual(decision.flatKeyword, "Birds")
        XCTAssertEqual(decision.hierarchicalKeyword, "Subject|Wildlife|Birds")
        XCTAssertEqual(decision.supportUnits, 1)
        XCTAssertEqual(decision.observationCount, 2)
        XCTAssertEqual(decision.observations.map(\.term), ["bird", "avian"])
        XCTAssertEqual(result.skips.map(\.reason), [.duplicate])
        XCTAssertEqual(result.skips.first?.canonicalPath, "Subject|Wildlife|Birds")
        XCTAssertEqual(result.batchCandidates.first?.directAssetSupportCount, 1)
        XCTAssertEqual(result.batchCandidates.first?.confidenceBands, ["high": 1, "medium": 1])
    }

    func testSeparatorInsensitiveVocabularyMatchCanonicalizesModelStyleTerms() throws {
        let vocabulary = try loadedVocabulary(entries: [
            subjectRoot(),
            VocabularyEntry(
                canonicalPath: "Subject|Still Life",
                flatKeyword: "Still Life",
                namespace: .subject,
                parentPath: "Subject",
                synonyms: ["bird photography"],
                requiresReview: false,
                directApplyPolicy: .allow
            )
        ])
        let extraction = try extractionResult(responses: [
            (.wholeImage, response([
                .genreOrPhotographyType: .array([
                    candidate("bird_photography", confidence: "high")
                ]),
                .proposedKeywords: .array([
                    candidate("still-life", confidence: "high")
                ])
            ]))
        ])

        let result = try CandidateCanonicalizer(vocabulary: vocabulary).canonicalize(
            extractionResults: [extraction],
            input: inputBatch(),
            configuration: normalizationConfiguration()
        )

        let decision = try XCTUnwrap(result.perAssetDecisions.first)
        XCTAssertEqual(decision.canonicalPath, "Subject|Still Life")
        XCTAssertEqual(decision.flatKeyword, "Still Life")
        XCTAssertEqual(decision.observations.map(\.term), ["bird_photography", "still-life"])
        XCTAssertEqual(result.skips.map(\.reason), [.duplicate])
    }

    func testConfidenceFilteringPipeRejectionGPSGuardAndUnmatchedVocabulary() throws {
        let vocabulary = try loadedVocabulary()
        let extraction = try extractionResult(responses: [
            (.wholeImage, response([
                .proposedKeywords: .array([
                    candidate("bird", confidence: "low"),
                    candidate("Subject|Wildlife|Birds", confidence: "high"),
                    candidate("unknown subject", confidence: "high"),
                    candidate("45.1, -122.7", confidence: "high")
                ])
            ]))
        ])
        var configuration = normalizationConfiguration()
        configuration.minConfidence = .medium

        let result = try CandidateCanonicalizer(vocabulary: vocabulary).canonicalize(
            extractionResults: [extraction],
            input: inputBatch(),
            configuration: configuration
        )

        XCTAssertTrue(result.perAssetDecisions.isEmpty)
        XCTAssertEqual(result.skips.map(\.reason), [
            .belowConfidenceThreshold,
            .containsHierarchySeparator,
            .unmatchedVocabulary,
            .coordinateLikeTerm
        ])
        XCTAssertEqual(result.skips.compactMap(\.term), [
            "bird",
            "Subject|Wildlife|Birds",
            "unknown subject",
            "45.1, -122.7"
        ])
    }

    func testOffModeUsesPhase2FallbackWithoutVocabularyMapping() throws {
        let vocabulary = try loadedVocabulary()
        let extraction = try extractionResult(responses: [
            (.wholeImage, response([
                .proposedKeywords: .array([
                    candidate("bird", confidence: "high")
                ])
            ]))
        ])
        var configuration = normalizationConfiguration()
        configuration.normalizationMode = .off

        let result = try CandidateCanonicalizer(vocabulary: vocabulary).canonicalize(
            extractionResults: [extraction],
            input: inputBatch(),
            configuration: configuration
        )

        let decision = try XCTUnwrap(result.perAssetDecisions.first)
        XCTAssertEqual(decision.stage, .phase2Fallback)
        XCTAssertEqual(decision.candidateKind, .phase2Fallback)
        XCTAssertNil(decision.canonicalPath)
        XCTAssertEqual(decision.flatKeyword, "bird")
        XCTAssertEqual(decision.hierarchicalKeyword, "bird")
        XCTAssertEqual(result.batchCandidates.first?.candidateKind, .phase2Fallback)
    }

    func testVocabularyDirectApplyPolicyWithholdsModelEvidenceAndFlatOnlySuppressesHierarchy() throws {
        let vocabulary = try loadedVocabulary(entries: [
            subjectRoot(),
            VocabularyEntry(
                canonicalPath: "Subject|Sensitive",
                flatKeyword: "Sensitive",
                namespace: .subject,
                parentPath: "Subject",
                synonyms: ["rare bird"],
                requiresReview: true,
                directApplyPolicy: .withhold
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Flat",
                flatKeyword: "Flat Only",
                namespace: .subject,
                parentPath: "Subject",
                synonyms: ["flat tag"],
                requiresReview: false,
                directApplyPolicy: .flatOnly
            )
        ])
        let extraction = try extractionResult(responses: [
            (.wholeImage, response([
                .proposedKeywords: .array([
                    candidate("rare bird", confidence: "high"),
                    candidate("flat tag", confidence: "high")
                ])
            ]))
        ])
        var configuration = normalizationConfiguration()
        configuration.allowSpecificTags = true

        let result = try CandidateCanonicalizer(vocabulary: vocabulary).canonicalize(
            extractionResults: [extraction],
            input: inputBatch(),
            configuration: configuration
        )

        let sensitive = try XCTUnwrap(result.perAssetDecisions.first { $0.canonicalPath == "Subject|Sensitive" })
        XCTAssertEqual(sensitive.status, .withheld)
        XCTAssertNil(sensitive.flatKeyword)
        XCTAssertNil(sensitive.hierarchicalKeyword)
        XCTAssertEqual(sensitive.skipReasons, [.directApplyWithheld, .requiresReview])

        let flatOnly = try XCTUnwrap(result.perAssetDecisions.first { $0.canonicalPath == "Subject|Flat" })
        XCTAssertEqual(flatOnly.status, .accepted)
        XCTAssertEqual(flatOnly.flatKeyword, "Flat Only")
        XCTAssertNil(flatOnly.hierarchicalKeyword)
        XCTAssertEqual(flatOnly.skipReasons, [.directApplyFlatOnly])
    }

    func testUnknownSessionContextRejectsByDefaultAndWriteUnnormalizedCreatesFlatOnlyUserDecision() throws {
        let vocabulary = try loadedVocabulary()
        var rejecting = normalizationConfiguration()
        rejecting.sessionSubject = "Folder Mystery"

        XCTAssertThrowsError(
            try CandidateCanonicalizer.preflightSessionContext(
                configuration: rejecting,
                vocabulary: vocabulary
            )
        ) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .validationFailed)
            XCTAssertEqual((error as? SidecarError)?.stage, .normalize)
        }

        var allowing = rejecting
        allowing.unknownSessionContextPolicy = .writeUnnormalized
        allowing.allowSessionSubjectPropagation = true
        let result = try CandidateCanonicalizer(vocabulary: vocabulary).canonicalize(
            extractionResults: [],
            input: inputBatch(),
            configuration: allowing
        )

        XCTAssertEqual(result.sessionContext.first?.unknownPolicyResult, "write_unnormalized")
        XCTAssertEqual(result.sessionContext.first?.directApplyPolicy, .flatOnly)
        let decision = try XCTUnwrap(result.perAssetDecisions.first)
        XCTAssertEqual(decision.stage, .userSessionContext)
        XCTAssertEqual(decision.candidateKind, .userContextUnnormalized)
        XCTAssertEqual(decision.flatKeyword, "Folder Mystery")
        XCTAssertNil(decision.hierarchicalKeyword)
        XCTAssertEqual(decision.skipReasons, [.unknownSessionContextFlatOnly])
    }

    private func loadedVocabulary(entries: [VocabularyEntry]? = nil) throws -> LoadedVocabulary {
        try VocabularyLoader.load(
            data: vocabularyData(entries: entries ?? [
                subjectRoot(),
                VocabularyEntry(
                    canonicalPath: "Subject|Wildlife",
                    flatKeyword: "Wildlife",
                    namespace: .subject,
                    parentPath: "Subject",
                    synonyms: ["wild animal"],
                    requiresReview: false,
                    directApplyPolicy: .allow
                ),
                VocabularyEntry(
                    canonicalPath: "Subject|Wildlife|Birds",
                    flatKeyword: "Birds",
                    namespace: .subject,
                    parentPath: "Subject|Wildlife",
                    synonyms: ["bird", "avian"],
                    requiresReview: false,
                    directApplyPolicy: .allow
                )
            ]),
            sourcePath: "memory://canonicalizer.json"
        )
    }

    private func subjectRoot() -> VocabularyEntry {
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
        )
    }

    private func normalizationConfiguration() -> ResolvedNormalizationConfiguration {
        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.normalizationMode = .singleImage
        configuration.minConfidence = .medium
        return configuration
    }

    private func xmpConfiguration(
        minConfidence: XMPMinimumConfidence = .medium,
        allowSpecificTags: Bool = true
    ) -> ResolvedXMPExportConfiguration {
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.minConfidence = minConfidence
        configuration.allowSpecificTags = allowSpecificTags
        return configuration
    }

    private func extractionResult(
        responses: [(ModelInputRole, JSONValue?)]
    ) throws -> CandidateExtractionResult {
        CandidateExtractor().extract(
            from: try resolvedInput(responses: responses),
            configuration: xmpConfiguration(minConfidence: .medium, allowSpecificTags: true)
        )
    }

    private func resolvedInput(
        responses: [(ModelInputRole, JSONValue?)]
    ) throws -> ResolvedRawSidecarInput {
        try ResolvedRawSidecarInput(
            sidecarPath: URL(fileURLWithPath: "/sidecars/Bird.JPG.ai.json"),
            document: RawJSONSidecarDocument(sidecar: sidecar(responses: responses)),
            sourcePath: URL(fileURLWithPath: "/photos/Bird.JPG"),
            sourceIdentityStatus: .skipped,
            relativePath: "Bird.JPG.ai.json",
            warnings: []
        )
    }

    private func sidecar(responses: [(ModelInputRole, JSONValue?)]) -> RawJSONSidecar {
        RawJSONSidecar(
            source: makeSource(fileName: "Bird.JPG", relativePath: "Bird.JPG", path: "/photos/Bird.JPG"),
            runConfiguration: .builtInDefaults,
            modelRuns: responses.enumerated().map { index, item in
                modelRun(role: item.0, response: item.1, index: index)
            },
            createdAt: Date(timeIntervalSince1970: 1_800_004_000)
        )
    }

    private func modelRun(role: ModelInputRole, response: JSONValue?, index: Int) -> ModelRunRecord {
        ModelRunRecord(
            inputRole: role,
            model: "gemma4:26b-a4b-it-qat",
            modelDigest: "sha256:test-\(index)",
            runtime: "ollama",
            runtimeVersion: "0.12.6",
            promptVersion: "aisidecar.prompt.test/1.0.0",
            promptSHA256: String(repeating: "a", count: 64),
            responseSchemaVersion: "urn:aisidecar:response:test:1.0.0",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "b", count: 64),
            rawResponseText: "{}",
            parsedResponseJSON: response,
            jsonValid: response != nil,
            durationMs: 1,
            error: nil
        )
    }

    private func inputBatch() -> NormalizationResolvedInputBatch {
        let source = makeSource(fileName: "Bird.JPG", relativePath: "Bird.JPG", path: "/photos/Bird.JPG")
        var affinityInputs = AssetAffinityInputBuilder.make(assetID: "asset-000001", source: source)
        affinityInputs.sameBaseNameGroupID = "group-000001"
        return NormalizationResolvedInputBatch(
            workflow: .fromJSON,
            inputPath: "/sidecars",
            inputBasePath: "/sidecars",
            scanRoot: "/sidecars",
            sourceAssets: [
                NormalizationSourceAsset(
                    assetID: "asset-000001",
                    sourcePath: source.path,
                    sourceRelativePath: source.relativePath,
                    fileName: source.fileName,
                    sourceType: source.detectedType,
                    sourceIdentity: source.identity,
                    sourceSidecarPath: "/sidecars/Bird.JPG.ai.json",
                    sourceSidecarRelativePath: "Bird.JPG.ai.json",
                    sourceIdentityStatus: .skipped,
                    fileListIndex: nil,
                    affinityInputs: affinityInputs
                )
            ],
            sourceAISidecars: [
                NormalizationSourceAISidecarRecord(
                    sidecarPath: "/sidecars/Bird.JPG.ai.json",
                    relativePath: "Bird.JPG.ai.json",
                    sourceAssetID: "asset-000001",
                    schemaVersion: "ai-sidecar-json/1.3",
                    sourceIdentityStatus: .skipped,
                    warnings: []
                )
            ],
            sameBaseNameGroups: [
                NormalizationSourceGroup(
                    groupID: "group-000001",
                    groupDirectory: "",
                    groupBasename: "Bird",
                    targetRelativePath: "Bird.xmp",
                    memberAssetIDs: ["asset-000001"],
                    selectedAssetIDs: ["asset-000001"],
                    skippedAssetIDs: []
                )
            ],
            warnings: [],
            failures: []
        )
    }

    private func response(_ fields: [CandidateSourceField: JSONValue]) -> JSONValue {
        var object: [String: JSONValue] = [
            "summary": .string("fixture"),
            "uncertainty_notes": .string("")
        ]
        for (field, value) in fields {
            object[field.rawValue] = value
        }
        return .object(object)
    }

    private func candidate(
        _ term: String,
        confidence: String = "high",
        evidence: String? = "visible evidence"
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "term": .string(term),
            "confidence": .string(confidence)
        ]
        if let evidence {
            object["evidence"] = .string(evidence)
        }
        return .object(object)
    }
}
