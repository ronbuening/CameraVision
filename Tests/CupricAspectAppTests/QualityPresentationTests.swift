import AISidecarCore
import Foundation
import XCTest

@testable import CupricAspectApp

final class QualityPresentationTests: XCTestCase {
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

    func testLegacyPlanHasNoQualityPresentation() throws {
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
    }

    func testReviewQualitySummaryCountsCorePresentationRows() {
        let record = QualityAssessmentRecord(
            role: .wholeImage,
            promptVersion: "prompt/quality",
            criteria: [.focus: .strong],
            overall: .strong,
            strengths: ["sharp detail"],
            concerns: [],
            confidence: .high
        )
        let rows = [
            "good": ReviewAssetQualityPresentation(
                records: [record],
                issueDiagnostics: ["malformed_block"],
                tier: .good,
                explanations: ["tier=good"],
                ungradedReason: nil
            ),
            "ungraded": ReviewAssetQualityPresentation(
                records: [record],
                issueDiagnostics: ["missing_overall", "unknown_criterion: future"],
                tier: nil,
                explanations: ["ungraded reason=below_minimum_confidence"],
                ungradedReason: "ungraded reason=below_minimum_confidence"
            ),
            "reject": ReviewAssetQualityPresentation(
                records: [],
                issueDiagnostics: [],
                tier: .reject,
                explanations: ["tier=reject"],
                ungradedReason: nil
            ),
        ]

        XCTAssertEqual(
            ReviewModel.qualitySummary(for: rows),
            ReviewModel.QualitySummary(
                assessedAssetCount: 2,
                tierCounts: [.good: 1, .reject: 1],
                ungradedAssetCount: 1,
                issueCount: 3
            )
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

}
