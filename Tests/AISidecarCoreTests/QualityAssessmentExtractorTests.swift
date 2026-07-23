import Foundation
import XCTest

@testable import AISidecarCore

final class QualityAssessmentExtractorTests: XCTestCase {
    func testExtractsBothRolesFromCombinedSidecar() throws {
        let input = try makeInput(
            primaryRuns: [
                modelRun(role: .wholeImage, response: try fixture("whole_image_with_quality_valid")),
                modelRun(role: .subjectIsolated, response: try fixture("subject_isolated_with_quality_valid")),
            ],
            primaryProfile: .taggingWithQuality
        )

        let result = QualityAssessmentExtractor.extract(from: input)

        XCTAssertEqual(result.sourceImagePath, "/photos/Bird.JPG")
        XCTAssertEqual(result.records.map(\.role), [.wholeImage, .subjectIsolated])
        let whole = try XCTUnwrap(result.records.first)
        XCTAssertEqual(whole.criteria[.focus], .strong)
        XCTAssertEqual(whole.criteria[.momentOrExpression], .unrated)
        XCTAssertEqual(whole.overall, .acceptable)
        XCTAssertEqual(whole.confidence, .high)
        XCTAssertEqual(whole.strengths, ["sharp eye detail", "warm directional light"])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testQualitySiblingSuppliesAssessmentBesideTaggingDocument() throws {
        let qualityResponse = try fixture("whole_image_quality_only_valid")
        let input = try makeInput(
            primaryRuns: [],
            primaryProfile: .tagging,
            qualityRuns: [modelRun(role: .wholeImage, response: qualityResponse)]
        )

        let result = QualityAssessmentExtractor.extract(from: input)

        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records.first?.role, .wholeImage)
        XCTAssertEqual(result.records.first?.promptVersion, "prompt.whole_image")
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testMalformedBlockProducesIssueWithoutThrowing() throws {
        let response: JSONValue = .object(["quality_assessment": .string("bad")])
        let input = try makeInput(
            primaryRuns: [modelRun(role: .wholeImage, response: response)],
            primaryProfile: .taggingWithQuality
        )

        let result = QualityAssessmentExtractor.extract(from: input)

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.issues, [.malformedBlock])
        XCTAssertEqual(result.issues.map(\.code), [.malformedBlock])
    }

    func testBatchExtractionDeduplicatesRepeatedMalformedBlockIssue() throws {
        let response: JSONValue = .object(["quality_assessment": .string("bad")])
        let input = try makeInput(
            primaryRuns: [modelRun(role: .wholeImage, response: response)],
            primaryProfile: .taggingWithQuality,
            qualityRuns: [modelRun(role: .wholeImage, response: response)]
        )

        let selection = QualityAssessmentExtractor.extractBatch(from: [input])

        XCTAssertTrue(selection.recordsByRole.isEmpty)
        XCTAssertEqual(selection.issues, [.malformedBlock])
    }

    func testPresentMalformedBlockUnderTaggingProfileIsReported() throws {
        let input = try makeInput(
            primaryRuns: [
                modelRun(
                    role: .wholeImage,
                    response: .object(["quality_assessment": .string("bad")])
                )
            ],
            primaryProfile: .tagging
        )

        let result = QualityAssessmentExtractor.extract(from: input)

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.issues, [.malformedBlock])
    }

    func testPlainTaggingResponseWithoutQualityBlockRemainsSilent() throws {
        let input = try makeInput(
            primaryRuns: [
                modelRun(
                    role: .wholeImage,
                    response: .object(["main_subjects": .array([])])
                )
            ],
            primaryProfile: .tagging
        )

        let result = QualityAssessmentExtractor.extract(from: input)

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testUnknownCriterionIsDroppedAndReported() throws {
        var assessment = try qualityObject(from: try fixture("whole_image_quality_only_valid"))
        assessment["future_aesthetic_signal"] = .string("strong")
        let input = try input(withWholeAssessment: assessment)

        let result = QualityAssessmentExtractor.extract(from: input)

        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records.first?.criteria.count, 7)
        XCTAssertEqual(result.issues, [.unknownCriterion("future_aesthetic_signal")])
    }

    func testMissingOverallDropsRecordAndReportsIssue() throws {
        var assessment = try qualityObject(from: try fixture("whole_image_quality_only_valid"))
        assessment.removeValue(forKey: "overall_effectiveness")

        let result = QualityAssessmentExtractor.extract(from: try input(withWholeAssessment: assessment))

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.issues, [.missingOverall])
    }

    func testInvalidCriterionLevelIsDroppedButRecordSurvives() throws {
        var assessment = try qualityObject(from: try fixture("whole_image_quality_only_valid"))
        assessment["focus"] = .string("excellent")

        let result = QualityAssessmentExtractor.extract(from: try input(withWholeAssessment: assessment))

        XCTAssertEqual(result.records.count, 1)
        XCTAssertNil(result.records.first?.criteria[.focus])
        XCTAssertEqual(result.issues, [.invalidLevel(field: "focus", value: "excellent")])
    }

    func testMissingConfidenceDropsRecordAndReportsInvalidLevel() throws {
        var assessment = try qualityObject(from: try fixture("whole_image_quality_only_valid"))
        assessment.removeValue(forKey: "confidence")

        let result = QualityAssessmentExtractor.extract(from: try input(withWholeAssessment: assessment))

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.issues, [.invalidLevel(field: "confidence", value: "<missing>")])
    }

    func testNewestValidRunWinsPerRole() throws {
        var earlier = try qualityObject(from: try fixture("whole_image_quality_only_valid"))
        earlier["overall_effectiveness"] = .string("problem")
        var newer = earlier
        newer["overall_effectiveness"] = .string("strong")
        let input = try makeInput(
            primaryRuns: [
                modelRun(role: .wholeImage, response: .object(["quality_assessment": .object(earlier)]), prompt: "old"),
                modelRun(role: .wholeImage, response: .object(["quality_assessment": .object(newer)]), prompt: "new"),
            ],
            primaryProfile: .qualityOnly
        )

        let result = QualityAssessmentExtractor.extract(from: input)

        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records.first?.overall, .strong)
        XCTAssertEqual(result.records.first?.promptVersion, "new")
    }

    func testBatchExtractionUsesDeterministicPathTieBreakForEqualCreationDates() throws {
        var earlierPathAssessment = try qualityObject(from: try fixture("whole_image_quality_only_valid"))
        earlierPathAssessment["overall_effectiveness"] = .string("problem")
        var laterPathAssessment = earlierPathAssessment
        laterPathAssessment["overall_effectiveness"] = .string("strong")
        let input = try makeInput(
            primaryRuns: [
                modelRun(
                    role: .wholeImage,
                    response: .object(["quality_assessment": .object(earlierPathAssessment)]),
                    prompt: "path-a"
                )
            ],
            primaryProfile: .qualityOnly,
            qualityRuns: [
                modelRun(
                    role: .wholeImage,
                    response: .object(["quality_assessment": .object(laterPathAssessment)]),
                    prompt: "path-B"
                )
            ],
            primaryCreatedAt: 100,
            qualityCreatedAt: 100,
            primaryPath: "/sidecars/a.ai.json",
            qualityPath: "/sidecars/B.quality.ai.json"
        )

        let selection = QualityAssessmentExtractor.extractBatch(from: [input])

        XCTAssertEqual(selection.contributors.map(\.path), ["/sidecars/a.ai.json", "/sidecars/B.quality.ai.json"])
        XCTAssertEqual(selection.recordsByRole[.wholeImage]?.overall, .strong)
        XCTAssertEqual(selection.recordsByRole[.wholeImage]?.promptVersion, "path-B")
    }

    func testCandidateExtractorIgnoresQualityAssessmentBlock() throws {
        let combined = try fixture("whole_image_with_quality_valid")
        guard case .object(var withoutQuality) = combined else {
            return XCTFail("Expected object fixture")
        }
        withoutQuality.removeValue(forKey: "quality_assessment")
        let withInput = try makeInput(
            primaryRuns: [modelRun(role: .wholeImage, response: combined)],
            primaryProfile: .taggingWithQuality
        )
        let withoutInput = try makeInput(
            primaryRuns: [modelRun(role: .wholeImage, response: .object(withoutQuality))],
            primaryProfile: .taggingWithQuality
        )
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.minConfidence = .low
        configuration.allowSpecificTags = true

        let withQuality = CandidateExtractor().extract(from: withInput, configuration: configuration)
        let without = CandidateExtractor().extract(from: withoutInput, configuration: configuration)

        XCTAssertEqual(withQuality, without)
    }

    private func input(withWholeAssessment assessment: [String: JSONValue]) throws -> ResolvedRawSidecarInput {
        try makeInput(
            primaryRuns: [
                modelRun(role: .wholeImage, response: .object(["quality_assessment": .object(assessment)]))
            ],
            primaryProfile: .qualityOnly
        )
    }

    private func makeInput(
        primaryRuns: [ModelRunRecord],
        primaryProfile: ModelTaskProfile,
        qualityRuns: [ModelRunRecord]? = nil,
        primaryCreatedAt: TimeInterval = 100,
        qualityCreatedAt: TimeInterval = 200,
        primaryPath: String = "/sidecars/Bird.JPG.ai.json",
        qualityPath: String = "/sidecars/Bird.JPG.quality.ai.json"
    ) throws -> ResolvedRawSidecarInput {
        let source = SourceImage(
            path: "/photos/Bird.JPG",
            relativePath: "Bird.JPG",
            fileName: "Bird.JPG",
            fileExtension: "JPG",
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: .jpg,
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
        )
        let primarySidecar = RawJSONSidecar(
            source: source,
            runConfiguration: ResolvedRunConfiguration.builtInDefaults.with(taskProfile: primaryProfile),
            modelRuns: primaryRuns,
            createdAt: Date(timeIntervalSince1970: primaryCreatedAt)
        )
        let primaryDocument = try RawJSONSidecarDocument(sidecar: primarySidecar)
        let primaryURL = URL(fileURLWithPath: primaryPath)
        if let qualityRuns {
            let qualitySidecar = RawJSONSidecar(
                source: source,
                runConfiguration: ResolvedRunConfiguration.builtInDefaults.with(taskProfile: .qualityOnly),
                modelRuns: qualityRuns,
                createdAt: Date(timeIntervalSince1970: qualityCreatedAt)
            )
            return ResolvedRawSidecarInput(
                sidecarPath: primaryURL,
                document: primaryDocument,
                qualitySidecarPath: URL(fileURLWithPath: qualityPath),
                qualityDocument: try RawJSONSidecarDocument(sidecar: qualitySidecar),
                sourcePath: URL(fileURLWithPath: source.path),
                sourceIdentityStatus: .matched,
                relativePath: "Bird.JPG.ai.json",
                warnings: []
            )
        }
        return ResolvedRawSidecarInput(
            sidecarPath: primaryURL,
            document: primaryDocument,
            sourcePath: URL(fileURLWithPath: source.path),
            sourceIdentityStatus: .matched,
            relativePath: "Bird.JPG.ai.json",
            warnings: []
        )
    }

    private func modelRun(
        role: ModelInputRole,
        response: JSONValue,
        prompt: String? = nil
    ) -> ModelRunRecord {
        ModelRunRecord(
            inputRole: role,
            model: "test:model",
            modelDigest: "sha256:test",
            runtime: "test",
            runtimeVersion: "1",
            promptVersion: prompt ?? "prompt.\(role.rawValue)",
            promptSHA256: String(repeating: "b", count: 64),
            responseSchemaVersion: "schema.test",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "c", count: 64),
            rawResponseText: "fixture",
            parsedResponseJSON: response,
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "model-responses")
                ?? Bundle.module.url(forResource: name, withExtension: "json")
        )
        return try JSONCoding.decoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    private func qualityObject(from response: JSONValue) throws -> [String: JSONValue] {
        try XCTUnwrap(response.objectValue?["quality_assessment"]?.objectValue)
    }
}
