import XCTest

@testable import AISidecarCore

final class XMPChangePlanAssemblerTests: XCTestCase {
    func testAssembleBuildsSharedScaffoldAndPreservesCallerOrder() {
        let assembler = XMPChangePlanAssembler()
        let firstFailure = error("first failure")
        let secondFailure = error("second failure")
        let firstWarning = error("first warning")
        let secondWarning = error("second warning")
        let flat = PlannedKeyword(term: "zeta", normalizedKey: "zeta", candidates: [])
        let hierarchical = PlannedKeyword(term: "Root|alpha", normalizedKey: "root|alpha", candidates: [])

        let plan = assembler.assemble(
            XMPChangePlanAssembler.TargetContent(
                targetXMPPath: "/photos/Bird.xmp",
                targetRelativePath: "Bird.xmp",
                sourceMembers: [],
                flatKeywords: [flat],
                hierarchicalKeywords: [hierarchical],
                skippedCandidates: [],
                candidateExtractionIssues: [],
                sourceVerificationWarnings: [firstWarning, secondWarning],
                groupWarnings: [secondWarning, firstWarning],
                failures: [firstFailure, secondFailure],
                gradingInputs: []
            ),
            settings: XMPChangePlanAssembler.Settings(
                pairScope: .rawOnly,
                conflictPolicy: .backupAndMerge,
                backupSidecars: false,
                writeFlatKeywords: true,
                writeHierarchicalKeywords: true,
                qualityGrading: .builtInDefaults
            ),
            snapshotReader: nil
        )

        XCTAssertEqual(plan.status, .failed)
        XCTAssertEqual(plan.targetXMPPath, "/photos/Bird.xmp")
        XCTAssertEqual(plan.targetRelativePath, "Bird.xmp")
        XCTAssertEqual(plan.pairScope, .rawOnly)
        XCTAssertEqual(plan.flatKeywordsToAdd, [flat])
        XCTAssertEqual(plan.hierarchicalKeywordsToAdd, [hierarchical])
        XCTAssertEqual(plan.sourceVerificationWarnings, [firstWarning, secondWarning])
        XCTAssertEqual(plan.groupWarnings, [secondWarning, firstWarning])
        XCTAssertEqual(plan.failures, [firstFailure, secondFailure])
        XCTAssertEqual(
            plan.backupPlan,
            BackupPlan(backupSidecars: false, backupRequiredBeforeMerge: true, conflictPolicy: .backupAndMerge)
        )
        XCTAssertEqual(plan.validationPlan, .phase2Default)
    }

    func testMergeKeywordsSupportsStableAndNormalizedPlannerOrdering() {
        let assembler = XMPChangePlanAssembler()
        let late = candidate(term: "late", sidecar: "/sidecars/z.ai.json", modelRunIndex: 1)
        let early = candidate(term: "early", sidecar: "/sidecars/a.ai.json", modelRunIndex: 0)
        let contributions = [
            PlannedKeyword(term: "zeta", normalizedKey: "same", candidates: [late]),
            PlannedKeyword(term: "ignored spelling", normalizedKey: "same", candidates: [early]),
            PlannedKeyword(term: "alpha", normalizedKey: "alpha", candidates: []),
        ]

        let stable = assembler.mergeKeywords(contributions)
        let sorted = assembler.mergeKeywords(
            contributions,
            keywordOrder: .termSorted,
            candidateOrder: .provenanceSorted
        )

        XCTAssertEqual(stable.map(\.term), ["zeta", "alpha"])
        XCTAssertEqual(stable.first?.candidates.map(\.term), ["late", "early"])
        XCTAssertEqual(sorted.map(\.term), ["alpha", "zeta"])
        XCTAssertEqual(sorted.last?.candidates.map(\.term), ["early", "late"])
    }

    func testSourceMemberPlanUsesSharedPairScopeAndQualityPathRules() {
        let assembler = XMPChangePlanAssembler()
        let content = XMPChangePlanAssembler.SourceMemberContent(
            sourcePath: "/photos/Bird.RAF",
            sourceRelativePath: "Bird.RAF",
            sourceFileName: "Bird.RAF",
            sourceType: .raf,
            sourceSidecarPath: "/sidecars/Bird.RAF.ai.json",
            sourceSidecarRelativePath: "Bird.RAF.ai.json",
            sourceIdentityStatus: .matched,
            pairKind: .rawLike,
            selected: false,
            flatKeywordContributionCount: 0,
            hierarchicalKeywordContributionCount: 0,
            qualityInput: nil,
            includesQualityProvenance: true
        )

        let plan = assembler.sourceMemberPlan(content, pairScope: .jpegOnly)

        XCTAssertFalse(plan.selected)
        XCTAssertEqual(plan.skipReason, XMPSourceMemberSkipReason.pairScopeJPEGOnly)
        XCTAssertNil(plan.qualitySidecarPath)
    }

    private func error(_ message: String) -> SidecarError {
        SidecarError(
            code: .validationFailed,
            stage: .write,
            message: message,
            recoverable: true
        )
    }

    private func candidate(term: String, sidecar: String, modelRunIndex: Int) -> ExtractedCandidate {
        ExtractedCandidate(
            term: term,
            normalizedTerm: term,
            confidence: .high,
            evidence: nil,
            provenance: CandidateProvenance(
                sourceField: .mainSubjects,
                inputRole: .wholeImage,
                sourceSidecar: sidecar,
                sourceImage: "/photos/Bird.JPG",
                modelRunIndex: modelRunIndex
            )
        )
    }
}
