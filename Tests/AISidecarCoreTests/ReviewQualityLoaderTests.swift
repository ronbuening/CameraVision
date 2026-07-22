import Foundation
import XCTest

@testable import AISidecarCore

final class ReviewQualityLoaderTests: XCTestCase {
    func testPlannedPresentationUsesStandardizedOrRelativeKeysAndLaterPlanWins() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("photos", isDirectory: true)
        let pathSource = sourceImage(
            path: sourceRoot.appendingPathComponent("A.JPG").path,
            relativePath: "A.JPG"
        )
        let relativeSource = sourceImage(path: "", relativePath: "nested/B.JPG")
        let mismatchedSource = sourceImage(
            path: sourceRoot.appendingPathComponent("C.JPG").path,
            relativePath: "C.JPG"
        )
        var session = makeSession(
            assets: [
                sourceAsset(id: "path", source: pathSource),
                sourceAsset(id: "relative", source: relativeSource, sourcePath: nil),
                sourceAsset(id: "path-not-relative", source: mismatchedSource),
            ]
        )
        session.xmpWritePlans = [
            normalizedPlan(
                plan(
                    memberPath: sourceRoot.appendingPathComponent("folder/../A.JPG").path,
                    memberRelativePath: "different/A.JPG",
                    tier: .good,
                    explanations: ["tier=good"]
                )
            ),
            normalizedPlan(
                plan(
                    memberPath: sourceRoot.appendingPathComponent("./A.JPG").path,
                    memberRelativePath: "also-different/A.JPG",
                    tier: .excellent,
                    explanations: ["tier=excellent", "later plan wins"]
                )
            ),
            normalizedPlan(
                plan(
                    memberPath: nil,
                    memberRelativePath: "nested/B.JPG",
                    tier: nil,
                    explanations: ["ungraded reason=no_records"]
                )
            ),
            normalizedPlan(
                plan(
                    memberPath: nil,
                    memberRelativePath: "C.JPG",
                    tier: .reject,
                    explanations: ["tier=reject"]
                )
            ),
        ]

        let presentation = ReviewQualityLoader().plannedPresentation(for: session)

        XCTAssertEqual(presentation["path"]?.tier, .excellent)
        XCTAssertEqual(presentation["path"]?.explanations, ["tier=excellent", "later plan wins"])
        XCTAssertEqual(presentation["relative"]?.ungradedReason, "ungraded reason=no_records")
        XCTAssertNil(presentation["path-not-relative"])
        XCTAssertTrue(presentation.values.allSatisfy { $0.records.isEmpty && $0.issueDiagnostics.isEmpty })
    }

    func testLoadMergesCurrentPairWithoutIdentityGateAndPreservesRecordAndIssueOrder() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let sidecarRoot = root.appendingPathComponent("sidecars", isDirectory: true)
        let sourceURL = root.appendingPathComponent("photos/A.JPG")
        let source = sourceImage(path: sourceURL.path, relativePath: "A.JPG")
        let taggingURL = sidecarRoot.appendingPathComponent("A.JPG.ai.json")
        try writeSidecar(
            at: taggingURL,
            source: source,
            profile: .tagging,
            runs: [taggingRun()],
            createdAt: 100
        )
        let qualityURL = sidecarRoot.appendingPathComponent("A.JPG.quality.ai.json")
        try writeSidecar(
            at: qualityURL,
            source: source,
            profile: .qualityOnly,
            runs: [
                qualityRun(
                    role: .subjectIsolated,
                    prompt: "prompt.subject",
                    assessment: assessment(
                        role: .subjectIsolated,
                        overall: "strong",
                        focus: "acceptable",
                        confidence: "medium"
                    )
                ),
                qualityRun(
                    role: .wholeImage,
                    prompt: "prompt.whole",
                    assessment: assessment(
                        role: .wholeImage,
                        overall: "acceptable",
                        focus: "excellent",
                        confidence: "high",
                        additional: ["future_aesthetic_signal": .string("strong")]
                    )
                ),
            ],
            createdAt: 200
        )
        var session = makeSession(
            sidecars: [sidecarRecord(path: taggingURL.path, assetID: "asset")],
            assets: [sourceAsset(id: "asset", source: source)]
        )
        session.xmpWritePlans = [
            normalizedPlan(
                plan(
                    memberPath: source.path,
                    memberRelativePath: source.relativePath,
                    tier: .good,
                    explanations: ["tier=good", "problem_count=0"]
                )
            )
        ]

        // The current-pair seam must not re-hash or even require the source image.
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        let loaded = ReviewQualityLoader().load(for: session)

        XCTAssertEqual(loaded.diagnostics, [])
        let quality = try XCTUnwrap(loaded.presentationByAssetID["asset"])
        XCTAssertEqual(quality.records.map(\.role), [.wholeImage, .subjectIsolated])
        XCTAssertEqual(quality.records.map(\.promptVersion), ["prompt.whole", "prompt.subject"])
        XCTAssertEqual(quality.records.first?.overall, .acceptable)
        XCTAssertEqual(quality.records.last?.overall, .strong)
        XCTAssertEqual(
            quality.issueDiagnostics,
            [
                "invalid_level: focus=excellent",
                "unknown_criterion: future_aesthetic_signal",
            ]
        )
        XCTAssertEqual(quality.tier, .good)
        XCTAssertEqual(quality.explanations, ["tier=good", "problem_count=0"])
    }

    func testStoredContributorOrderFirstExtractionAndStandardizedConsumptionAreStable() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = sourceImage(path: "/photos/A.JPG", relativePath: "A.JPG")
        let firstURL = root.appendingPathComponent("Z.JPG.quality.ai.json")
        let laterURL = root.appendingPathComponent("A.JPG.quality.ai.json")
        try writeSidecar(
            at: firstURL,
            source: source,
            profile: .qualityOnly,
            runs: [
                qualityRun(
                    role: .wholeImage,
                    prompt: "stored-first",
                    assessment: assessment(
                        role: .wholeImage,
                        overall: "strong",
                        focus: "strong",
                        confidence: "high"
                    )
                )
            ],
            createdAt: 300
        )
        try writeSidecar(
            at: laterURL,
            source: source,
            profile: .qualityOnly,
            runs: [
                qualityRun(
                    role: .wholeImage,
                    prompt: "stored-later",
                    assessment: assessment(
                        role: .wholeImage,
                        overall: "problem",
                        focus: "problem",
                        confidence: "high"
                    )
                )
            ],
            createdAt: 100
        )
        let duplicateSpelling = root.appendingPathComponent("unused/../Z.JPG.quality.ai.json").path
        let duplicateSource = sourceImage(path: "/photos/B.JPG", relativePath: "B.JPG")
        let session = makeSession(
            sidecars: [
                sidecarRecord(path: firstURL.path, assetID: "shared"),
                sidecarRecord(path: laterURL.path, assetID: "shared"),
                sidecarRecord(path: duplicateSpelling, assetID: "duplicate"),
            ],
            assets: [
                sourceAsset(id: "shared", source: source),
                sourceAsset(id: "duplicate", source: duplicateSource),
            ]
        )

        let loaded = ReviewQualityLoader().load(for: session)

        XCTAssertEqual(loaded.diagnostics, [])
        XCTAssertEqual(loaded.presentationByAssetID["shared"]?.records.first?.promptVersion, "stored-first")
        XCTAssertEqual(loaded.presentationByAssetID["shared"]?.records.first?.overall, .strong)
        XCTAssertNil(loaded.presentationByAssetID["duplicate"])
    }

    func testFailuresWithinCurrentPairArePathSortedWithExactDiagnostics() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let taggingURL = root.appendingPathComponent("Bad.JPG.ai.json")
        let qualityURL = root.appendingPathComponent("Bad.JPG.quality.ai.json")
        try Data("{}".utf8).write(to: taggingURL)
        try Data("{}".utf8).write(to: qualityURL)
        let source = sourceImage(path: "/photos/Bad.JPG", relativePath: "Bad.JPG")
        let session = makeSession(
            sidecars: [sidecarRecord(path: qualityURL.path, assetID: "bad")],
            assets: [sourceAsset(id: "bad", source: source)]
        )

        let loaded = ReviewQualityLoader().load(for: session)

        XCTAssertTrue(loaded.presentationByAssetID.isEmpty)
        XCTAssertEqual(
            loaded.diagnostics,
            [
                "E_VALIDATION_FAILED: Raw sidecar document is missing schema_version: \(taggingURL.path)",
                "E_VALIDATION_FAILED: Raw sidecar document is missing schema_version: \(qualityURL.path)",
            ]
        )
    }

    func testMissingPairDiagnosticAndLegacyPresentationAreExact() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let missingURL = root.appendingPathComponent("Gone.JPG.ai.json")
        let source = sourceImage(path: "/photos/Gone.JPG", relativePath: "Gone.JPG")
        let session = makeSession(
            sidecars: [sidecarRecord(path: missingURL.path, assetID: "gone")],
            assets: [sourceAsset(id: "gone", source: source)]
        )

        XCTAssertTrue(ReviewQualityLoader().plannedPresentation(for: session).isEmpty)
        XCTAssertEqual(
            ReviewQualityLoader().load(for: session),
            ReviewQualityLoadResult(
                presentationByAssetID: [:],
                diagnostics: [
                    "E_VALIDATION_FAILED: Stored raw sidecar and its quality pair are unavailable: \(missingURL.path)"
                ]
            )
        )
    }

    func testPublicValuesAreSendableAndEquatable() {
        let presentation = ReviewAssetQualityPresentation(
            records: [],
            issueDiagnostics: ["malformed_block"],
            tier: .reject,
            explanations: ["tier=reject"],
            ungradedReason: nil
        )
        let result = ReviewQualityLoadResult(
            presentationByAssetID: ["asset": presentation],
            diagnostics: ["diagnostic"]
        )
        let loader = ReviewQualityLoader()

        requireSendable(presentation)
        requireSendable(result)
        requireSendable(loader)
        XCTAssertEqual(presentation, presentation)
        XCTAssertEqual(result, result)
        XCTAssertEqual(loader, ReviewQualityLoader())
    }

    private func makeSession(
        sidecars: [NormalizationSourceAISidecarRecord] = [],
        assets: [NormalizationSourceAsset]
    ) -> NormalizationSessionDocument {
        NormalizationSessionDocument(
            session: NormalizationSessionMetadata(
                sessionID: "review-quality-loader",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                workflow: .fromJSON,
                inputPath: "/sidecars",
                normalizationMode: .singleImage,
                scanRoot: nil,
                sourceRoot: "/photos",
                outputDir: nil
            ),
            vocabulary: VocabularyIdentity(
                path: "observed-tags://session",
                sha256: String(repeating: "d", count: 64),
                schemaVersion: "observed-tags/1.0",
                mode: .observedTags,
                entryCount: 0
            ),
            resolvedConfiguration: .builtInDefaults,
            sessionContext: [],
            privacy: NormalizationPrivacyRecord(privacyMode: .standard),
            xmpWriter: MetadataWriteEngineContext(
                engineName: OwnedXMPSidecarEngine.engineName,
                engineVersion: OwnedXMPSidecarEngine.engineVersion,
                writerRecipeVersion: OwnedXMPSidecarEngine.writerRecipeVersion
            ),
            sourceAISidecars: sidecars,
            sourceAssets: assets,
            sameBaseNameGroups: [],
            affinity: NormalizationAffinityRecord(
                mode: .off,
                profile: .balanced,
                minAffinityForConsensus: 0.55,
                nodes: []
            ),
            artifacts: NormalizationArtifactPlan(
                sessionPath: nil,
                reportPath: "/artifacts/report.json",
                summaryPath: "/artifacts/summary.md",
                progressPath: "/artifacts/progress.jsonl",
                xmpTargetRoot: nil
            ),
            deterministicPolicy: NormalizationDeterministicPolicyRecord(exactAffinityInputsPersisted: false),
            warnings: [],
            errors: []
        )
    }

    private func sourceImage(path: String, relativePath: String) -> SourceImage {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        return SourceImage(
            path: path,
            relativePath: relativePath,
            fileName: fileName,
            fileExtension: URL(fileURLWithPath: fileName).pathExtension,
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: .jpg,
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
        )
    }

    private func sourceAsset(
        id: String,
        source: SourceImage,
        sourcePath: String? = nil
    ) -> NormalizationSourceAsset {
        NormalizationSourceAsset(
            assetID: id,
            sourcePath: sourcePath ?? (source.path.isEmpty ? nil : source.path),
            sourceRelativePath: source.relativePath,
            fileName: source.fileName,
            sourceType: source.detectedType,
            sourceIdentity: source.identity,
            sourceSidecarPath: nil,
            sourceSidecarRelativePath: nil,
            sourceIdentityStatus: .matched,
            fileListIndex: nil,
            affinityInputs: AssetAffinityInputBuilder.make(assetID: id, source: source)
        )
    }

    private func sidecarRecord(path: String, assetID: String) -> NormalizationSourceAISidecarRecord {
        NormalizationSourceAISidecarRecord(
            sidecarPath: path,
            relativePath: URL(fileURLWithPath: path).lastPathComponent,
            sourceAssetID: assetID,
            schemaVersion: "ai-sidecar-json/1.3",
            sourceIdentityStatus: .matched,
            warnings: []
        )
    }

    private func writeSidecar(
        at url: URL,
        source: SourceImage,
        profile: ModelTaskProfile,
        runs: [ModelRunRecord],
        createdAt: TimeInterval
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sidecar = RawJSONSidecar(
            source: source,
            runConfiguration: ResolvedRunConfiguration.builtInDefaults.with(taskProfile: profile),
            modelRuns: runs,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
        try RawJSONSidecarDocument(sidecar: sidecar).encodedData().write(to: url)
    }

    private func taggingRun() -> ModelRunRecord {
        ModelRunRecord(
            inputRole: .wholeImage,
            model: "test:model",
            modelDigest: "sha256:test",
            runtime: "test",
            runtimeVersion: "1",
            promptVersion: "prompt.tagging",
            promptSHA256: String(repeating: "b", count: 64),
            responseSchemaVersion: "schema.test",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "c", count: 64),
            rawResponseText: "fixture",
            parsedResponseJSON: .object(["proposed_keywords": .array([])]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func qualityRun(
        role: ModelInputRole,
        prompt: String,
        assessment: [String: JSONValue]
    ) -> ModelRunRecord {
        ModelRunRecord(
            inputRole: role,
            model: "test:model",
            modelDigest: "sha256:test",
            runtime: "test",
            runtimeVersion: "1",
            promptVersion: prompt,
            promptSHA256: String(repeating: "b", count: 64),
            responseSchemaVersion: "schema.test",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "c", count: 64),
            rawResponseText: "fixture",
            parsedResponseJSON: .object(["quality_assessment": .object(assessment)]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func assessment(
        role: ModelInputRole,
        overall: String,
        focus: String,
        confidence: String,
        additional: [String: JSONValue] = [:]
    ) -> [String: JSONValue] {
        var result: [String: JSONValue] = [
            "focus": .string(focus),
            role == .wholeImage ? "overall_effectiveness" : "overall_subject_quality": .string(overall),
            "strengths": .array([.string("visible strength")]),
            "concerns": .array([]),
            "confidence": .string(confidence),
        ]
        for (key, value) in additional {
            result[key] = value
        }
        return result
    }

    private func plan(
        memberPath: String?,
        memberRelativePath: String,
        tier: QualityTier?,
        explanations: [String]?
    ) -> XMPChangePlan {
        XMPChangePlan(
            status: .planned,
            targetXMPPath: "/xmp/target.xmp",
            targetRelativePath: "target.xmp",
            pairScope: .union,
            sourceMembers: [
                SourceMemberPlan(
                    sourcePath: memberPath,
                    sourceRelativePath: memberRelativePath,
                    sourceFileName: URL(fileURLWithPath: memberRelativePath).lastPathComponent,
                    sourceType: .jpg,
                    sourceSidecarPath: nil,
                    sourceSidecarRelativePath: nil,
                    sourceIdentityStatus: .matched,
                    pairKind: .jpeg,
                    selected: true,
                    skipReason: nil,
                    flatKeywordContributionCount: 0,
                    hierarchicalKeywordContributionCount: 0
                )
            ],
            flatKeywordsToAdd: [],
            hierarchicalKeywordsToAdd: [],
            skippedCandidates: [],
            candidateExtractionIssues: [],
            sourceVerificationWarnings: [],
            groupWarnings: [],
            existingPolicy: .backupAndMerge,
            backupPlan: BackupPlan(
                backupSidecars: true,
                backupRequiredBeforeMerge: true,
                conflictPolicy: .backupAndMerge
            ),
            validationPlan: .phase2Default,
            failures: [],
            qualityExplanation: explanations,
            qualityTier: tier
        )
    }

    private func normalizedPlan(_ plan: XMPChangePlan) -> NormalizedXMPWritePlan {
        NormalizedXMPWritePlan(
            xmpChangePlan: plan,
            flatKeywordProvenance: [],
            hierarchicalKeywordProvenance: [],
            normalizationSkips: []
        )
    }

    private func requireSendable<T: Sendable>(_: T) {}
}
