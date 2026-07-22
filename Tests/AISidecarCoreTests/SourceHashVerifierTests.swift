import Foundation
import XCTest

@testable import AISidecarCore

final class SourceHashVerifierTests: XCTestCase {
    func testSelectedSourcePathsIncludeOnlySelectedNonNilPathsDedupedAndSorted() {
        let plan = makePlan(
            members: [
                makeMember(sourcePath: "/photos/z.JPG", selected: true),
                makeMember(sourcePath: "/photos/a.JPG", selected: true),
                makeMember(sourcePath: "/photos/z.JPG", selected: true),
                makeMember(sourcePath: "/photos/skipped.JPG", selected: false),
                makeMember(sourcePath: nil, selected: true),
            ]
        )

        XCTAssertEqual(
            SourceHashVerifier.selectedSourcePaths(for: plan),
            ["/photos/a.JPG", "/photos/z.JPG"]
        )
    }

    func testMissingBaselineEntryIsRetainedAndReportedAfterVerification() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("A.JPG")
        let missing = root.appendingPathComponent("B.JPG")
        try Data("existing".utf8).write(to: existing)
        let verifier = SourceHashVerifier(
            plan: makePlan(
                members: [
                    makeMember(sourcePath: missing.path, selected: true),
                    makeMember(sourcePath: existing.path, selected: true),
                ]
            )
        )

        let outcome = verifier.verify()

        XCTAssertEqual(outcome.checks.map(\.sourcePath), [existing.path, missing.path])
        XCTAssertTrue(outcome.checks[0].unchanged)
        XCTAssertNil(outcome.checks[1].beforeSHA256)
        XCTAssertNil(outcome.checks[1].afterSHA256)
        XCTAssertFalse(outcome.checks[1].unchanged)
        XCTAssertEqual(
            outcome.checks[1].error?.message,
            "Unable to read source image before XMP export: \(missing.path)"
        )
        XCTAssertEqual(outcome.errors, [outcome.checks[1].error].compactMap { $0 })
    }

    func testVerificationReportsMutationAndPostBaselineReadFailureInPathOrder() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let mutated = root.appendingPathComponent("A.JPG")
        let removed = root.appendingPathComponent("B.JPG")
        try Data("before-a".utf8).write(to: mutated)
        try Data("before-b".utf8).write(to: removed)
        let verifier = SourceHashVerifier(
            plan: makePlan(
                members: [
                    makeMember(sourcePath: removed.path, selected: true),
                    makeMember(sourcePath: mutated.path, selected: true),
                ]
            )
        )

        try Data("after-a".utf8).write(to: mutated)
        try FileManager.default.removeItem(at: removed)
        let outcome = verifier.verify()

        XCTAssertEqual(outcome.checks.map(\.sourcePath), [mutated.path, removed.path])
        XCTAssertEqual(outcome.errors.count, 2)
        XCTAssertEqual(outcome.errors[0].message, "Source image hash changed during XMP export: \(mutated.path)")
        XCTAssertTrue(
            outcome.errors[1].message.hasPrefix(
                "Unable to verify source image hash after XMP export for \(removed.path): "
            )
        )
        XCTAssertFalse(outcome.checks[0].unchanged)
        XCTAssertNotEqual(outcome.checks[0].beforeSHA256, outcome.checks[0].afterSHA256)
        XCTAssertFalse(outcome.checks[1].unchanged)
        XCTAssertNil(outcome.checks[1].afterSHA256)
        XCTAssertEqual(outcome.checks[1].error, outcome.errors[1])
    }

    private func makePlan(members: [SourceMemberPlan]) -> XMPChangePlan {
        XMPChangePlan(
            status: .planned,
            targetXMPPath: "/exports/Bird.xmp",
            targetRelativePath: "Bird.xmp",
            pairScope: .union,
            sourceMembers: members,
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
            failures: []
        )
    }

    private func makeMember(sourcePath: String?, selected: Bool) -> SourceMemberPlan {
        SourceMemberPlan(
            sourcePath: sourcePath,
            sourceRelativePath: sourcePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "missing.JPG",
            sourceFileName: sourcePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "missing.JPG",
            sourceType: .jpg,
            sourceSidecarPath: nil,
            sourceSidecarRelativePath: nil,
            sourceIdentityStatus: .matched,
            pairKind: .jpeg,
            selected: selected,
            skipReason: nil,
            flatKeywordContributionCount: 0,
            hierarchicalKeywordContributionCount: 0
        )
    }
}
