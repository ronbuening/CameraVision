import Foundation
import XCTest
@testable import AISidecarCore

final class NormalizationSessionTests: XCTestCase {
    func testFromJSONSessionOnlyWritesSchemaPrivacyIdentityAndReportWithoutXMP() throws {
        let jsonRoot = try temporaryDirectory()
        let sourceRoot = try temporaryDirectory()
        let output = try temporaryDirectory()
        let source = try writeTestImage("Bird.JPG", in: sourceRoot)
        let sourceImage = try scannedSourceImage(source, relativePath: "Bird.JPG")
        _ = try writeRawSidecar(source: sourceImage, named: "Bird.JPG.ai.json", in: jsonRoot)

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .controlledVocabulary
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = output.path
        configuration.sessionOnly = true
        configuration.sessionSubject = "Birds"
        configuration.allowSessionSubjectPropagation = true
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

        let result = try NormalizePipeline().runSessionOnly(
            mode: .fromJSON(path: jsonRoot.path),
            configuration: configuration,
            timestamp: timestamp,
            sessionID: "session-fixture"
        )

        let sessionPath = try XCTUnwrap(result.session.artifacts.sessionPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.session.artifacts.reportPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.session.artifacts.summaryPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.session.artifacts.progressPath))
        XCTAssertTrue(try xmpFiles(in: jsonRoot).isEmpty)
        XCTAssertTrue(try xmpFiles(in: sourceRoot).isEmpty)
        XCTAssertTrue(try xmpFiles(in: output).isEmpty)

        let decoded = try decodeSession(at: URL(fileURLWithPath: sessionPath))
        XCTAssertEqual(decoded.schemaVersion, NormalizationSchemaIdentifiers.session)
        XCTAssertEqual(decoded.session.sessionID, "session-fixture")
        XCTAssertEqual(decoded.session.workflow, .fromJSON)
        XCTAssertEqual(decoded.vocabulary.schemaVersion, NormalizationSchemaIdentifiers.vocabulary)
        XCTAssertEqual(decoded.xmpWriter.engineName, OwnedXMPSidecarEngine.engineName)
        XCTAssertFalse(decoded.privacy.exactAffinityInputsPersisted)
        XCTAssertFalse(decoded.privacy.gpsCoordinatesPersisted)
        XCTAssertFalse(decoded.privacy.captureTimesPersisted)
        XCTAssertEqual(decoded.sourceAssets.count, 1)
        XCTAssertEqual(decoded.sourceAssets[0].sourceIdentity.sha256, sourceImage.identity.sha256)
        XCTAssertEqual(decoded.sourceAISidecars[0].sourceAssetID, decoded.sourceAssets[0].assetID)
        XCTAssertEqual(decoded.sameBaseNameGroups[0].memberAssetIDs, [decoded.sourceAssets[0].assetID])
        XCTAssertTrue(decoded.candidateObservations.isEmpty)
        XCTAssertTrue(decoded.candidateSkips.isEmpty)
        XCTAssertFalse(decoded.batchCandidates.isEmpty)
        XCTAssertEqual(decoded.perAssetDecisions.count, 1)
        XCTAssertEqual(decoded.perAssetDecisions[0].stage, .userSessionContext)
        XCTAssertEqual(decoded.perAssetDecisions[0].contextType, .subject)
        XCTAssertTrue(decoded.xmpWritePlans.isEmpty)
        XCTAssertEqual(decoded.sessionContext.map(\.contextType), [.subject])
        XCTAssertEqual(decoded.sessionContext[0].foldedText, "birds")
        XCTAssertEqual(decoded.sessionContext[0].unknownPolicyResult, "matched")
        XCTAssertNotNil(decoded.sessionContext[0].matchedCanonicalPath)
        XCTAssertEqual(decoded.sessionContext[0].exportResult, "applied")

        let report = try decodeReport(at: URL(fileURLWithPath: result.session.artifacts.reportPath))
        XCTAssertEqual(report.schemaVersion, NormalizationSchemaIdentifiers.report)
        XCTAssertEqual(report.sessionPath, sessionPath)
        XCTAssertEqual(report.inputSummary.sourceAssetCount, 1)
        XCTAssertEqual(report.inputSummary.sourceAISidecarCount, 1)
        XCTAssertEqual(report.inputSummary.candidateObservationCount, 0)
        XCTAssertGreaterThan(report.inputSummary.batchCandidateCount, 0)
        XCTAssertEqual(report.inputSummary.perAssetDecisionCount, 1)
        XCTAssertEqual(report.inputSummary.xmpWritePlanCount, 0)
        XCTAssertEqual(report.perAssetDecisions.count, 1)
        XCTAssertEqual(report.sourceAssets.count, 1)
        XCTAssertTrue(report.applicationInstructions.contains { $0.contains("Lightroom Classic") })
        XCTAssertTrue(try readText(at: result.session.artifacts.summaryPath).contains("Normalization Summary"))
        let progress = try decodeProgress(at: result.session.artifacts.progressPath)
        XCTAssertEqual(progress.map(\.stage), [.inputResolution, .normalization, .xmpPlanning, .artifactWrite])
        XCTAssertEqual(progress.map(\.status), [.completed, .completed, .skipped, .completed])
    }

    func testObservedTagsDefaultWritesFlatOnlyDecisionsAndSyntheticVocabularyIdentity() throws {
        let jsonRoot = try temporaryDirectory()
        let sourceRoot = try temporaryDirectory()
        let output = try temporaryDirectory()
        let source = try writeTestImage("Heron.JPG", in: sourceRoot)
        let sourceImage = try scannedSourceImage(source, relativePath: "Heron.JPG")
        _ = try writeRawSidecar(
            source: sourceImage,
            named: "Heron.JPG.ai.json",
            in: jsonRoot,
            modelRuns: [
                modelRun(role: .wholeImage, response: response([
                    .species: .array([
                        candidate("great blue herons", confidence: "high"),
                        candidate("Great Blue Heron", confidence: "medium"),
                        candidate("Ardea herodias", confidence: "high")
                    ]),
                    .proposedKeywords: .array([
                        candidate("Subject|Wildlife|Birds", confidence: "high"),
                        candidate("40.7128, -74.0060", confidence: "high", evidence: "GPS coordinates only")
                    ])
                ]), index: 0)
            ]
        )

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = output.path
        configuration.dryRun = true
        configuration.normalizationMode = .singleImage

        let result = try NormalizePipeline().runDryRun(
            mode: .fromJSON(path: jsonRoot.path),
            configuration: configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_050),
            sessionID: "observed-tags-session"
        )

        let plan = try XCTUnwrap(result.changePlan?.targetPlans.first)
        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["Great Blue Heron"])
        XCTAssertTrue(plan.hierarchicalKeywordsToAdd.isEmpty)

        let decoded = try decodeSession(at: URL(fileURLWithPath: try XCTUnwrap(result.session.artifacts.sessionPath)))
        XCTAssertEqual(decoded.resolvedConfiguration.vocabularyMode, .observedTags)
        XCTAssertEqual(decoded.vocabulary.path, "observed-tags://generated")
        XCTAssertEqual(decoded.vocabulary.schemaVersion, NormalizationSchemaIdentifiers.vocabulary)
        XCTAssertEqual(decoded.vocabulary.mode, .observedTags)
        XCTAssertEqual(decoded.vocabulary.entryCount, 1)
        XCTAssertEqual(
            decoded.candidateSkips.map(\.reason.rawValue).sorted(),
            ["contains_hierarchy_separator", "coordinate_like_term", "duplicate", "specific_tag_policy"]
        )
        XCTAssertEqual(decoded.batchCandidates.first?.candidateKind, .observedModelTag)
        XCTAssertNil(decoded.batchCandidates.first?.hierarchicalKeyword)
        let decision = try XCTUnwrap(decoded.perAssetDecisions.first)
        XCTAssertEqual(decision.candidateKind, .observedModelTag)
        XCTAssertEqual(decision.canonicalPath, "Great Blue Heron")
        XCTAssertEqual(decision.flatKeyword, "Great Blue Heron")
        XCTAssertNil(decision.hierarchicalKeyword)
        XCTAssertNil(decision.namespace)
        XCTAssertEqual(decision.directApplyPolicy, .flatOnly)
        XCTAssertEqual(decision.skipReasons, [.directApplyFlatOnly])
    }

    func testFromJSONSessionOnlyPersistsCanonicalizedCandidateDecisionsAndReportCounts() throws {
        let jsonRoot = try temporaryDirectory()
        let sourceRoot = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        let source = try writeTestImage("Bird.JPG", in: sourceRoot)
        let sourceImage = try scannedSourceImage(source, relativePath: "Bird.JPG")
        _ = try writeRawSidecar(
            source: sourceImage,
            named: "Bird.JPG.ai.json",
            in: jsonRoot,
            modelRuns: [
                modelRun(role: .wholeImage, response: response([
                    .mainSubjects: .array([
                        candidate("bird", confidence: "high")
                    ])
                ]), index: 0),
                modelRun(role: .subjectIsolated, response: response([
                    .proposedKeywords: .array([
                        candidate("avian", confidence: "medium")
                    ])
                ]), index: 1)
            ]
        )

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = output.path
        configuration.sessionOnly = true
        configuration.normalizationMode = .singleImage
        configuration.vocabularyMode = .controlledVocabulary
        configuration.vocabularyPath = vocabularyPath

        let result = try NormalizePipeline().runSessionOnly(
            mode: .fromJSON(path: jsonRoot.path),
            configuration: configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_100),
            sessionID: "session-candidates"
        )

        let decoded = try decodeSession(at: URL(fileURLWithPath: try XCTUnwrap(result.session.artifacts.sessionPath)))
        XCTAssertEqual(decoded.candidateObservations.map(\.provenance.inputRole), [.wholeImage, .subjectIsolated])
        XCTAssertEqual(decoded.candidateSkips.map(\.reason), [.duplicate])
        XCTAssertEqual(decoded.batchCandidates.first?.canonicalPath, "Subject|Wildlife|Birds")
        XCTAssertEqual(decoded.batchCandidates.first?.directAssetSupportCount, 1)
        let decision = try XCTUnwrap(decoded.perAssetDecisions.first)
        XCTAssertEqual(decision.stage, .directModelObservation)
        XCTAssertEqual(decision.canonicalPath, "Subject|Wildlife|Birds")
        XCTAssertEqual(decision.flatKeyword, "Birds")
        XCTAssertEqual(decision.hierarchicalKeyword, "Subject|Wildlife|Birds")
        XCTAssertEqual(decision.supportUnits, 1)
        XCTAssertEqual(decision.observationCount, 2)

        let report = try decodeReport(at: URL(fileURLWithPath: decoded.artifacts.reportPath))
        XCTAssertEqual(report.inputSummary.candidateObservationCount, 2)
        XCTAssertEqual(report.inputSummary.candidateSkipCount, 1)
        XCTAssertEqual(report.inputSummary.batchCandidateCount, 1)
        XCTAssertEqual(report.inputSummary.perAssetDecisionCount, 1)
        XCTAssertEqual(report.decisionSummary.acceptedCount, 1)
    }

    func testNormalizeDryRunPersistsNormalizedXMPPlansWithoutCreatingXMP() throws {
        let jsonRoot = try temporaryDirectory()
        let sourceRoot = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        let source = try writeTestImage("Bird.JPG", in: sourceRoot)
        let sourceImage = try scannedSourceImage(source, relativePath: "Bird.JPG")
        _ = try writeRawSidecar(
            source: sourceImage,
            named: "Bird.JPG.ai.json",
            in: jsonRoot,
            modelRuns: [
                modelRun(role: .wholeImage, response: response([
                    .mainSubjects: .array([
                        candidate("bird", confidence: "high")
                    ])
                ]), index: 0)
            ]
        )

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = output.path
        configuration.dryRun = true
        configuration.normalizationMode = .singleImage
        configuration.vocabularyMode = .controlledVocabulary
        configuration.vocabularyPath = vocabularyPath

        let result = try NormalizePipeline().runDryRun(
            mode: .fromJSON(path: jsonRoot.path),
            configuration: configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_200),
            sessionID: "session-dry-run"
        )

        XCTAssertTrue(try xmpFiles(in: sourceRoot).isEmpty)
        XCTAssertTrue(try xmpFiles(in: output).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.session.artifacts.summaryPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.session.artifacts.progressPath))
        let changePlan = try XCTUnwrap(result.changePlan)
        XCTAssertTrue(changePlan.dryRun)
        XCTAssertEqual(changePlan.targetPlans.count, 1)
        XCTAssertEqual(changePlan.targetPlans[0].flatKeywordsToAdd.map(\.term), ["Birds"])
        XCTAssertEqual(changePlan.targetPlans[0].hierarchicalKeywordsToAdd.map(\.term), ["Subject|Wildlife|Birds"])
        XCTAssertEqual(changePlan.targetPlans[0].targetXMPPath, output.appendingPathComponent("Bird.xmp").path)

        let decoded = try decodeSession(at: URL(fileURLWithPath: try XCTUnwrap(result.session.artifacts.sessionPath)))
        let writePlan = try XCTUnwrap(decoded.xmpWritePlans.first)
        XCTAssertEqual(writePlan.xmpChangePlan.targetXMPPath, output.appendingPathComponent("Bird.xmp").path)
        XCTAssertEqual(writePlan.flatKeywordProvenance.first?.decisionIDs, ["decision-000001"])
        XCTAssertEqual(writePlan.flatKeywordProvenance.first?.observationIDs, ["obs-000001"])
        XCTAssertEqual(writePlan.hierarchicalKeywordProvenance.first?.canonicalPaths, ["Subject|Wildlife|Birds"])

        let report = try decodeReport(at: URL(fileURLWithPath: decoded.artifacts.reportPath))
        XCTAssertEqual(report.inputSummary.xmpWritePlanCount, 1)
        XCTAssertEqual(report.xmpWritePlans.count, 1)
        let progress = try decodeProgress(at: decoded.artifacts.progressPath)
        XCTAssertEqual(
            progress.map(\.stage),
            [.inputResolution, .normalization, .xmpPlanning, .xmpTarget, .artifactWrite]
        )
        XCTAssertEqual(progress[3].targetXMPPath, output.appendingPathComponent("Bird.xmp").path)
        XCTAssertEqual(progress[3].plannedFlatKeywords, ["Birds"])
        XCTAssertEqual(progress[3].plannedHierarchicalKeywords, ["Subject|Wildlife|Birds"])
    }

    func testNormalizeDryRunWritesUnmatchedModelSpeciesFallbackAsFlatKeywordOnly() throws {
        let jsonRoot = try temporaryDirectory()
        let sourceRoot = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        let source = try writeTestImage("Heron.JPG", in: sourceRoot)
        let sourceImage = try scannedSourceImage(source, relativePath: "Heron.JPG")
        _ = try writeRawSidecar(
            source: sourceImage,
            named: "Heron.JPG.ai.json",
            in: jsonRoot,
            modelRuns: [
                modelRun(role: .wholeImage, response: response([
                    .species: .array([
                        candidate("Great Blue Heron", confidence: "high")
                    ])
                ]), index: 0)
            ]
        )

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = output.path
        configuration.dryRun = true
        configuration.normalizationMode = .singleImage
        configuration.vocabularyMode = .controlledVocabulary
        configuration.vocabularyPath = vocabularyPath

        let result = try NormalizePipeline().runDryRun(
            mode: .fromJSON(path: jsonRoot.path),
            configuration: configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_250),
            sessionID: "session-species-fallback"
        )

        let plan = try XCTUnwrap(result.changePlan?.targetPlans.first)
        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["Great Blue Heron"])
        XCTAssertTrue(plan.hierarchicalKeywordsToAdd.isEmpty)

        let decoded = try decodeSession(at: URL(fileURLWithPath: try XCTUnwrap(result.session.artifacts.sessionPath)))
        let decision = try XCTUnwrap(decoded.perAssetDecisions.first)
        XCTAssertEqual(decision.candidateKind, .modelSpeciesFallback)
        XCTAssertNil(decision.canonicalPath)
        XCTAssertEqual(decision.flatKeyword, "Great Blue Heron")
        XCTAssertNil(decision.hierarchicalKeyword)
        XCTAssertEqual(decision.directApplyPolicy, .flatOnly)
        let writePlan = try XCTUnwrap(decoded.xmpWritePlans.first)
        XCTAssertEqual(writePlan.flatKeywordProvenance.first?.candidateKinds, [.modelSpeciesFallback])
        XCTAssertEqual(writePlan.flatKeywordProvenance.first?.canonicalPaths, [])
        XCTAssertTrue(writePlan.hierarchicalKeywordProvenance.isEmpty)
    }

    func testNormalizeDryRunWriteUnnormalizedSessionContextPlansFlatKeywordOnly() throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        _ = try writeTestImage("Mystery.JPG", in: root)
        let list = root.appendingPathComponent("images.txt")
        try "Mystery.JPG\n".write(to: list, atomically: true, encoding: .utf8)

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.outputDir = output.path
        configuration.dryRun = true
        configuration.vocabularyMode = .controlledVocabulary
        configuration.vocabularyPath = vocabularyPath
        configuration.sessionSubject = "Folder Mystery"
        configuration.unknownSessionContextPolicy = .writeUnnormalized
        configuration.allowSessionSubjectPropagation = true

        let result = try NormalizePipeline().runDryRun(
            mode: .fileList(path: list.path),
            configuration: configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_300),
            sessionID: "session-flat-only"
        )

        XCTAssertTrue(try xmpFiles(in: output).isEmpty)
        let plan = try XCTUnwrap(result.changePlan?.targetPlans.first)
        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["Folder Mystery"])
        XCTAssertTrue(plan.hierarchicalKeywordsToAdd.isEmpty)

        let decoded = try decodeSession(at: URL(fileURLWithPath: try XCTUnwrap(result.session.artifacts.sessionPath)))
        let writePlan = try XCTUnwrap(decoded.xmpWritePlans.first)
        XCTAssertEqual(writePlan.flatKeywordProvenance.first?.candidateKinds, [.userContextUnnormalized])
        XCTAssertEqual(writePlan.flatKeywordProvenance.first?.contextTypes, [.subject])
        XCTAssertTrue(writePlan.hierarchicalKeywordProvenance.isEmpty)
        XCTAssertTrue(try readText(at: decoded.artifacts.summaryPath).contains("Folder Mystery"))
    }

    func testApplySessionAllowStaleIsInvocationOnlyResolvedConfiguration() throws {
        let configPath = try writeConfig(#"{ "allow_stale": true }"#)
        XCTAssertThrowsError(
            try ConfigurationResolver.resolveApplySession(
                cli: ApplySessionConfigurationOverrides(configPath: configPath)
            )
        )

        let resolved = try ConfigurationResolver.resolveApplySession(
            cli: ApplySessionConfigurationOverrides(allowStale: true)
        )
        XCTAssertTrue(resolved.allowStale)
    }

    private func scannedSourceImage(_ url: URL, relativePath: String) throws -> SourceImage {
        let scan = try ImageScanner().scan(inputPath: url.path, recursive: false, identityPolicy: .sha256)
        var source = try XCTUnwrap(scan.images.first)
        source.relativePath = relativePath
        return source
    }

    private func writeRawSidecar(
        source: SourceImage,
        named relativePath: String,
        in root: URL,
        modelRuns: [ModelRunRecord] = []
    ) throws -> URL {
        let destination = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sidecar = RawJSONSidecar(
            source: source,
            runConfiguration: .builtInDefaults,
            modelRuns: modelRuns,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try RawJSONSidecarDocument(sidecar: sidecar).encodedData()
        try data.write(to: destination)
        return destination
    }

    private func decodeSession(at url: URL) throws -> NormalizationSessionDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NormalizationSessionDocument.self, from: Data(contentsOf: url))
    }

    private func decodeReport(at url: URL) throws -> NormalizationReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NormalizationReport.self, from: Data(contentsOf: url))
    }

    private func xmpFiles(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return enumerator.compactMap { element in
            guard let url = element as? URL, url.pathExtension.lowercased() == "xmp" else {
                return nil
            }
            return url
        }
    }

    private func readText(at path: String) throws -> String {
        String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
    }

    private func decodeProgress(at path: String) throws -> [NormalizationProgressRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try readText(at: path)
            .split(separator: "\n")
            .map { try decoder.decode(NormalizationProgressRecord.self, from: Data($0.utf8)) }
    }

    private func writeConfig(_ contents: String) throws -> String {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("config.json")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    private func writeVocabulary() throws -> String {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("vocabulary.json")
        try vocabularyData(entries: [
            VocabularyEntry(
                canonicalPath: "Subject",
                flatKeyword: "Subject",
                namespace: .subject,
                parentPath: nil,
                synonyms: [],
                requiresReview: false,
                autoApplyAllowed: false,
                directApplyPolicy: .withhold,
                propagationScope: PropagationScope.none,
                specificity: .broad
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Wildlife",
                flatKeyword: "Wildlife",
                namespace: .subject,
                parentPath: "Subject",
                synonyms: [],
                requiresReview: false,
                directApplyPolicy: .allow
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Wildlife|Birds",
                flatKeyword: "Birds",
                namespace: .subject,
                parentPath: "Subject|Wildlife",
                synonyms: ["bird", "avian"],
                requiresReview: false,
                directApplyPolicy: .allow
            )
        ]).write(to: file)
        return file.path
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
        confidence: String,
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
}
