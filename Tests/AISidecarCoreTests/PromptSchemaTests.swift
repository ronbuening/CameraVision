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
