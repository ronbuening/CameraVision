import Foundation
import XCTest

@testable import AISidecarCore

final class NormalizedQualityGradingTests: XCTestCase {
    func testNormalizedPlannerAppendsQualityAfterDecisionsAndPlansScalars() throws {
        let asset = phase3Asset(index: 1, relativePath: "Bird.JPG")
        var input = phase3InputBatch(assets: [asset])
        input.rawSidecarInputs = [
            try rawInput(for: asset, assessment: goodAssessment(), createdAt: 1_700_000_000)
        ]
        let result = try plan(input: input, selectedAssetID: asset.assetID)

        let writePlan = try XCTUnwrap(result.writePlans.first)
        let plan = writePlan.xmpChangePlan
        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["Birds", "AI Quality good"])
        XCTAssertEqual(
            plan.hierarchicalKeywordsToAdd.map(\.term),
            ["Subject|Wildlife|Birds", "AI Quality|good"]
        )
        XCTAssertEqual(writePlan.flatKeywordProvenance.map(\.term), ["Birds"])
        XCTAssertEqual(writePlan.hierarchicalKeywordProvenance.map(\.term), ["Subject|Wildlife|Birds"])
        XCTAssertEqual(plan.qualityTier, .good)
        XCTAssertEqual(plan.ratingWrite?.plannedValue, "4")
        XCTAssertEqual(plan.labelWrite?.plannedValue, "Green")
        XCTAssertEqual(plan.urgencyWrite?.plannedValue, "2")
        XCTAssertEqual(plan.pickWrite?.plannedValue, "1")
        XCTAssertEqual(plan.goodWrite?.plannedValue, "true")
        XCTAssertEqual(plan.sourceMembers.first?.qualitySidecarPath, "/sidecars/Bird.JPG.quality.ai.json")
    }

    func testOnlySelectedGroupMembersContributeQualityAssessmentsAndProvenance() throws {
        let selected = phase3Asset(index: 1, relativePath: "Bird.JPG")
        let skipped = phase3Asset(index: 2, relativePath: "Other.JPG")
        let group = NormalizationSourceGroup(
            groupID: "group-000001",
            groupDirectory: "",
            groupBasename: "Bird",
            targetRelativePath: "Bird.xmp",
            memberAssetIDs: [selected.assetID, skipped.assetID],
            selectedAssetIDs: [selected.assetID],
            skippedAssetIDs: [skipped.assetID]
        )
        var input = phase3InputBatch(assets: [selected, skipped], groups: [group])
        input.rawSidecarInputs = [
            try rawInput(for: selected, assessment: goodAssessment(), createdAt: 1_700_000_000),
            try rawInput(for: skipped, assessment: rejectAssessment(), createdAt: 1_700_000_001),
        ]

        let result = try plan(input: input, selectedAssetID: selected.assetID)
        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)

        XCTAssertEqual(plan.qualityTier, .good)
        XCTAssertNotNil(plan.sourceMembers.first { $0.selected }?.qualitySidecarPath)
        XCTAssertNil(plan.sourceMembers.first { !$0.selected }?.qualitySidecarPath)
        XCTAssertFalse(plan.qualityExplanation?.contains(where: { $0.contains("tier=reject") }) == true)
    }

    func testBelowConfidenceAssessmentIsUngradedInNormalizedPlan() throws {
        let asset = phase3Asset(index: 1, relativePath: "Bird.JPG")
        var input = phase3InputBatch(assets: [asset])
        var assessment = goodAssessment()
        assessment["confidence"] = .string("low")
        input.rawSidecarInputs = [try rawInput(for: asset, assessment: assessment, createdAt: 1_700_000_000)]

        let result = try plan(input: input, selectedAssetID: asset.assetID)
        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)

        XCTAssertNil(plan.qualityTier)
        XCTAssertNil(plan.ratingWrite)
        XCTAssertEqual(plan.qualityExplanation?.first, "ungraded reason=below_minimum_confidence")
        XCTAssertTrue(plan.qualityExplanation?.contains("confidence=low") == true)
    }

    func testEnabledGradingMatchesPreC3NormalizedPlanFixtureBytes() throws {
        let asset = phase3Asset(index: 1, relativePath: "Bird.JPG")
        var input = phase3InputBatch(assets: [asset])
        input.rawSidecarInputs = [
            try rawInput(for: asset, assessment: goodAssessment(), createdAt: 1_700_000_000)
        ]
        let result = try plan(input: input, selectedAssetID: asset.assetID)
        let encoded = try JSONCoding.documentEncoder().encode(result.changePlan)
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "normalized-quality-grading-enabled-pre-c3",
                withExtension: "json",
                subdirectory: "xmp-plans"
            )
                ?? Bundle.module.url(
                    forResource: "normalized-quality-grading-enabled-pre-c3",
                    withExtension: "json"
                )
        )
        var expected = try Data(contentsOf: fixtureURL)
        if expected.last == UInt8(ascii: "\n") {
            expected.removeLast()
        }

        XCTAssertEqual(encoded, expected)
    }

    func testDisabledGradingMatchesPreQN3NormalizedPlanFixtureBytes() throws {
        let input = phase3InputBatch(["Bird.JPG"])
        var configuration = phase3Configuration(normalizationMode: .singleImage)
        configuration.outputDir = "/tmp/normalized"
        configuration.dryRun = true
        let decision = phase3DirectDecision(
            assetID: "asset-000001",
            canonicalPath: "Subject|Wildlife|Birds",
            decisionID: "decision-000001",
            observation: phase3Observation(id: "obs-000001", assetID: "asset-000001", term: "bird")
        )

        let result = try NormalizedXMPChangePlanner().plan(
            input: input,
            decisions: [decision],
            candidateSkips: [],
            configuration: configuration
        )
        let encoded = try JSONCoding.documentEncoder().encode(result.changePlan)
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "normalized-quality-grading-disabled-pre-qn3",
                withExtension: "json",
                subdirectory: "xmp-plans"
            )
                ?? Bundle.module.url(
                    forResource: "normalized-quality-grading-disabled-pre-qn3",
                    withExtension: "json"
                )
        )
        var expected = try Data(contentsOf: fixtureURL)
        if expected.last == UInt8(ascii: "\n") {
            expected.removeLast()
        }

        XCTAssertEqual(encoded, expected)
    }

    private func plan(
        input: NormalizationResolvedInputBatch,
        selectedAssetID: String
    ) throws -> NormalizedXMPChangePlanResult {
        var policy = QualityGradingPolicy(
            minimumConfidence: .medium,
            writeRating: true,
            writeLabel: true,
            writeUrgency: true,
            writeFlag: true,
            writeKeywords: true
        )
        policy.labelMap[.good] = "Green"
        policy.urgencyMap[.good] = 2
        policy.flagMap[.good] = .pick
        var configuration = phase3Configuration(normalizationMode: .singleImage)
        configuration.outputDir = "/tmp/normalized"
        configuration.qualityGrading = ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: .preserve,
            policy: policy
        )
        let decision = phase3DirectDecision(
            assetID: selectedAssetID,
            canonicalPath: "Subject|Wildlife|Birds",
            decisionID: "decision-000001"
        )
        return try NormalizedXMPChangePlanner().plan(
            input: input,
            decisions: [decision],
            candidateSkips: [],
            configuration: configuration,
            snapshotReader: { path in .empty(targetPath: path, exists: false) }
        )
    }

    private func rawInput(
        for asset: NormalizationSourceAsset,
        assessment: [String: JSONValue],
        createdAt: TimeInterval
    ) throws -> ResolvedRawSidecarInput {
        let source = SourceImage(
            path: asset.sourcePath ?? "/photos/\(asset.fileName)",
            relativePath: asset.sourceRelativePath,
            fileName: asset.fileName,
            fileExtension: URL(fileURLWithPath: asset.fileName).pathExtension,
            fileSize: 1,
            modifiedAt: Date(timeIntervalSince1970: createdAt),
            detectedType: asset.sourceType,
            identity: asset.sourceIdentity
        )
        let taggingPath = URL(fileURLWithPath: "/sidecars/\(asset.sourceRelativePath).ai.json")
        let qualityPath = URL(fileURLWithPath: "/sidecars/\(asset.sourceRelativePath).quality.ai.json")
        let tagging = try RawJSONSidecarDocument(
            sidecar: RawJSONSidecar(
                source: source,
                runConfiguration: .builtInDefaults,
                modelRuns: [],
                createdAt: Date(timeIntervalSince1970: createdAt)
            )
        )
        let quality = try RawJSONSidecarDocument(
            sidecar: RawJSONSidecar(
                source: source,
                runConfiguration: .builtInDefaults,
                modelRuns: [qualityRun(assessment: assessment)],
                createdAt: Date(timeIntervalSince1970: createdAt)
            )
        )
        return ResolvedRawSidecarInput(
            sidecarPath: taggingPath,
            document: tagging,
            qualitySidecarPath: qualityPath,
            qualityDocument: quality,
            sourcePath: asset.sourcePath.map { URL(fileURLWithPath: $0) },
            sourceIdentityStatus: .matched,
            relativePath: taggingPath.lastPathComponent,
            warnings: []
        )
    }

    private func qualityRun(assessment: [String: JSONValue]) -> ModelRunRecord {
        ModelRunRecord(
            inputRole: .wholeImage,
            model: "test:model",
            modelDigest: "sha256:test",
            runtime: "test",
            runtimeVersion: "1",
            promptVersion: "prompt.quality",
            promptSHA256: String(repeating: "a", count: 64),
            responseSchemaVersion: "schema.test",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "b", count: 64),
            rawResponseText: "fixture",
            parsedResponseJSON: .object(["quality_assessment": .object(assessment)]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func goodAssessment() -> [String: JSONValue] {
        [
            "composition": .string("strong"),
            "confidence": .string("high"),
            "concerns": .array([]),
            "focus": .string("strong"),
            "overall_effectiveness": .string("acceptable"),
            "strengths": .array([]),
        ]
    }

    private func rejectAssessment() -> [String: JSONValue] {
        [
            "composition": .string("problem"),
            "confidence": .string("high"),
            "concerns": .array([]),
            "focus": .string("problem"),
            "overall_effectiveness": .string("problem"),
            "strengths": .array([]),
        ]
    }
}
