import AISidecarCore
import Foundation
import XCTest

@testable import CupricAspectApp

final class QualityPresentationTests: XCTestCase {
    func testCoreExtractionMapsCombinedAndQualitySiblingFixturesToExactAssetRows() throws {
        let combinedSource = sourceImage(path: "/photos/Combined.JPG")
        let qualityOnlySource = sourceImage(path: "/photos/Quality.JPG")
        let combined = try resolvedInput(
            source: combinedSource,
            primaryRuns: [
                modelRun(
                    role: .wholeImage,
                    assessment: wholeAssessment(
                        overall: "acceptable",
                        focus: "strong",
                        confidence: "high",
                        strengths: ["sharp eye detail"],
                        concerns: []
                    )
                ),
                modelRun(
                    role: .subjectIsolated,
                    assessment: subjectAssessment(
                        overall: "strong",
                        focus: "acceptable",
                        confidence: "medium",
                        strengths: ["clear subject detail"],
                        concerns: ["minor edge artifact"]
                    )
                ),
            ],
            primaryProfile: .taggingWithQuality
        )
        let qualitySibling = try resolvedInput(
            source: qualityOnlySource,
            primaryRuns: [],
            primaryProfile: .tagging,
            qualityRuns: [
                modelRun(
                    role: .wholeImage,
                    assessment: wholeAssessment(
                        overall: "problem",
                        focus: "problem",
                        confidence: "medium",
                        strengths: [],
                        concerns: ["focus misses the subject"]
                    )
                )
            ]
        )
        let assets = [
            sourceAsset(id: "combined", source: combinedSource),
            sourceAsset(id: "quality", source: qualityOnlySource),
        ]
        let writePlans = [
            normalizedPlan(
                plan(
                    source: combinedSource,
                    target: "Combined.xmp",
                    tier: .good,
                    explanations: ["tier=good"]
                )
            ),
            normalizedPlan(
                plan(
                    source: qualityOnlySource,
                    target: "Quality.xmp",
                    tier: nil,
                    explanations: ["ungraded reason=below_minimum_confidence", "confidence=medium"]
                )
            ),
        ]

        let rows = ReviewModel.qualityPresentation(
            sourceAssets: assets,
            xmpWritePlans: writePlans,
            extractionByAssetID: [
                "combined": QualityAssessmentExtractor.extract(from: combined),
                "quality": QualityAssessmentExtractor.extract(from: qualitySibling),
            ]
        )

        XCTAssertEqual(rows["combined"]?.records.map(\.role), [.wholeImage, .subjectIsolated])
        XCTAssertEqual(rows["combined"]?.records.first?.overall, .acceptable)
        XCTAssertEqual(rows["combined"]?.records.first?.criteria[.focus], .strong)
        XCTAssertEqual(rows["combined"]?.records.first?.strengths, ["sharp eye detail"])
        XCTAssertEqual(rows["combined"]?.tier, .good)
        XCTAssertEqual(rows["quality"]?.records.map(\.role), [.wholeImage])
        XCTAssertEqual(rows["quality"]?.records.first?.concerns, ["focus misses the subject"])
        XCTAssertNil(rows["quality"]?.tier)
        XCTAssertEqual(rows["quality"]?.ungradedReason, "ungraded reason=below_minimum_confidence")

        let summary = ReviewModel.qualitySummary(for: rows)
        XCTAssertEqual(summary.assessedAssetCount, 2)
        XCTAssertEqual(summary.tierCounts, [.good: 1])
        XCTAssertEqual(summary.ungradedAssetCount, 1)
        XCTAssertEqual(summary.issueCount, 0)
    }

    func testTolerantExtractionIssuesMapToNonFatalDiagnostics() throws {
        let source = sourceImage(path: "/photos/Issue.JPG")
        var assessment = wholeAssessment(
            overall: "acceptable",
            focus: "excellent",
            confidence: "high",
            strengths: [],
            concerns: []
        )
        assessment["future_aesthetic_signal"] = .string("strong")
        let input = try resolvedInput(
            source: source,
            primaryRuns: [modelRun(role: .wholeImage, assessment: assessment)],
            primaryProfile: .qualityOnly
        )

        let rows = ReviewModel.qualityPresentation(
            sourceAssets: [sourceAsset(id: "issue", source: source)],
            xmpWritePlans: [],
            extractionByAssetID: ["issue": QualityAssessmentExtractor.extract(from: input)]
        )

        XCTAssertEqual(rows["issue"]?.records.count, 1)
        XCTAssertEqual(
            rows["issue"]?.issueDiagnostics,
            [
                "invalid_level: focus=excellent",
                "unknown_criterion: future_aesthetic_signal",
            ]
        )
        XCTAssertEqual(ReviewModel.qualitySummary(for: rows).issueCount, 2)
    }

    func testPlanAndReportPresentationUsesCoreScalarActionsAndResultValues() throws {
        let source = sourceImage(path: "/photos/Graded.JPG")
        var graded = plan(
            source: source,
            target: "Graded.xmp",
            tier: .good,
            explanations: ["tier=good", "problem_count=0"]
        )
        graded.ratingWrite = PlannedScalarWrite(
            field: "xmp:Rating",
            plannedValue: "4",
            existingValue: "3",
            action: .overwrite
        )
        graded.labelWrite = PlannedScalarWrite(
            field: "xmp:Label",
            plannedValue: "Green",
            existingValue: "Blue",
            action: .skipExisting
        )
        let snapshot = XMPMetadataSnapshot(
            targetPath: graded.targetXMPPath,
            exists: true,
            flatKeywords: [],
            hierarchicalKeywords: [],
            unmanagedContentFingerprint: .empty(),
            rating: "3",
            label: "Blue"
        )
        let writeResult = try MockMetadataWriteEngine(
            snapshotsByPath: [graded.targetXMPPath: snapshot]
        ).apply(XMPWriteRequest(plan: graded))
        let ungraded = plan(
            source: sourceImage(path: "/photos/Ungraded.JPG"),
            target: "Ungraded.xmp",
            tier: nil,
            explanations: ["ungraded reason=no_records"]
        )
        let report = XMPExportReport(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            inputPath: "/photos",
            reportDirectory: nil,
            dryRun: false,
            configuration: .builtInDefaults,
            engine: MetadataWriteEngineContext(
                engineName: OwnedXMPSidecarEngine.engineName,
                engineVersion: OwnedXMPSidecarEngine.engineVersion,
                writerRecipeVersion: OwnedXMPSidecarEngine.writerRecipeVersion
            ),
            targetReports: [
                XMPExportTargetReport(
                    plan: graded,
                    status: .written,
                    writeResult: writeResult,
                    durationMs: 10
                ),
                XMPExportTargetReport(plan: ungraded, status: .unchanged, durationMs: 2),
            ],
            inputFailures: []
        )

        let planned = try XCTUnwrap(ExportModel.qualityPresentation(for: graded))
        XCTAssertEqual(planned.tier, .good)
        XCTAssertEqual(planned.explanations, ["tier=good", "problem_count=0"])
        XCTAssertEqual(planned.scalars.map(\.action), [.overwrite, .skipExisting])
        XCTAssertEqual(planned.scalars.map(\.plannedExistingValue), ["3", "Blue"])

        let completed = try XCTUnwrap(ExportModel.qualityPresentation(for: report.targetReports[0]))
        XCTAssertEqual(completed.scalars.map(\.resultExistingValue), ["3", "Blue"])
        XCTAssertEqual(completed.scalars.map(\.resultResultingValue), ["4", "Blue"])
        XCTAssertEqual(
            ExportModel.qualityPresentation(for: report.targetReports[1])?.ungradedReason,
            "ungraded reason=no_records"
        )
        XCTAssertEqual(
            ExportModel.qualitySummary(for: report),
            ExportModel.QualityExportSummary(
                gradedTargetCount: 1,
                ungradedTargetCount: 1,
                writtenScalarCount: 1,
                skippedScalarCount: 1
            )
        )
    }

    func testLegacyPlanAndAssessmentFreeRunHaveNoQualityPresentation() throws {
        let source = sourceImage(path: "/photos/Legacy.JPG")
        let legacyPlan = plan(source: source, target: "Legacy.xmp", tier: nil, explanations: nil)
        let document = XMPChangePlanDocument(
            schemaVersion: "ai-sidecar-xmp-change-plan/1.1",
            dryRun: true,
            targetPlans: [legacyPlan],
            inputFailures: []
        )
        let decoded = try JSONDecoder().decode(
            XMPChangePlanDocument.self,
            from: JSONCoding.documentEncoder().encode(document)
        )

        XCTAssertNil(ExportModel.qualityPresentation(for: try XCTUnwrap(decoded.targetPlans.first)))
        XCTAssertTrue(
            ReviewModel.qualityPresentation(
                sourceAssets: [sourceAsset(id: "legacy", source: source)],
                xmpWritePlans: [],
                extractionByAssetID: [:]
            ).isEmpty
        )
    }

    private func sourceImage(path: String) -> SourceImage {
        let url = URL(fileURLWithPath: path)
        return SourceImage(
            path: path,
            relativePath: url.lastPathComponent,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: .jpg,
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
        )
    }

    private func sourceAsset(id: String, source: SourceImage) -> NormalizationSourceAsset {
        NormalizationSourceAsset(
            assetID: id,
            sourcePath: source.path,
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

    private func resolvedInput(
        source: SourceImage,
        primaryRuns: [ModelRunRecord],
        primaryProfile: ModelTaskProfile,
        qualityRuns: [ModelRunRecord]? = nil
    ) throws -> ResolvedRawSidecarInput {
        let primary = RawJSONSidecar(
            source: source,
            runConfiguration: ResolvedRunConfiguration.builtInDefaults.with(taskProfile: primaryProfile),
            modelRuns: primaryRuns,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let primaryPath = URL(fileURLWithPath: "/sidecars/\(source.fileName).ai.json")
        if let qualityRuns {
            let quality = RawJSONSidecar(
                source: source,
                runConfiguration: ResolvedRunConfiguration.builtInDefaults.with(taskProfile: .qualityOnly),
                modelRuns: qualityRuns,
                createdAt: Date(timeIntervalSince1970: 200)
            )
            return ResolvedRawSidecarInput(
                sidecarPath: primaryPath,
                document: try RawJSONSidecarDocument(sidecar: primary),
                qualitySidecarPath: URL(fileURLWithPath: "/sidecars/\(source.fileName).quality.ai.json"),
                qualityDocument: try RawJSONSidecarDocument(sidecar: quality),
                sourcePath: URL(fileURLWithPath: source.path),
                sourceIdentityStatus: .matched,
                relativePath: primaryPath.lastPathComponent,
                warnings: []
            )
        }
        return ResolvedRawSidecarInput(
            sidecarPath: primaryPath,
            document: try RawJSONSidecarDocument(sidecar: primary),
            sourcePath: URL(fileURLWithPath: source.path),
            sourceIdentityStatus: .matched,
            relativePath: primaryPath.lastPathComponent,
            warnings: []
        )
    }

    private func modelRun(role: ModelInputRole, assessment: [String: JSONValue]) -> ModelRunRecord {
        ModelRunRecord(
            inputRole: role,
            model: "test:model",
            modelDigest: "sha256:test",
            runtime: "test",
            runtimeVersion: "1",
            promptVersion: "prompt.\(role.rawValue)",
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

    private func wholeAssessment(
        overall: String,
        focus: String,
        confidence: String,
        strengths: [String],
        concerns: [String]
    ) -> [String: JSONValue] {
        [
            "focus": .string(focus),
            "overall_effectiveness": .string(overall),
            "strengths": .array(strengths.map(JSONValue.string)),
            "concerns": .array(concerns.map(JSONValue.string)),
            "confidence": .string(confidence),
        ]
    }

    private func subjectAssessment(
        overall: String,
        focus: String,
        confidence: String,
        strengths: [String],
        concerns: [String]
    ) -> [String: JSONValue] {
        [
            "focus": .string(focus),
            "overall_subject_quality": .string(overall),
            "strengths": .array(strengths.map(JSONValue.string)),
            "concerns": .array(concerns.map(JSONValue.string)),
            "confidence": .string(confidence),
        ]
    }

    private func plan(
        source: SourceImage,
        target: String,
        tier: QualityTier?,
        explanations: [String]?
    ) -> XMPChangePlan {
        XMPChangePlan(
            status: .planned,
            targetXMPPath: "/photos/\(target)",
            targetRelativePath: target,
            pairScope: .union,
            sourceMembers: [
                SourceMemberPlan(
                    sourcePath: source.path,
                    sourceRelativePath: source.relativePath,
                    sourceFileName: source.fileName,
                    sourceType: source.detectedType,
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
}
