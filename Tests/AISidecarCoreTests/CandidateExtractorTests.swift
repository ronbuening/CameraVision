import Foundation
import XCTest
@testable import AISidecarCore

final class CandidateExtractorTests: XCTestCase {
    func testGoldenSidecarFixtureExtractsDeterministicKeywordsAndSkipsSpecies() throws {
        let result = CandidateExtractor().extract(
            from: try resolvedInput(document: goldenSidecarDocument()),
            configuration: configuration()
        )

        XCTAssertEqual(
            result.flatKeywords.map(\.term),
            [
                "bird_photography",
                "shallow water",
                "outdoor wildlife scene",
                "wetland",
                "standing",
                "wading bird",
                "gray-blue plumage",
                "long bill"
            ]
        )
        XCTAssertEqual(result.hierarchicalKeywords.map(\.term), result.flatKeywords.map(\.term))
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(
            result.skippedCandidates
                .filter { $0.reason == .specificTagPolicy }
                .compactMap(\.term),
            ["great blue heron", "great blue heron", "heron", "heron"]
        )

        let birdPhotography = try XCTUnwrap(result.flatKeywords.first { $0.term == "bird_photography" })
        XCTAssertEqual(birdPhotography.candidates.map(\.provenance.inputRole), [.wholeImage, .subjectIsolated])
        XCTAssertEqual(
            result.skippedCandidates
                .filter { $0.reason == .duplicate }
                .compactMap(\.term),
            ["bird_photography", "standing"]
        )
    }

    func testConfidenceThresholdFiltersOrdinalBands() throws {
        let input = try resolvedInput(response: response([
            .proposedKeywords: .array([
                candidate("low term", confidence: "low"),
                candidate("medium term", confidence: "medium"),
                candidate("high term", confidence: "high")
            ])
        ]))

        XCTAssertEqual(
            CandidateExtractor().extract(from: input, configuration: configuration(minConfidence: .low))
                .flatKeywords.map(\.term),
            ["low term", "medium term", "high term"]
        )
        let mediumResult = CandidateExtractor().extract(from: input, configuration: configuration(minConfidence: .medium))
        XCTAssertEqual(mediumResult.flatKeywords.map(\.term), ["medium term", "high term"])
        XCTAssertEqual(mediumResult.skippedCandidates.map(\.reason), [.belowConfidenceThreshold])
        XCTAssertEqual(
            CandidateExtractor().extract(from: input, configuration: configuration(minConfidence: .high))
                .flatKeywords.map(\.term),
            ["high term"]
        )
    }

    func testDuplicatesPreserveFirstCasingAndAllProvenance() throws {
        let input = try resolvedInput(response: response([
            .mainSubjects: .array([
                candidate(" Bird ", confidence: "high"),
                candidate("bird", confidence: "medium"),
                candidate("BIRD", confidence: "high")
            ])
        ]))

        let result = CandidateExtractor().extract(from: input, configuration: configuration(minConfidence: .low))

        XCTAssertEqual(result.flatKeywords.map(\.term), ["Bird"])
        XCTAssertEqual(result.flatKeywords.first?.candidates.map(\.term), [" Bird ", "bird", "BIRD"])
        XCTAssertEqual(
            result.skippedCandidates.filter { $0.reason == .duplicate }.compactMap(\.term),
            ["bird", "BIRD"]
        )
    }

    func testKeywordTextNormalizationRejectsEmptyTermsAndHierarchySeparators() throws {
        let input = try resolvedInput(response: response([
            .proposedKeywords: .array([
                candidate(" cafe\u{301}\t bird ", confidence: "high"),
                candidate("shore|bird", confidence: "high"),
                candidate("   ", confidence: "high")
            ])
        ]))

        let result = CandidateExtractor().extract(from: input, configuration: configuration())

        XCTAssertEqual(result.flatKeywords.map(\.term), ["café bird"])
        XCTAssertEqual(result.skippedCandidates.map(\.reason), [
            .containsHierarchySeparator,
            .emptyAfterNormalization
        ])
    }

    func testMalformedCandidateShapesProduceIssuesWithoutThrowing() throws {
        let input = try resolvedInput(response: response([
            .mainSubjects: .string("not an array"),
            .proposedKeywords: .array([
                .string("not an object"),
                .object(["confidence": .string("high")]),
                .object([
                    "term": .string("bad confidence"),
                    "confidence": .string("certain")
                ]),
                .object([
                    "term": .string("valid despite evidence"),
                    "confidence": .string("high"),
                    "evidence": .number(1)
                ])
            ])
        ]))

        let result = CandidateExtractor().extract(from: input, configuration: configuration())

        XCTAssertEqual(result.flatKeywords.map(\.term), ["valid despite evidence"])
        XCTAssertNil(result.flatKeywords.first?.candidates.first?.evidence)
        XCTAssertEqual(result.issues.map(\.reason), [
            .malformedCandidateField,
            .malformedCandidate,
            .malformedCandidate,
            .malformedCandidate,
            .malformedEvidence
        ])
    }

    func testMissingEvidenceIsValidForSceneHabitatAndBehaviorFields() throws {
        let input = try resolvedInput(response: response([
            .sceneContext: .array([candidate("outdoor scene", confidence: "high", evidence: nil)]),
            .habitatOrSetting: .array([candidate("wetland", confidence: "medium", evidence: nil)]),
            .behaviorOrAction: .array([candidate("standing", confidence: "high", evidence: nil)])
        ]))

        let result = CandidateExtractor().extract(from: input, configuration: configuration())

        XCTAssertEqual(result.flatKeywords.map(\.term), ["outdoor scene", "wetland", "standing"])
        XCTAssertTrue(result.extractedCandidates.allSatisfy { $0.evidence == nil })
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testSpecificTagPolicyCanBeBypassedWithoutBypassingOtherFilters() throws {
        let input = try resolvedInput(response: response([
            .species: .array([candidate("great blue heron", confidence: "high")]),
            .mainSubjects: .array([candidate("great blue heron", confidence: "high")]),
            .proposedKeywords: .array([
                candidate("Ardea herodias", confidence: "high"),
                candidate("Yosemite National Park", confidence: "high"),
                candidate("Jane Doe", confidence: "high"),
                candidate("red-tailed hawk", confidence: "high", evidence: "exact ID from field marks"),
                candidate("bird", confidence: "high"),
                candidate("shorebird", confidence: "medium"),
                candidate("lake", confidence: "high"),
                candidate("low specific", confidence: "low", evidence: "exact identification")
            ])
        ]))

        let defaultResult = CandidateExtractor().extract(from: input, configuration: configuration())
        XCTAssertEqual(defaultResult.flatKeywords.map(\.term), ["bird", "shorebird", "lake"])
        XCTAssertEqual(
            defaultResult.skippedCandidates.filter { $0.reason == .specificTagPolicy }.compactMap(\.term),
            [
                "great blue heron",
                "great blue heron",
                "Ardea herodias",
                "Yosemite National Park",
                "Jane Doe",
                "red-tailed hawk"
            ]
        )

        let allowedResult = CandidateExtractor().extract(
            from: input,
            configuration: configuration(allowSpecificTags: true)
        )
        XCTAssertEqual(
            allowedResult.flatKeywords.map(\.term),
            [
                "great blue heron",
                "Ardea herodias",
                "Yosemite National Park",
                "Jane Doe",
                "red-tailed hawk",
                "bird",
                "shorebird",
                "lake"
            ]
        )
        XCTAssertTrue(allowedResult.skippedCandidates.contains { $0.reason == .duplicate && $0.term == "great blue heron" })
        XCTAssertTrue(allowedResult.skippedCandidates.contains { $0.reason == .belowConfidenceThreshold && $0.term == "low specific" })
    }

    func testDisabledFlatAndHierarchicalExportsRecordSkippedReasons() throws {
        let input = try resolvedInput(response: response([
            .proposedKeywords: .array([candidate("wading bird", confidence: "high")])
        ]))

        let result = CandidateExtractor().extract(
            from: input,
            configuration: configuration(writeFlatKeywords: false, writeHierarchicalKeywords: false)
        )

        XCTAssertTrue(result.flatKeywords.isEmpty)
        XCTAssertTrue(result.hierarchicalKeywords.isEmpty)
        XCTAssertEqual(result.skippedCandidates.map(\.reason), [
            .disabledFlatExport,
            .disabledHierarchicalExport
        ])
        XCTAssertEqual(result.skippedCandidates.map(\.term), ["wading bird", "wading bird"])
    }

    private func configuration(
        minConfidence: XMPMinimumConfidence = .medium,
        allowSpecificTags: Bool = false,
        writeFlatKeywords: Bool = true,
        writeHierarchicalKeywords: Bool = true
    ) -> ResolvedXMPExportConfiguration {
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.minConfidence = minConfidence
        configuration.allowSpecificTags = allowSpecificTags
        configuration.writeFlatKeywords = writeFlatKeywords
        configuration.writeHierarchicalKeywords = writeHierarchicalKeywords
        return configuration
    }

    private func resolvedInput(
        response: JSONValue,
        sidecarPath: String = "/sidecars/Bird.JPG.ai.json",
        sourcePath: String = "/photos/Bird.JPG"
    ) throws -> ResolvedRawSidecarInput {
        try resolvedInput(
            document: RawJSONSidecarDocument(sidecar: sidecar(responses: [(.wholeImage, response)])),
            sidecarPath: sidecarPath,
            sourcePath: sourcePath
        )
    }

    private func resolvedInput(
        document: RawJSONSidecarDocument,
        sidecarPath: String = "/sidecars/Bird.JPG.ai.json",
        sourcePath: String = "/photos/Bird.JPG"
    ) throws -> ResolvedRawSidecarInput {
        ResolvedRawSidecarInput(
            sidecarPath: URL(fileURLWithPath: sidecarPath),
            document: document,
            sourcePath: URL(fileURLWithPath: sourcePath),
            sourceIdentityStatus: .skipped,
            relativePath: URL(fileURLWithPath: sidecarPath).lastPathComponent,
            warnings: []
        )
    }

    private func sidecar(responses: [(ModelInputRole, JSONValue?)]) -> RawJSONSidecar {
        RawJSONSidecar(
            source: makeSource(fileName: "Bird.JPG", relativePath: "Bird.JPG", path: "/photos/Bird.JPG"),
            runConfiguration: .builtInDefaults,
            modelRuns: responses.enumerated().map { index, item in
                modelRun(role: item.0, response: item.1, index: index)
            },
            createdAt: Date(timeIntervalSince1970: 1_800_003_000)
        )
    }

    private func modelRun(role: ModelInputRole, response: JSONValue?, index: Int) -> ModelRunRecord {
        ModelRunRecord(
            inputRole: role,
            model: "gemma4:26b-a4b-it-qat",
            modelDigest: "sha256:test-\(index)",
            runtime: "ollama",
            runtimeVersion: "0.12.6",
            promptVersion: "aisidecar.prompt.test/1.0.0",
            promptSHA256: String(repeating: "a", count: 64),
            responseSchemaVersion: "urn:aisidecar:response:test:1.0.0",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "b", count: 64),
            rawResponseText: "{}",
            parsedResponseJSON: response,
            jsonValid: response != nil,
            durationMs: 1,
            error: nil
        )
    }

    private func response(_ fields: [CandidateSourceField: JSONValue]) -> JSONValue {
        var object: [String: JSONValue] = [
            "summary": .string("fixture"),
            "uncertainty_notes": .string("")
        ]
        for (field, value) in fields {
            object[field.rawValue] = value
        }
        return .object(object)
    }

    private func candidate(
        _ term: String,
        confidence: String = "high",
        evidence: String? = "visible evidence"
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "term": .string(term),
            "confidence": .string(confidence)
        ]
        if let evidence {
            object["evidence"] = .string(evidence)
        }
        return .object(object)
    }

    private func goldenSidecarDocument() throws -> RawJSONSidecarDocument {
        let json = try fixtureJSON(
            name: "phase1-both-normalized",
            extension: "json",
            subdirectory: "golden-sidecars"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try RawJSONSidecarDocument(data: encoder.encode(sanitizeGoldenFixture(json)))
    }

    private func fixtureJSON(name: String, extension fileExtension: String, subdirectory: String) throws -> JSONValue {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
                ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
        )
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    private func sanitizeGoldenFixture(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            return .object(object.mapValues(sanitizeGoldenFixture))
        case .array(let array):
            return .array(array.map(sanitizeGoldenFixture))
        case .string("<timestamp>"):
            return .string("2026-01-01T00:00:00Z")
        case .string("<source-path>"):
            return .string("/photos/Bird.JPG")
        case .string("<sha256>"):
            return .string(String(repeating: "a", count: 64))
        case .string("<derivative-sha256>"):
            return .string(String(repeating: "b", count: 64))
        case .string("<cache-path>"):
            return .string("/cache/Bird.jpg")
        default:
            return value
        }
    }
}
