import XCTest

@testable import AISidecarCore

final class NormalizedXMPChangePlanTests: XCTestCase {
    func testDuplicateSourceAssetIDThrowsStructuredValidationError() throws {
        var input = phase3InputBatch(["Bird.JPG"])
        let duplicate = try XCTUnwrap(input.sourceAssets.first)
        input.sourceAssets.append(duplicate)

        XCTAssertThrowsError(
            try NormalizedXMPChangePlanner().plan(
                input: input,
                decisions: [],
                candidateSkips: [],
                configuration: phase3Configuration()
            )
        ) { error in
            let sidecarError = error as? SidecarError
            XCTAssertEqual(sidecarError?.code, .validationFailed)
            XCTAssertEqual(sidecarError?.stage, .normalize)
            XCTAssertTrue(sidecarError?.message.contains(duplicate.assetID) == true)
        }
    }

    func testDuplicateSourceSidecarAssetIDThrowsStructuredValidationError() throws {
        var input = phase3InputBatch(["Bird.JPG"])
        let duplicate = try XCTUnwrap(input.sourceAISidecars.first)
        input.sourceAISidecars.append(duplicate)

        XCTAssertThrowsError(
            try NormalizedXMPChangePlanner().plan(
                input: input,
                decisions: [],
                candidateSkips: [],
                configuration: phase3Configuration()
            )
        ) { error in
            let sidecarError = error as? SidecarError
            XCTAssertEqual(sidecarError?.code, .validationFailed)
            XCTAssertEqual(sidecarError?.stage, .normalize)
            XCTAssertTrue(sidecarError?.message.contains(duplicate.sourceAssetID) == true)
        }
    }

    func testPlanDeduplicatesTermsAndRetainsDecisionProvenance() throws {
        let input = phase3InputBatch(["Bird.JPG"])
        var configuration = phase3Configuration(normalizationMode: .singleImage)
        configuration.outputDir = "/tmp/normalized"
        configuration.dryRun = true
        let observation = phase3Observation(id: "obs-000001", assetID: "asset-000001", term: "bird")
        let decisions = [
            phase3DirectDecision(
                assetID: "asset-000001",
                canonicalPath: "Subject|Wildlife|Birds",
                decisionID: "decision-000001",
                observation: observation
            ),
            phase3DirectDecision(
                assetID: "asset-000001",
                canonicalPath: "Subject|Wildlife|Birds",
                decisionID: "decision-000002"
            ),
            unnormalizedContextDecision(),
        ]

        let result = try NormalizedXMPChangePlanner().plan(
            input: input,
            decisions: decisions,
            candidateSkips: [],
            configuration: configuration
        )

        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)
        XCTAssertTrue(result.changePlan.dryRun)
        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["Birds", "Folder Mystery"])
        XCTAssertEqual(plan.hierarchicalKeywordsToAdd.map(\.term), ["Subject|Wildlife|Birds"])
        XCTAssertEqual(plan.targetXMPPath, "/tmp/normalized/Bird.xmp")

        let birds = try XCTUnwrap(
            result.writePlans.first?.flatKeywordProvenance.first {
                $0.term == "Birds"
            })
        XCTAssertEqual(birds.decisionIDs, ["decision-000001", "decision-000002"])
        XCTAssertEqual(birds.observationIDs, ["obs-000001"])
        XCTAssertEqual(birds.stages, [.directModelObservation])

        let mystery = try XCTUnwrap(
            result.writePlans.first?.flatKeywordProvenance.first {
                $0.term == "Folder Mystery"
            })
        XCTAssertEqual(mystery.candidateKinds, [.userContextUnnormalized])
        XCTAssertEqual(mystery.contextTypes, [.subject])
        XCTAssertTrue(
            result.writePlans.first?.hierarchicalKeywordProvenance.allSatisfy {
                !$0.term.contains("Folder Mystery")
            } == true)
    }

    func testSameBaseNameGroupPlansOneTargetAndHonorsPairScopeSelection() throws {
        let raw = phase3Asset(index: 1, relativePath: "set/Bird.NEF", sameBaseNameGroupID: "group-000001")
        let jpeg = phase3Asset(index: 2, relativePath: "set/Bird.JPG", sameBaseNameGroupID: "group-000001")
        let group = NormalizationSourceGroup(
            groupID: "group-000001",
            groupDirectory: "set",
            groupBasename: "Bird",
            targetRelativePath: "set/Bird.xmp",
            memberAssetIDs: [raw.assetID, jpeg.assetID],
            selectedAssetIDs: [raw.assetID],
            skippedAssetIDs: [jpeg.assetID]
        )
        var configuration = phase3Configuration(normalizationMode: .singleImage)
        configuration.outputDir = "/tmp/normalized"
        configuration.pairScope = .rawOnly
        let result = try NormalizedXMPChangePlanner().plan(
            input: phase3InputBatch(assets: [raw, jpeg], groups: [group]),
            decisions: [
                phase3DirectDecision(
                    assetID: raw.assetID,
                    canonicalPath: "Subject|Wildlife|Birds",
                    groupID: "group-000001",
                    decisionID: "decision-000001"
                )
            ],
            candidateSkips: [],
            configuration: configuration
        )

        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)
        XCTAssertEqual(result.changePlan.targetPlans.count, 1)
        XCTAssertEqual(plan.targetRelativePath, "set/Bird.xmp")
        XCTAssertEqual(plan.targetXMPPath, "/tmp/normalized/set/Bird.xmp")
        XCTAssertEqual(plan.pairScope, .rawOnly)
        XCTAssertEqual(plan.sourceMembers.map(\.selected), [true, false])
        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["Birds"])
    }

    func testCaseInsensitiveTargetCollisionsFailAffectedPlans() throws {
        let upper = phase3Asset(index: 1, relativePath: "Bird.JPG")
        let lower = phase3Asset(index: 2, relativePath: "bird.JPG")
        var configuration = phase3Configuration(normalizationMode: .singleImage)
        configuration.outputDir = "/tmp/normalized"

        let result = try NormalizedXMPChangePlanner().plan(
            input: phase3InputBatch(assets: [upper, lower]),
            decisions: [
                phase3DirectDecision(assetID: upper.assetID, canonicalPath: "Subject|Wildlife|Birds"),
                phase3DirectDecision(assetID: lower.assetID, canonicalPath: "Subject|Wildlife|Birds"),
            ],
            candidateSkips: [],
            configuration: configuration
        )

        XCTAssertEqual(result.changePlan.targetPlans.map(\.status), [.failed, .failed])
        XCTAssertEqual(
            result.changePlan.targetPlans.flatMap(\.failures).map(\.code),
            [.sidecarCollision, .sidecarCollision]
        )
    }

    func testSourceSidecarPathIsNilWhenNoRawSidecarExists() throws {
        var input = phase3InputBatch(["Bird.JPG"])
        input.sourceAISidecars = []

        let result = try NormalizedXMPChangePlanner().plan(
            input: input,
            decisions: [
                phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Subject|Wildlife|Birds")
            ],
            candidateSkips: [],
            configuration: phase3Configuration(normalizationMode: .singleImage)
        )

        XCTAssertNil(result.changePlan.targetPlans.first?.sourceMembers.first?.sourceSidecarPath)
    }

    func testAcceptedCoordinateDecisionFailsClosedAtFinalPlanBoundary() throws {
        var decision = phase3DirectDecision(
            assetID: "asset-000001",
            canonicalPath: "Subject|Imported",
            flatKeyword: "40, -79",
            decisionID: "decision-coordinate"
        )
        decision.hierarchicalKeyword = nil
        decision.exportHierarchicalKeyword = false

        let result = try NormalizedXMPChangePlanner().plan(
            input: phase3InputBatch(["Bird.JPG"]),
            decisions: [decision],
            candidateSkips: [],
            configuration: phase3Configuration(normalizationMode: .singleImage)
        )

        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)
        XCTAssertTrue(plan.flatKeywordsToAdd.isEmpty)
        XCTAssertTrue(plan.hierarchicalKeywordsToAdd.isEmpty)
        XCTAssertEqual(result.writePlans.first?.normalizationSkips.map(\.reason), [.coordinateLikeTerm])
        XCTAssertEqual(result.writePlans.first?.normalizationSkips.first?.term, "40, -79")
    }

    func testVisibleGPSObjectRemainsValidAtFinalPlanBoundary() throws {
        var decision = phase3DirectDecision(
            assetID: "asset-000001",
            canonicalPath: "Objects|Electronics|GPS Unit",
            flatKeyword: "GPS Unit",
            decisionID: "decision-gps-unit"
        )
        decision.hierarchicalKeyword = nil
        decision.exportHierarchicalKeyword = false

        let result = try NormalizedXMPChangePlanner().plan(
            input: phase3InputBatch(["Bird.JPG"]),
            decisions: [decision],
            candidateSkips: [],
            configuration: phase3Configuration(normalizationMode: .singleImage)
        )

        XCTAssertEqual(result.changePlan.targetPlans.first?.flatKeywordsToAdd.map(\.term), ["GPS Unit"])
        XCTAssertTrue(result.writePlans.first?.normalizationSkips.isEmpty == true)
    }

    func testGPSMetadataIsSkippedWhileVisibleGPSObjectStillExports() throws {
        var gpsUnit = phase3DirectDecision(
            assetID: "asset-000001",
            canonicalPath: "Objects|Electronics|GPS Unit",
            flatKeyword: "GPS Unit",
            decisionID: "decision-gps-unit"
        )
        gpsUnit.hierarchicalKeyword = nil
        gpsUnit.exportHierarchicalKeyword = false
        var gpsFix = phase3DirectDecision(
            assetID: "asset-000001",
            canonicalPath: "Workflow|Imported GPS",
            flatKeyword: "GPS fix",
            decisionID: "decision-gps-fix"
        )
        gpsFix.hierarchicalKeyword = nil
        gpsFix.exportHierarchicalKeyword = false

        let result = try NormalizedXMPChangePlanner().plan(
            input: phase3InputBatch(["Bird.JPG"]),
            decisions: [gpsUnit, gpsFix],
            candidateSkips: [],
            configuration: phase3Configuration(normalizationMode: .singleImage)
        )

        XCTAssertEqual(result.changePlan.targetPlans.first?.flatKeywordsToAdd.map(\.term), ["GPS Unit"])
        XCTAssertEqual(result.writePlans.first?.normalizationSkips.map(\.reason), [.coordinateLikeTerm])
        XCTAssertEqual(result.writePlans.first?.normalizationSkips.first?.term, "GPS fix")
    }

    func testPlannerNeverExportsForwardUnknownDecisionEvenIfPublicFlagsAreMutated() throws {
        let original = phase3DirectDecision(
            assetID: "asset-000001",
            canonicalPath: "Subject|Wildlife|Birds"
        )
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        object["stage"] = "future_stage"
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var decoded = try JSONDecoder().decode(PerAssetNormalizationDecision.self, from: data)
        XCTAssertTrue(decoded.isForwardCompatUnknown)

        decoded.status = .accepted
        decoded.exportFlatKeyword = true
        decoded.exportHierarchicalKeyword = true
        let result = try NormalizedXMPChangePlanner().plan(
            input: phase3InputBatch(["Bird.JPG"]),
            decisions: [decoded],
            candidateSkips: [],
            configuration: phase3Configuration(normalizationMode: .singleImage)
        )

        XCTAssertTrue(result.changePlan.targetPlans[0].flatKeywordsToAdd.isEmpty)
        XCTAssertTrue(result.changePlan.targetPlans[0].hierarchicalKeywordsToAdd.isEmpty)
    }

    private func unnormalizedContextDecision() -> PerAssetNormalizationDecision {
        PerAssetNormalizationDecision(
            decisionID: "decision-000003",
            assetID: "asset-000001",
            stage: .userSessionContext,
            status: .accepted,
            candidateKind: .userContextUnnormalized,
            flatKeyword: "Folder Mystery",
            sourceText: "Folder Mystery",
            contextType: .subject,
            directApplyPolicy: .flatOnly,
            exportFlatKeyword: true,
            exportHierarchicalKeyword: false,
            supportUnits: 1,
            supportingAssetIDs: ["asset-000001"],
            governingRule: "unknown_session_context_flat_only",
            skipReasons: [.unknownSessionContextFlatOnly]
        )
    }
}
