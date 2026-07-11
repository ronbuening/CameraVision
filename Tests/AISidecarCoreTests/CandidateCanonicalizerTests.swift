import Foundation
import XCTest
@testable import AISidecarCore

final class CandidateCanonicalizerTests: XCTestCase {
    func testObservationBuilderRejectsDuplicateSourceSidecarPath() throws {
        var input = inputBatch()
        let duplicate = try XCTUnwrap(input.sourceAISidecars.first)
        input.sourceAISidecars.append(duplicate)

        XCTAssertThrowsError(
            try CandidateObservationBuilder().build(extractionResults: [], input: input)
        ) { error in
            let sidecarError = error as? SidecarError
            XCTAssertEqual(sidecarError?.code, .validationFailed)
            XCTAssertEqual(sidecarError?.stage, .normalize)
            XCTAssertTrue(sidecarError?.message.contains(duplicate.sidecarPath) == true)
        }
    }

    func testObservationBuilderRejectsAssetPresentInMultipleGroups() throws {
        var input = inputBatch()
        let assetID = try XCTUnwrap(input.sourceAssets.first?.assetID)
        input.sameBaseNameGroups.append(
            NormalizationSourceGroup(
                groupID: "group-duplicate",
                groupDirectory: "",
                groupBasename: "Duplicate",
                targetRelativePath: "Duplicate.xmp",
                memberAssetIDs: [assetID],
                selectedAssetIDs: [assetID],
                skippedAssetIDs: []
            )
        )

        XCTAssertThrowsError(
            try CandidateObservationBuilder().build(extractionResults: [], input: input)
        ) { error in
            let sidecarError = error as? SidecarError
            XCTAssertEqual(sidecarError?.code, .validationFailed)
            XCTAssertEqual(sidecarError?.stage, .normalize)
            XCTAssertTrue(sidecarError?.message.contains(assetID) == true)
        }
    }

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

    func testUnmatchedSpeciesFallbackCollapsesAcrossBatchToFlatDirectModelDecisions() throws {
        let vocabulary = try loadedVocabulary()
        let first = try extractionResult(fileName: "HeronA.JPG", responses: [
            (.wholeImage, response([
                .species: .array([
                    candidate("great blue herons", confidence: "high")
                ])
            ]))
        ])
        let second = try extractionResult(fileName: "HeronB.JPG", responses: [
            (.subjectIsolated, response([
                .species: .array([
                    candidate("Great Blue Heron", confidence: "high")
                ])
            ]))
        ])

        let result = try CandidateCanonicalizer(vocabulary: vocabulary).canonicalize(
            extractionResults: [first, second],
            input: inputBatch(fileNames: ["HeronA.JPG", "HeronB.JPG"]),
            configuration: normalizationConfiguration()
        )

        XCTAssertTrue(result.skips.isEmpty)
        XCTAssertEqual(result.perAssetDecisions.count, 2)
        XCTAssertEqual(result.perAssetDecisions.map(\.candidateKind), [
            .modelSpeciesFallback,
            .modelSpeciesFallback
        ])
        XCTAssertEqual(result.perAssetDecisions.map(\.stage), [
            .directModelObservation,
            .directModelObservation
        ])
        XCTAssertEqual(result.perAssetDecisions.compactMap(\.canonicalPath), [])
        XCTAssertEqual(result.perAssetDecisions.compactMap(\.flatKeyword), [
            "Great Blue Heron",
            "Great Blue Heron"
        ])
        XCTAssertEqual(result.perAssetDecisions.compactMap(\.hierarchicalKeyword), [])
        XCTAssertEqual(result.perAssetDecisions.compactMap(\.directApplyPolicy), [.flatOnly, .flatOnly])
        XCTAssertEqual(result.perAssetDecisions.map(\.skipReasons), [
            [.directApplyFlatOnly],
            [.directApplyFlatOnly]
        ])

        let summary = try XCTUnwrap(result.batchCandidates.first)
        XCTAssertEqual(summary.candidateKind, .modelSpeciesFallback)
        XCTAssertEqual(summary.flatKeyword, "Great Blue Heron")
        XCTAssertNil(summary.hierarchicalKeyword)
        XCTAssertEqual(summary.supportingAssetIDs, ["asset-000001", "asset-000002"])
        XCTAssertEqual(summary.directAssetSupportCount, 2)
        XCTAssertEqual(summary.observationCount, 2)
        XCTAssertEqual(summary.sourceFields, ["species": 2])
    }

    func testUnmatchedSpeciesFallbackHonorsSpecificTagPolicy() throws {
        let vocabulary = try loadedVocabulary()
        let extraction = try extractionResult(allowSpecificTags: false, responses: [
            (.wholeImage, response([
                .species: .array([
                    candidate("Ardea herodias", confidence: "high")
                ])
            ]))
        ])

        let result = try CandidateCanonicalizer(vocabulary: vocabulary).canonicalize(
            extractionResults: [extraction],
            input: inputBatch(),
            configuration: normalizationConfiguration()
        )

        XCTAssertTrue(result.perAssetDecisions.isEmpty)
        XCTAssertEqual(result.skips.map(\.reason), [.specificTagPolicy])
        XCTAssertEqual(result.skips.first?.sourceField, .species)
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
        configuration.vocabularyMode = .controlledVocabulary
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
        fileName: String = "Bird.JPG",
        allowSpecificTags: Bool = true,
        responses: [(ModelInputRole, JSONValue?)]
    ) throws -> CandidateExtractionResult {
        CandidateExtractor().extract(
            from: try resolvedInput(fileName: fileName, responses: responses),
            configuration: xmpConfiguration(minConfidence: .medium, allowSpecificTags: allowSpecificTags)
        )
    }

    private func resolvedInput(
        fileName: String = "Bird.JPG",
        responses: [(ModelInputRole, JSONValue?)]
    ) throws -> ResolvedRawSidecarInput {
        let sidecarPath = "/sidecars/\(fileName).ai.json"
        return try ResolvedRawSidecarInput(
            sidecarPath: URL(fileURLWithPath: sidecarPath),
            document: RawJSONSidecarDocument(sidecar: sidecar(fileName: fileName, responses: responses)),
            sourcePath: URL(fileURLWithPath: "/photos/\(fileName)"),
            sourceIdentityStatus: .skipped,
            relativePath: "\(fileName).ai.json",
            warnings: []
        )
    }

    private func sidecar(fileName: String = "Bird.JPG", responses: [(ModelInputRole, JSONValue?)]) -> RawJSONSidecar {
        RawJSONSidecar(
            source: makeSource(fileName: fileName, relativePath: fileName, path: "/photos/\(fileName)"),
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
        inputBatch(fileNames: ["Bird.JPG"])
    }

    private func inputBatch(fileNames: [String]) -> NormalizationResolvedInputBatch {
        let assets: [NormalizationSourceAsset] = fileNames.enumerated().map { index, fileName in
            let assetID = String(format: "asset-%06d", index + 1)
            let groupID = String(format: "group-%06d", index + 1)
            let source = makeSource(fileName: fileName, relativePath: fileName, path: "/photos/\(fileName)")
            var affinityInputs = AssetAffinityInputBuilder.make(assetID: assetID, source: source)
            affinityInputs.sameBaseNameGroupID = groupID
            return NormalizationSourceAsset(
                assetID: assetID,
                sourcePath: source.path,
                sourceRelativePath: source.relativePath,
                fileName: source.fileName,
                sourceType: source.detectedType,
                sourceIdentity: source.identity,
                sourceSidecarPath: "/sidecars/\(fileName).ai.json",
                sourceSidecarRelativePath: "\(fileName).ai.json",
                sourceIdentityStatus: .skipped,
                fileListIndex: nil,
                affinityInputs: affinityInputs
            )
        }
        let sidecars: [NormalizationSourceAISidecarRecord] = fileNames.enumerated().map { index, fileName in
            NormalizationSourceAISidecarRecord(
                sidecarPath: "/sidecars/\(fileName).ai.json",
                relativePath: "\(fileName).ai.json",
                sourceAssetID: String(format: "asset-%06d", index + 1),
                schemaVersion: "ai-sidecar-json/1.3",
                sourceIdentityStatus: .skipped,
                warnings: []
            )
        }
        let groups: [NormalizationSourceGroup] = fileNames.enumerated().map { index, fileName in
            let assetID = String(format: "asset-%06d", index + 1)
            let groupID = String(format: "group-%06d", index + 1)
            let basename = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
            return NormalizationSourceGroup(
                groupID: groupID,
                groupDirectory: "",
                groupBasename: basename,
                targetRelativePath: "\(basename).xmp",
                memberAssetIDs: [assetID],
                selectedAssetIDs: [assetID],
                skippedAssetIDs: []
            )
        }
        return NormalizationResolvedInputBatch(
            workflow: .fromJSON,
            inputPath: "/sidecars",
            inputBasePath: "/sidecars",
            scanRoot: "/sidecars",
            sourceAssets: assets,
            sourceAISidecars: sidecars,
            sameBaseNameGroups: groups,
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
