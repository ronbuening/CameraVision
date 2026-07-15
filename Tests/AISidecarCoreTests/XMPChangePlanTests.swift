import Foundation
import XCTest

@testable import AISidecarCore

final class XMPChangePlanTests: XCTestCase {
    func testDryRunDocumentContainsPlanningMetadataWarningsAndValidationIntent() throws {
        let input = try resolvedInput(warnings: [
            SidecarError(
                code: .sourceIdentityMismatch,
                stage: .scan,
                message: "Source identity mismatch for fixture.",
                recoverable: true
            )
        ])
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.dryRun = true
        configuration.xmpConflictPolicy = .backupAndMerge
        configuration.backupSidecars = true

        let document = XMPChangePlanner().plan(
            inputBatch: RawJSONSidecarInputBatch(
                inputs: [input],
                failures: [
                    RawJSONSidecarInputFailure(
                        sidecarPath: URL(fileURLWithPath: "/sidecars/Bad.JPG.ai.json"),
                        relativePath: "Bad.JPG.ai.json",
                        error: SidecarError(
                            code: .schemaUnsupported,
                            stage: .scan,
                            message: "Unsupported fixture schema.",
                            recoverable: true
                        )
                    )
                ]),
            extractionResults: [extraction(for: input)],
            configuration: configuration
        )

        XCTAssertEqual(document.schemaVersion, XMPExportSchemaIdentifiers.changePlan)
        XCTAssertTrue(document.dryRun)
        XCTAssertEqual(document.inputFailures.map(\.error.code), [.schemaUnsupported])

        let plan = try XCTUnwrap(document.targetPlans.first)
        XCTAssertEqual(plan.status, .planned)
        XCTAssertEqual(plan.existingPolicy, .backupAndMerge)
        XCTAssertEqual(plan.backupPlan.backupSidecars, true)
        XCTAssertEqual(plan.backupPlan.backupRequiredBeforeMerge, true)
        XCTAssertEqual(plan.validationPlan, .phase2Default)
        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["wading bird"])
        XCTAssertEqual(plan.hierarchicalKeywordsToAdd.map(\.term), ["wading bird"])
        XCTAssertEqual(plan.skippedCandidates.map(\.reason), [.belowConfidenceThreshold])
        XCTAssertEqual(plan.candidateExtractionIssues.map(\.reason), [.malformedCandidate])
        XCTAssertEqual(plan.sourceVerificationWarnings.map(\.code), [.sourceIdentityMismatch])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let encoded = String(data: try encoder.encode(document), encoding: .utf8)
        XCTAssertTrue(encoded?.contains("\"schema_version\" : \"ai-sidecar-xmp-change-plan/1.0\"") == true)
        XCTAssertTrue(encoded?.contains("\"backup_plan\"") == true)
        XCTAssertTrue(encoded?.contains("\"source_field\"") == true)
        XCTAssertTrue(encoded?.contains("\"normalized_term\"") == true)
        XCTAssertTrue(encoded?.contains("\"validation_plan\"") == true)
    }

    func testFailedCountCountsInputFailuresAndFailureBearingTargetPlans() {
        let failure = SidecarError(
            code: .validationFailed,
            stage: .normalize,
            message: "Planned target failure.",
            recoverable: false
        )
        let document = XMPChangePlanDocument(
            dryRun: true,
            targetPlans: [
                minimalTargetPlan(status: .planned, failures: []),
                minimalTargetPlan(status: .failed, failures: [failure]),
                minimalTargetPlan(status: .planned, failures: [failure]),
            ],
            inputFailures: [
                XMPChangePlanInputFailure(
                    sidecarPath: "/sidecars/Bad.JPG.ai.json",
                    relativePath: "Bad.JPG.ai.json",
                    error: failure
                )
            ]
        )

        XCTAssertEqual(document.failedCount, 3)
        XCTAssertEqual(
            XMPChangePlanDocument(dryRun: true, targetPlans: [], inputFailures: []).failedCount,
            0
        )
    }

    private func minimalTargetPlan(status: XMPTargetPlanStatus, failures: [SidecarError]) -> XMPChangePlan {
        XMPChangePlan(
            status: status,
            targetXMPPath: "/photos/Bird.xmp",
            targetRelativePath: "Bird.xmp",
            pairScope: .union,
            sourceMembers: [],
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
            failures: failures
        )
    }

    func testDuplicateExtractionSidecarBecomesInputFailureAndKeepsFirstResult() throws {
        let input = try resolvedInput(warnings: [])
        let first = extraction(for: input)

        let document = XMPChangePlanner().plan(
            inputBatch: RawJSONSidecarInputBatch(inputs: [input], failures: []),
            extractionResults: [first, first],
            configuration: .builtInDefaults
        )

        let failure = try XCTUnwrap(document.inputFailures.first)
        XCTAssertEqual(failure.sidecarPath, first.sourceSidecar)
        XCTAssertEqual(failure.error.code, .validationFailed)
        XCTAssertTrue(failure.error.message.contains(first.sourceSidecar))
        XCTAssertEqual(document.targetPlans.count, 1)
        XCTAssertEqual(document.targetPlans.first?.flatKeywordsToAdd.map(\.term), ["wading bird"])
    }

    private func resolvedInput(warnings: [SidecarError]) throws -> ResolvedRawSidecarInput {
        let source = SourceImage(
            path: "/photos/Bird.JPG",
            relativePath: "Bird.JPG",
            fileName: "Bird.JPG",
            fileExtension: "JPG",
            fileSize: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: .jpg,
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
        )
        return ResolvedRawSidecarInput(
            sidecarPath: URL(fileURLWithPath: "/sidecars/Bird.JPG.ai.json"),
            document: try RawJSONSidecarDocument(
                sidecar: RawJSONSidecar(
                    source: source,
                    runConfiguration: .builtInDefaults
                )),
            sourcePath: URL(fileURLWithPath: source.path),
            sourceIdentityStatus: .mismatched,
            relativePath: "Bird.JPG.ai.json",
            warnings: warnings
        )
    }

    private func extraction(for input: ResolvedRawSidecarInput) -> CandidateExtractionResult {
        let accepted = candidate(term: "wading bird", input: input)
        let skipped = candidate(term: "low confidence", input: input)
        let keyword = ExportableKeyword(
            term: accepted.normalizedTerm,
            normalizedKey: KeywordTextNormalizer.deduplicationKey(for: accepted.normalizedTerm),
            candidates: [accepted]
        )
        return CandidateExtractionResult(
            sourceSidecar: input.sidecarPath.standardizedFileURL.path,
            sourceImage: input.document.sidecar.source.path,
            extractedCandidates: [accepted, skipped],
            flatKeywords: [keyword],
            hierarchicalKeywords: [keyword],
            skippedCandidates: [SkippedCandidate(reason: .belowConfidenceThreshold, candidate: skipped)],
            issues: [
                CandidateExtractionIssue(
                    reason: .malformedCandidate,
                    sourceSidecar: input.sidecarPath.standardizedFileURL.path,
                    sourceImage: input.document.sidecar.source.path,
                    modelRunIndex: 0,
                    sourceField: .proposedKeywords,
                    candidateIndex: 1,
                    message: "Malformed fixture candidate."
                )
            ]
        )
    }

    private func candidate(term: String, input: ResolvedRawSidecarInput) -> ExtractedCandidate {
        let normalized = KeywordTextNormalizer.normalize(term)
        return ExtractedCandidate(
            term: term,
            normalizedTerm: normalized,
            confidence: .high,
            evidence: "fixture",
            provenance: CandidateProvenance(
                sourceField: .proposedKeywords,
                inputRole: .wholeImage,
                sourceSidecar: input.sidecarPath.standardizedFileURL.path,
                sourceImage: input.document.sidecar.source.path,
                modelRunIndex: 0
            )
        )
    }
}
