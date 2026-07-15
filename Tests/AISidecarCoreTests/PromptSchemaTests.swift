import CryptoKit
import Foundation
import XCTest
@testable import AISidecarCore

final class PromptSchemaTests: XCTestCase {
    func testPromptsResolveVersionsAndDeterministicHashes() throws {
        let whole = try PromptRegistry.prompt(for: .wholeImage)
        let subject = try PromptRegistry.prompt(for: .subjectIsolated)

        XCTAssertEqual(whole.version, "aisidecar.prompt.whole_image/1.5.0")
        XCTAssertEqual(subject.version, "aisidecar.prompt.subject_isolated/1.5.0")
        XCTAssertTrue(whole.text.hasPrefix("PROMPT_VERSION: \(whole.version)\n"))
        XCTAssertTrue(subject.text.hasPrefix("PROMPT_VERSION: \(subject.version)\n"))
        XCTAssertTrue(whole.text.hasSuffix("\n"))
        XCTAssertFalse(whole.text.hasSuffix("\n\n"))
        XCTAssertTrue(subject.text.hasSuffix("\n"))
        XCTAssertFalse(subject.text.hasSuffix("\n\n"))
        XCTAssertEqual(whole.sha256, sha256(whole.text))
        XCTAssertEqual(subject.sha256, sha256(subject.text))
    }

    func testQualityPromptResourcesHaveVersionedHeadersAndStableHashes() throws {
        let expectedVersions = [
            ("whole_image_v1.6.0", "aisidecar.prompt.whole_image/1.6.0"),
            ("subject_isolated_v1.6.0", "aisidecar.prompt.subject_isolated/1.6.0"),
            ("whole_image_quality_v1.0.0", "aisidecar.prompt.whole_image_quality/1.0.0"),
            ("subject_isolated_quality_v1.0.0", "aisidecar.prompt.subject_isolated_quality/1.0.0"),
        ]

        for (name, version) in expectedVersions {
            let text = try bundledPrompt(named: name)
            XCTAssertTrue(text.hasPrefix("PROMPT_VERSION: \(version)\n"))
            XCTAssertTrue(text.hasSuffix("\n"))
            XCTAssertFalse(text.hasSuffix("\n\n"))
            XCTAssertEqual(VersionedPrompt(version: version, text: text).sha256, sha256(text))
            XCTAssertEqual(text, try bundledPrompt(named: name))
        }

        XCTAssertEqual(
            sha256(try bundledPrompt(named: "whole_image_v1.5.0")),
            "603d96141dd9ac54b0b49024b93e76ba931921086e73bc0e7e57467363f57300"
        )
        XCTAssertEqual(
            sha256(try bundledPrompt(named: "subject_isolated_v1.5.0")),
            "be7bedb9dac5c795c03b49d8f16368080d5d2ab44226d76bcf4314b5fbf17640"
        )
    }

    func testPromptContextAppendsDeterministicGPSBlockWhenAvailable() throws {
        let context = ModelInputContext(gps: GPSModelInputContext(
            mode: .coarse,
            latitude: 45.1,
            longitude: -122.7,
            precisionDegrees: 0.1
        ))
        let base = try PromptRegistry.prompt(for: .wholeImage)
        let contextual = try PromptRegistry.prompt(for: .wholeImage, context: context)
        let repeated = try PromptRegistry.prompt(for: .wholeImage, context: context)

        XCTAssertEqual(contextual.version, base.version)
        XCTAssertNotEqual(contextual.text, base.text)
        XCTAssertTrue(contextual.text.contains("MODEL INPUT CONTEXT"))
        XCTAssertTrue(contextual.text.contains("latitude: 45.1"))
        XCTAssertTrue(contextual.text.contains("longitude: -122.7"))
        XCTAssertEqual(contextual.sha256, repeated.sha256)
        XCTAssertEqual(contextual.sha256, sha256(contextual.text))
    }

    func testSchemasExposeExpectedTopLevelFields() throws {
        let whole = try ResponseSchemas.schema(for: .wholeImage)
        let subject = try ResponseSchemas.schema(for: .subjectIsolated)

        XCTAssertEqual(whole.version, "urn:aisidecar:response:whole-image:1.5.0")
        XCTAssertEqual(subject.version, "urn:aisidecar:response:subject-isolated:1.5.0")
        let wholeProperties = try XCTUnwrap(whole.schema.objectValue?["properties"]?.objectValue)
        XCTAssertNotNil(wholeProperties["species"])
        XCTAssertNotNil(wholeProperties["scene_context"])
        XCTAssertNotNil(wholeProperties["habitat_or_setting"])
        XCTAssertNil(wholeProperties["visible_text"])
        XCTAssertNil(wholeProperties["gps"])
        XCTAssertNil(wholeProperties["latitude"])
        XCTAssertNil(wholeProperties["longitude"])
        let subjectProperties = try XCTUnwrap(subject.schema.objectValue?["properties"]?.objectValue)
        XCTAssertNotNil(subjectProperties["species"])
        XCTAssertNil(subjectProperties["scene_context"])
        XCTAssertNil(subjectProperties["habitat_or_setting"])
        XCTAssertNil(subjectProperties["visible_text"])
        XCTAssertNil(subjectProperties["gps"])
        XCTAssertNil(subjectProperties["latitude"])
        XCTAssertNil(subjectProperties["longitude"])
    }

    func testValidFixtureResponsesPassValidation() throws {
        try JSONSchemaValidator.validate(wholeImageFixture(), against: ResponseSchemas.schema(for: .wholeImage))
        try JSONSchemaValidator.validate(subjectIsolatedFixture(), against: ResponseSchemas.schema(for: .subjectIsolated))
    }

    func testQualitySchemaResourcesLoadWithExpectedIDs() throws {
        let expectedVersions = [
            ("whole_image_v1.6.0", "urn:aisidecar:response:whole-image:1.6.0"),
            ("subject_isolated_v1.6.0", "urn:aisidecar:response:subject-isolated:1.6.0"),
            ("whole_image_quality_v1.0.0", "urn:aisidecar:response:whole-image-quality:1.0.0"),
            ("subject_isolated_quality_v1.0.0", "urn:aisidecar:response:subject-isolated-quality:1.0.0"),
        ]

        for (name, expectedVersion) in expectedVersions {
            let schema = try bundledSchema(named: name)
            XCTAssertEqual(schema.version, expectedVersion)
        }

        let wholeLegacy = try bundledSchema(named: "whole_image_v1.5.0")
        let subjectLegacy = try bundledSchema(named: "subject_isolated_v1.5.0")
        XCTAssertEqual(wholeLegacy.version, "urn:aisidecar:response:whole-image:1.5.0")
        XCTAssertEqual(subjectLegacy.version, "urn:aisidecar:response:subject-isolated:1.5.0")

        let qualityOnlyConfidence = try XCTUnwrap(
            try bundledSchema(named: "whole_image_quality_v1.0.0").schema.objectValue?["$defs"]?.objectValue?["confidence"]
        )
        let legacyConfidence = try XCTUnwrap(wholeLegacy.schema.objectValue?["$defs"]?.objectValue?["confidence"])
        XCTAssertEqual(qualityOnlyConfidence, legacyConfidence)
    }

    func testQualitySchemasAcceptCompleteAssessments() throws {
        var wholeCombined = try XCTUnwrap(wholeImageFixture().objectValue)
        wholeCombined["quality_assessment"] = wholeQualityAssessment()
        try JSONSchemaValidator.validate(.object(wholeCombined), against: bundledSchema(named: "whole_image_v1.6.0"))

        var subjectCombined = try XCTUnwrap(subjectIsolatedFixture().objectValue)
        subjectCombined["quality_assessment"] = subjectQualityAssessment()
        try JSONSchemaValidator.validate(.object(subjectCombined), against: bundledSchema(named: "subject_isolated_v1.6.0"))

        try JSONSchemaValidator.validate(
            .object(["quality_assessment": wholeQualityAssessment()]),
            against: bundledSchema(named: "whole_image_quality_v1.0.0")
        )
        try JSONSchemaValidator.validate(
            .object(["quality_assessment": subjectQualityAssessment()]),
            against: bundledSchema(named: "subject_isolated_quality_v1.0.0")
        )
    }

    func testQualitySchemaRejectsInvalidAssessmentShapes() throws {
        let schema = try bundledSchema(named: "whole_image_v1.6.0")

        assertInvalid(wholeImageFixture(), against: schema)

        var missingCriterion = try XCTUnwrap(wholeImageFixture().objectValue)
        var incompleteAssessment = try XCTUnwrap(wholeQualityAssessment().objectValue)
        incompleteAssessment.removeValue(forKey: "focus")
        missingCriterion["quality_assessment"] = .object(incompleteAssessment)
        assertInvalid(.object(missingCriterion), against: schema)

        var unknownCriterion = try XCTUnwrap(wholeImageFixture().objectValue)
        var assessmentWithUnknownCriterion = try XCTUnwrap(wholeQualityAssessment().objectValue)
        assessmentWithUnknownCriterion["imaginary_criterion"] = .string("strong")
        unknownCriterion["quality_assessment"] = .object(assessmentWithUnknownCriterion)
        assertInvalid(.object(unknownCriterion), against: schema)

        var invalidLevel = try XCTUnwrap(wholeImageFixture().objectValue)
        var assessmentWithInvalidLevel = try XCTUnwrap(wholeQualityAssessment().objectValue)
        assessmentWithInvalidLevel["focus"] = .string("excellent")
        invalidLevel["quality_assessment"] = .object(assessmentWithInvalidLevel)
        assertInvalid(.object(invalidLevel), against: schema)

        var tooManyConcerns = try XCTUnwrap(wholeImageFixture().objectValue)
        var assessmentWithTooManyConcerns = try XCTUnwrap(wholeQualityAssessment().objectValue)
        assessmentWithTooManyConcerns["concerns"] = .array([.string("a"), .string("b"), .string("c")])
        tooManyConcerns["quality_assessment"] = .object(assessmentWithTooManyConcerns)
        assertInvalid(.object(tooManyConcerns), against: schema)

        var tooLongNote = try XCTUnwrap(wholeImageFixture().objectValue)
        var assessmentWithTooLongNote = try XCTUnwrap(wholeQualityAssessment().objectValue)
        assessmentWithTooLongNote["strengths"] = .array([.string(String(repeating: "a", count: 161))])
        tooLongNote["quality_assessment"] = .object(assessmentWithTooLongNote)
        assertInvalid(.object(tooLongNote), against: schema)

        var multilineNote = try XCTUnwrap(wholeImageFixture().objectValue)
        var assessmentWithMultilineNote = try XCTUnwrap(wholeQualityAssessment().objectValue)
        assessmentWithMultilineNote["strengths"] = .array([.string("visible detail\ncontinues")])
        multilineNote["quality_assessment"] = .object(assessmentWithMultilineNote)
        assertInvalid(.object(multilineNote), against: schema)
    }

    func testSubjectSchemaRejectsHabitatAndSceneFields() throws {
        let schema = try ResponseSchemas.schema(for: .subjectIsolated)
        var response = try XCTUnwrap(subjectIsolatedFixture().objectValue)
        response["scene_context"] = .array([candidateWithoutEvidence("studio setup")])
        response["habitat_or_setting"] = .array([candidateWithoutEvidence("wetland")])

        XCTAssertThrowsError(try JSONSchemaValidator.validate(.object(response), against: schema)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Additional property"))
        }
    }

    func testSchemasRejectVisibleTextField() throws {
        var wholeResponse = try XCTUnwrap(wholeImageFixture().objectValue)
        wholeResponse["visible_text"] = .array([])
        assertInvalid(.object(wholeResponse), against: try ResponseSchemas.schema(for: .wholeImage))

        var subjectResponse = try XCTUnwrap(subjectIsolatedFixture().objectValue)
        subjectResponse["visible_text"] = .array([])
        assertInvalid(.object(subjectResponse), against: try ResponseSchemas.schema(for: .subjectIsolated))
    }

    func testTargetGenreRequiresSpeciesButAllowsEmptySpecies() throws {
        let wholeSchema = try ResponseSchemas.schema(for: .wholeImage)

        assertInvalid(wholeImageMutating { response in
            response.removeValue(forKey: "species")
        }, against: wholeSchema)

        try JSONSchemaValidator.validate(wholeImageMutating { response in
            response["species"] = .array([])
        }, against: wholeSchema)
    }

    func testSecondaryTargetGenreAlsoRequiresSpecies() throws {
        let schema = try ResponseSchemas.schema(for: .wholeImage)

        try JSONSchemaValidator.validate(wholeImageMutating { response in
            response["genre_or_photography_type"] = .array([
                genreCandidate("landscape"),
                genreCandidate("wildlife")
            ])
            response["species"] = .array([
                candidateWithEvidence("heron", evidence: "long-legged bird visible in scene")
            ])
        }, against: schema)

        assertInvalid(wholeImageMutating { response in
            response["genre_or_photography_type"] = .array([
                genreCandidate("landscape"),
                genreCandidate("wildlife")
            ])
            response.removeValue(forKey: "species")
        }, against: schema)
    }

    func testNonTargetGenresStillRequireSpeciesField() throws {
        // Schema 1.5.0 requires `species` unconditionally because Ollama's
        // grammar conversion ignores if/then/else; non-biological genres
        // carry an empty array and CandidateExtractor enforces the genre
        // precondition downstream.
        let schema = try ResponseSchemas.schema(for: .wholeImage)

        try JSONSchemaValidator.validate(wholeImageMutating { response in
            response["genre_or_photography_type"] = .array([genreCandidate("landscape")])
            response["species"] = .array([])
        }, against: schema)

        assertInvalid(wholeImageMutating { response in
            response["genre_or_photography_type"] = .array([genreCandidate("landscape")])
            response.removeValue(forKey: "species")
        }, against: schema)
    }

    func testBasePromptsCarryNoGPSOrExternalContextLanguage() throws {
        // GPS guidance lives only in the injected MODEL INPUT CONTEXT block,
        // so runs without GPS context never mention it.
        for role in ModelInputRole.allCases {
            let prompt = try PromptRegistry.prompt(for: role)
            XCTAssertFalse(prompt.text.contains("GPS"), "\(role.rawValue) prompt mentions GPS")
            XCTAssertFalse(prompt.text.contains("EXIF"), "\(role.rawValue) prompt mentions EXIF")
            XCTAssertFalse(prompt.text.contains("MODEL INPUT CONTEXT"), "\(role.rawValue) prompt mentions the context block")
            XCTAssertFalse(prompt.text.lowercased().contains("coordinate"), "\(role.rawValue) prompt mentions coordinates")
        }

        for name in [
            "whole_image_v1.6.0",
            "subject_isolated_v1.6.0",
            "whole_image_quality_v1.0.0",
            "subject_isolated_quality_v1.0.0",
        ] {
            let prompt = try bundledPrompt(named: name)
            XCTAssertTrue(prompt.contains("Do not use GPS, EXIF, filename, location,"), "\(name) lacks the quality-context ban")
            XCTAssertEqual(prompt.components(separatedBy: "GPS").count, 2, "\(name) mentions GPS outside the ban")
            XCTAssertEqual(prompt.components(separatedBy: "EXIF").count, 2, "\(name) mentions EXIF outside the ban")
            XCTAssertFalse(prompt.contains("MODEL INPUT CONTEXT"), "\(name) mentions the context block")
            XCTAssertFalse(prompt.lowercased().contains("coordinate"), "\(name) mentions coordinates")
        }
    }

    func testSpeciesUsesCandidateWithEvidenceShape() throws {
        let schema = try ResponseSchemas.schema(for: .wholeImage)

        assertInvalid(wholeImageMutating { response in
            response["species"] = .array([.string("great blue heron")])
        }, against: schema)

        assertInvalid(wholeImageMutating { response in
            response["species"] = .array([
                .object([
                    "term": .string("great blue heron"),
                    "confidence": .string("certain"),
                    "evidence": .string("large gray-blue wading bird")
                ])
            ])
        }, against: schema)

        assertInvalid(wholeImageMutating { response in
            response["species"] = .array([
                .object([
                    "term": .string("great blue heron"),
                    "confidence": .string("high")
                ])
            ])
        }, against: schema)
    }

    func testInvalidResponsesFailSchemaValidation() throws {
        let wholeSchema = try ResponseSchemas.schema(for: .wholeImage)

        assertInvalid(wholeImageMutating { response in
            response["genre_or_photography_type"] = .array([
                .object([
                    "term": .string("bird_photography"),
                    "confidence": .string("certain"),
                    "evidence": .string("bird fills the frame")
                ])
            ])
        }, against: wholeSchema)

        assertInvalid(wholeImageMutating { response in
            response["main_subjects"] = .array([.string("heron")])
        }, against: wholeSchema)

        assertInvalid(wholeImageMutating { response in
            response.removeValue(forKey: "summary")
        }, against: wholeSchema)

        assertInvalid(wholeImageMutating { response in
            response["camera"] = .string("mirrorless")
        }, against: wholeSchema)

        assertInvalid(wholeImageMutating { response in
            response["genre_or_photography_type"] = .array([
                genreCandidate("bird_photography"),
                genreCandidate("wildlife"),
                genreCandidate("landscape"),
                genreCandidate("travel"),
                genreCandidate("event")
            ])
        }, against: wholeSchema)

        assertInvalid(wholeImageMutating { response in
            response["summary"] = .string(String(repeating: "a", count: 281))
        }, against: wholeSchema)

        assertInvalid(wholeImageMutating { response in
            response["proposed_keywords"] = .array([
                .object([
                    "term": .string("wading\nbird"),
                    "confidence": .string("high"),
                    "evidence": .string("long legs")
                ])
            ])
        }, against: wholeSchema)

        assertInvalid(wholeImageMutating { response in
            response["genre_or_photography_type"] = .array([
                .object([
                    "term": .string("bird"),
                    "confidence": .string("high"),
                    "evidence": .string("bird fills the frame")
                ])
            ])
        }, against: wholeSchema)
    }

    private func assertInvalid(_ value: JSONValue, against schema: JSONSchemaDocument, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try JSONSchemaValidator.validate(value, against: schema), file: file, line: line)
    }

    private func wholeImageMutating(_ mutate: (inout [String: JSONValue]) -> Void) -> JSONValue {
        var response = wholeImageFixture().objectValue!
        mutate(&response)
        return .object(response)
    }

    private func wholeImageFixture() -> JSONValue {
        .object([
            "summary": .string("A great blue heron stands in shallow wetland water."),
            "genre_or_photography_type": .array([genreCandidate("bird_photography")]),
            "species": .array([
                candidateWithEvidence("great blue heron", evidence: "large gray-blue wading bird")
            ]),
            "main_subjects": .array([
                candidateWithEvidence("great blue heron", evidence: "large gray-blue wading bird")
            ]),
            "secondary_subjects": .array([
                candidateWithEvidence("shallow water", evidence: "ripples around the bird's legs")
            ]),
            "scene_context": .array([candidateWithoutEvidence("outdoor wildlife scene")]),
            "habitat_or_setting": .array([candidateWithoutEvidence("wetland")]),
            "behavior_or_action": .array([candidateWithoutEvidence("standing")]),
            "proposed_keywords": .array([
                candidateWithEvidence("wading bird", evidence: "long legs in shallow water")
            ]),
            "uncertainty_notes": .string("")
        ])
    }

    private func subjectIsolatedFixture() -> JSONValue {
        .object([
            "summary": .string("An isolated heron shows long legs, a pointed bill, and gray-blue plumage."),
            "genre_or_photography_type": .array([genreCandidate("bird_photography")]),
            "species": .array([
                candidateWithEvidence("heron", evidence: "long pointed bill and wading-bird shape")
            ]),
            "main_subjects": .array([
                candidateWithEvidence("heron", evidence: "long pointed bill and wading-bird shape")
            ]),
            "secondary_subjects": .array([
                candidateWithEvidence("plumage", evidence: "gray-blue feathers")
            ]),
            "behavior_or_action": .array([candidateWithoutEvidence("standing")]),
            "proposed_keywords": .array([
                candidateWithEvidence("long bill", evidence: "straight pointed bill")
            ]),
            "uncertainty_notes": .string("")
        ])
    }

    private func wholeQualityAssessment() -> JSONValue {
        .object([
            "focus": .string("strong"),
            "composition": .string("strong"),
            "exposure_and_tone": .string("acceptable"),
            "lighting_and_color": .string("acceptable"),
            "subject_background_relationship": .string("strong"),
            "moment_or_expression": .string("unrated"),
            "technical_cleanliness": .string("acceptable"),
            "overall_effectiveness": .string("strong"),
            "strengths": .array([.string("The bird is sharply resolved against calm water.")]),
            "concerns": .array([]),
            "confidence": .string("high"),
        ])
    }

    private func subjectQualityAssessment() -> JSONValue {
        .object([
            "focus": .string("strong"),
            "exposure_and_tone": .string("acceptable"),
            "lighting_and_color": .string("acceptable"),
            "detail_and_texture": .string("strong"),
            "pose_expression_or_moment": .string("acceptable"),
            "technical_cleanliness": .string("acceptable"),
            "overall_subject_quality": .string("strong"),
            "strengths": .array([.string("Fine feather detail remains visible."), .string("The eye is sharply focused.")]),
            "concerns": .array([]),
            "confidence": .string("high"),
        ])
    }

    private func bundledSchema(named name: String) throws -> JSONSchemaDocument {
        let url = try XCTUnwrap(AISidecarResourceBundle.current.url(forResource: name, withExtension: "json"))
        let schema = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let version = try XCTUnwrap(schema.objectValue?["$id"]?.stringValue)
        return JSONSchemaDocument(version: version, schema: schema)
    }

    private func bundledPrompt(named name: String) throws -> String {
        let url = try XCTUnwrap(AISidecarResourceBundle.current.url(forResource: name, withExtension: "txt"))
        return try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))
    }

    private func genreCandidate(_ term: String) -> JSONValue {
        .object([
            "term": .string(term),
            "confidence": .string("high"),
            "evidence": .string("bird fills the frame")
        ])
    }

    private func candidateWithEvidence(_ term: String, evidence: String) -> JSONValue {
        .object([
            "term": .string(term),
            "confidence": .string("high"),
            "evidence": .string(evidence)
        ])
    }

    private func candidateWithoutEvidence(_ term: String) -> JSONValue {
        .object([
            "term": .string(term),
            "confidence": .string("high")
        ])
    }

    private func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
