import Foundation
import XCTest

@testable import AISidecarCore

final class NormalizeQualityGradingIntegrationTests: XCTestCase {
    func testNormalizeWriteCombinesNormalizedAndQualityMetadataAndRecordsArtifacts() throws {
        let fixture = try makeFixture(confidence: "high")

        let result = try NormalizeAndWritePipeline(logger: Logger(sink: { _ in })).run(
            mode: .fromJSON(path: fixture.jsonRoot.path),
            configuration: fixture.configuration
        )

        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: fixture.targetXMP.path)
        XCTAssertEqual(snapshot.flatKeywords, ["Birds", "AI Quality good"])
        XCTAssertEqual(snapshot.hierarchicalKeywords, ["Subject|Wildlife|Birds", "AI Quality|good"])
        XCTAssertEqual(snapshot.rating, "4")
        XCTAssertEqual(snapshot.label, "Green")
        XCTAssertEqual(snapshot.urgency, "2")
        XCTAssertEqual(snapshot.pick, "1")
        XCTAssertEqual(snapshot.good, "true")

        let plan = try XCTUnwrap(result.normalizeResult.report.xmpWritePlans.first?.xmpChangePlan)
        XCTAssertEqual(plan.qualityTier, .good)
        XCTAssertEqual(plan.ratingWrite?.plannedValue, "4")
        XCTAssertEqual(plan.labelWrite?.plannedValue, "Green")
        XCTAssertEqual(plan.urgencyWrite?.plannedValue, "2")
        XCTAssertEqual(plan.pickWrite?.plannedValue, "1")
        XCTAssertEqual(plan.goodWrite?.plannedValue, "true")
        XCTAssertEqual(plan.sourceMembers.first?.qualitySidecarPath, fixture.qualitySidecar.path)

        let progress = try decodeProgress(at: result.normalizeResult.report.artifacts.progressPath)
        XCTAssertTrue(
            progress.contains {
                $0.stage == .xmpTarget
                    && $0.qualityTier == .good
                    && $0.ratingWrite?.plannedValue == "4"
                    && $0.labelWrite?.plannedValue == "Green"
                    && $0.pickWrite?.plannedValue == "1"
            }
        )

        let taggingStamp = try XCTUnwrap(RawSidecarExportStamp.contents(sidecarPath: fixture.taggingSidecar.path))
        let qualityStamp = try XCTUnwrap(RawSidecarExportStamp.contents(sidecarPath: fixture.qualitySidecar.path))
        XCTAssertEqual(taggingStamp, qualityStamp)
        XCTAssertEqual(taggingStamp.rating, "4")
        XCTAssertEqual(taggingStamp.label, "Green")
        XCTAssertEqual(taggingStamp.urgency, "2")
        XCTAssertEqual(taggingStamp.pick, "1")
        XCTAssertEqual(taggingStamp.good, "true")
        XCTAssertEqual(taggingStamp.qualityTier, .good)
    }

    func testQualityKeywordsBypassVocabularyAndNormalizationProvenance() throws {
        let fixture = try makeFixture(confidence: "high", includesQualityRenamingVocabulary: true)

        let result = try NormalizeAndWritePipeline(logger: Logger(sink: { _ in })).run(
            mode: .fromJSON(path: fixture.jsonRoot.path),
            configuration: fixture.configuration
        )

        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: fixture.targetXMP.path)
        XCTAssertTrue(snapshot.flatKeywords.contains("AI Quality good"))
        XCTAssertTrue(snapshot.hierarchicalKeywords.contains("AI Quality|good"))
        XCTAssertFalse(snapshot.flatKeywords.contains("Renamed Quality"))

        let writePlan = try XCTUnwrap(result.normalizeResult.report.xmpWritePlans.first)
        XCTAssertFalse(writePlan.flatKeywordProvenance.contains { $0.term.hasPrefix("AI Quality") })
        XCTAssertFalse(writePlan.hierarchicalKeywordProvenance.contains { $0.term.hasPrefix("AI Quality") })
        XCTAssertFalse(
            result.normalizeResult.report.perAssetDecisions.contains {
                $0.flatKeyword == "AI Quality good" || $0.hierarchicalKeyword == "AI Quality|good"
            }
        )
    }

    func testNormalizePreservesExistingQualityAndForeignKeywords() throws {
        let fixture = try makeFixture(confidence: "high", existingXMP: existingQualityKeywordsXMP)

        _ = try NormalizeAndWritePipeline(logger: Logger(sink: { _ in })).run(
            mode: .fromJSON(path: fixture.jsonRoot.path),
            configuration: fixture.configuration
        )

        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: fixture.targetXMP.path)
        XCTAssertEqual(snapshot.flatKeywords, ["foreign flat", "AI Quality good", "Birds"])
        XCTAssertEqual(
            snapshot.hierarchicalKeywords,
            ["Foreign|Tree", "AI Quality|good", "Subject|Wildlife|Birds"]
        )
    }

    func testNormalizePlansAgainstCurrentForeignScalarsAndPreservesThem() throws {
        let fixture = try makeFixture(confidence: "high", existingXMP: existingForeignQualityScalarsXMP)

        let result = try NormalizeAndWritePipeline(logger: Logger(sink: { _ in })).run(
            mode: .fromJSON(path: fixture.jsonRoot.path),
            configuration: fixture.configuration
        )

        let plan = try XCTUnwrap(result.normalizeResult.report.xmpWritePlans.first?.xmpChangePlan)
        XCTAssertEqual(plan.ratingWrite?.action, .skipExisting)
        XCTAssertEqual(plan.ratingWrite?.existingValue, "5")
        XCTAssertEqual(plan.labelWrite?.action, .skipExisting)
        XCTAssertEqual(plan.labelWrite?.existingValue, "Blue")
        XCTAssertEqual(plan.urgencyWrite?.action, .skipExisting)
        XCTAssertEqual(plan.pickWrite?.action, .skipExisting)
        XCTAssertEqual(plan.goodWrite?.action, .skipExisting)

        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: fixture.targetXMP.path)
        XCTAssertEqual(snapshot.rating, "5")
        XCTAssertEqual(snapshot.label, "Blue")
        XCTAssertEqual(snapshot.urgency, "3")
        XCTAssertEqual(snapshot.pick, "-1")
        XCTAssertEqual(snapshot.good, "false")
        let stamp = try XCTUnwrap(RawSidecarExportStamp.contents(sidecarPath: fixture.taggingSidecar.path))
        XCTAssertNil(stamp.rating)
        XCTAssertNil(stamp.label)
        XCTAssertNil(stamp.urgency)
        XCTAssertNil(stamp.pick)
        XCTAssertNil(stamp.good)
        XCTAssertEqual(stamp.qualityTier, .good)
    }

    func testSessionOnlyQualityPreviewOmitsUnresolvedScalarsWithoutReadingXMP() throws {
        let fixture = try makeFixture(confidence: "high")
        let counter = NormalizeSnapshotReadCounter()
        let pipeline = NormalizePipeline(snapshotReader: { path in
            counter.recordRead()
            return .empty(targetPath: path, exists: false)
        })

        let result = try pipeline.runSessionOnly(
            mode: .fromJSON(path: fixture.jsonRoot.path),
            configuration: fixture.configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            sessionID: "quality-session-preview"
        )

        XCTAssertEqual(counter.count, 0)
        let plan = try XCTUnwrap(result.session.xmpWritePlans.first?.xmpChangePlan)
        XCTAssertEqual(plan.qualityTier, .good)
        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["Birds", "AI Quality good"])
        XCTAssertEqual(
            plan.hierarchicalKeywordsToAdd.map(\.term),
            ["Subject|Wildlife|Birds", "AI Quality|good"]
        )
        XCTAssertNil(plan.ratingWrite)
        XCTAssertNil(plan.labelWrite)
        XCTAssertNil(plan.urgencyWrite)
        XCTAssertNil(plan.pickWrite)
        XCTAssertNil(plan.goodWrite)
        XCTAssertTrue(plan.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.targetXMP.path))
    }

    func testUngradedReasonFlowsThroughNormalizeReportAndProgress() throws {
        var fixture = try makeFixture(confidence: "low")
        fixture.configuration.dryRun = true

        let result = try NormalizePipeline().runDryRun(
            mode: .fromJSON(path: fixture.jsonRoot.path),
            configuration: fixture.configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_001),
            sessionID: "quality-ungraded"
        )

        let plan = try XCTUnwrap(result.report.xmpWritePlans.first?.xmpChangePlan)
        XCTAssertNil(plan.qualityTier)
        XCTAssertEqual(plan.qualityExplanation?.first, "ungraded reason=below_minimum_confidence")
        XCTAssertTrue(plan.qualityExplanation?.contains("confidence=low") == true)
        XCTAssertTrue(
            try decodeProgress(at: result.report.artifacts.progressPath).contains {
                $0.qualityExplanation?.first == "ungraded reason=below_minimum_confidence"
            }
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.targetXMP.path))
    }

    func testLegacySessionWithoutGradingOrScalarRowsStillDecodes() throws {
        var fixture = try makeFixture(confidence: "high")
        fixture.configuration.qualityGrading = .builtInDefaults
        fixture.configuration.dryRun = true
        let result = try NormalizePipeline().runDryRun(
            mode: .fromJSON(path: fixture.jsonRoot.path),
            configuration: fixture.configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_002),
            sessionID: "legacy-quality-session"
        )
        let sessionURL = URL(fileURLWithPath: try XCTUnwrap(result.session.artifacts.sessionPath))
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: sessionURL)) as? [String: Any]
        )
        var resolved = try XCTUnwrap(object["resolved_configuration"] as? [String: Any])
        resolved.removeValue(forKey: "quality_grading")
        object["resolved_configuration"] = resolved
        var writePlans = try XCTUnwrap(object["xmp_write_plans"] as? [[String: Any]])
        var changePlan = try XCTUnwrap(writePlans[0]["xmp_change_plan"] as? [String: Any])
        for key in [
            "rating_write", "label_write", "urgency_write", "pick_write", "good_write",
            "quality_explanation", "quality_tier",
        ] {
            changePlan.removeValue(forKey: key)
        }
        writePlans[0]["xmp_change_plan"] = changePlan
        object["xmp_write_plans"] = writePlans
        let legacyURL = fixture.root.appendingPathComponent("legacy-normalization-session.json")
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: legacyURL)

        let decoded = try NormalizationSessionReader().read(from: legacyURL.path)
        XCTAssertEqual(decoded.resolvedConfiguration.qualityGrading, .builtInDefaults)
        XCTAssertNil(decoded.xmpWritePlans.first?.xmpChangePlan.qualityTier)
        XCTAssertNil(decoded.xmpWritePlans.first?.xmpChangePlan.ratingWrite)
    }

    private func makeFixture(
        confidence: String,
        existingXMP: String? = nil,
        includesQualityRenamingVocabulary: Bool = false
    ) throws -> NormalizeQualityFixture {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let jsonRoot = root.appendingPathComponent("json")
        let sourceRoot = root.appendingPathComponent("source")
        let output = root.appendingPathComponent("output")
        let sourceURL = try writeTestImage("Bird.JPG", in: sourceRoot)
        let source = try scannedSourceImage(sourceURL)
        let taggingSidecar = try writeSidecar(
            source: source,
            named: "Bird.JPG.ai.json",
            in: jsonRoot,
            modelRuns: [taggingRun()],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let qualitySidecar = try writeSidecar(
            source: source,
            named: "Bird.JPG.quality.ai.json",
            in: jsonRoot,
            modelRuns: [qualityRun(confidence: confidence)],
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let targetXMP = output.appendingPathComponent("Bird.xmp")
        if let existingXMP {
            try existingXMP.write(to: targetXMP, atomically: true, encoding: .utf8)
        }

        var vocabularyEntries = minimalVocabularyEntries()
        if includesQualityRenamingVocabulary {
            vocabularyEntries.append(
                VocabularyEntry(
                    canonicalPath: "Workflow",
                    flatKeyword: "Workflow",
                    namespace: .event,
                    parentPath: nil,
                    requiresReview: false,
                    autoApplyAllowed: false,
                    directApplyPolicy: .withhold,
                    propagationScope: PropagationScope.none,
                    specificity: .broad
                )
            )
            vocabularyEntries.append(
                VocabularyEntry(
                    canonicalPath: "Workflow|Renamed Quality",
                    flatKeyword: "Renamed Quality",
                    namespace: .event,
                    parentPath: "Workflow",
                    synonyms: ["AI Quality good"],
                    requiresReview: false,
                    autoApplyAllowed: true,
                    directApplyPolicy: .allow,
                    propagationScope: PropagationScope.none,
                    specificity: .broad
                )
            )
        }
        let vocabularyPath = root.appendingPathComponent("vocabulary.json")
        try vocabularyData(entries: vocabularyEntries).write(to: vocabularyPath)

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

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .controlledVocabulary
        configuration.vocabularyPath = vocabularyPath.path
        configuration.normalizationMode = .singleImage
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = output.path
        configuration.backupSidecars = false
        configuration.xmpConflictPolicy = .merge
        configuration.qualityGrading = ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: .preserve,
            policy: policy
        )

        return NormalizeQualityFixture(
            root: root,
            jsonRoot: jsonRoot,
            targetXMP: targetXMP,
            taggingSidecar: taggingSidecar,
            qualitySidecar: qualitySidecar,
            configuration: configuration
        )
    }

    private func scannedSourceImage(_ url: URL) throws -> SourceImage {
        let scan = try ImageScanner().scan(inputPath: url.path, recursive: false, identityPolicy: .sha256)
        var source = try XCTUnwrap(scan.images.first)
        source.relativePath = "Bird.JPG"
        return source
    }

    private func writeSidecar(
        source: SourceImage,
        named name: String,
        in root: URL,
        modelRuns: [ModelRunRecord],
        createdAt: Date
    ) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        let sidecar = RawJSONSidecar(
            source: source,
            runConfiguration: .builtInDefaults,
            modelRuns: modelRuns,
            createdAt: createdAt
        )
        try RawJSONSidecarDocument(sidecar: sidecar).encodedData().write(to: url)
        return url
    }

    private func taggingRun() -> ModelRunRecord {
        modelRun(
            parsedResponseJSON: .object([
                "main_subjects": .array([
                    .object([
                        "term": .string("bird"),
                        "confidence": .string("high"),
                        "evidence": .string("visible bird"),
                    ])
                ])
            ]),
            promptVersion: "prompt.tagging"
        )
    }

    private func qualityRun(confidence: String) -> ModelRunRecord {
        modelRun(
            parsedResponseJSON: .object([
                "quality_assessment": .object([
                    "composition": .string("strong"),
                    "confidence": .string(confidence),
                    "concerns": .array([]),
                    "focus": .string("strong"),
                    "overall_effectiveness": .string("acceptable"),
                    "strengths": .array([]),
                ])
            ]),
            promptVersion: "prompt.quality"
        )
    }

    private func modelRun(parsedResponseJSON: JSONValue, promptVersion: String) -> ModelRunRecord {
        ModelRunRecord(
            inputRole: .wholeImage,
            model: "test:model",
            modelDigest: "sha256:test",
            runtime: "test",
            runtimeVersion: "1",
            promptVersion: promptVersion,
            promptSHA256: String(repeating: "a", count: 64),
            responseSchemaVersion: "schema.test",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "b", count: 64),
            rawResponseText: "fixture",
            parsedResponseJSON: parsedResponseJSON,
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func decodeProgress(at path: String) throws -> [NormalizationProgressRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try String(decoding: Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
            .split(separator: "\n")
            .map { try decoder.decode(NormalizationProgressRecord.self, from: Data($0.utf8)) }
    }
}

private struct NormalizeQualityFixture {
    var root: URL
    var jsonRoot: URL
    var targetXMP: URL
    var taggingSidecar: URL
    var qualitySidecar: URL
    var configuration: ResolvedNormalizationConfiguration
}

private final class NormalizeSnapshotReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func recordRead() {
        lock.withLock { value += 1 }
    }
}

private let existingQualityKeywordsXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
               xmlns:dc="http://purl.org/dc/elements/1.1/"
               xmlns:lr="http://ns.adobe.com/lightroom/1.0/">
        <rdf:Description rdf:about="">
          <dc:subject>
            <rdf:Bag>
              <rdf:li>foreign flat</rdf:li>
              <rdf:li>AI Quality good</rdf:li>
            </rdf:Bag>
          </dc:subject>
          <lr:hierarchicalSubject>
            <rdf:Bag>
              <rdf:li>Foreign|Tree</rdf:li>
              <rdf:li>AI Quality|good</rdf:li>
            </rdf:Bag>
          </lr:hierarchicalSubject>
        </rdf:Description>
      </rdf:RDF>
    </x:xmpmeta>
    """

private let existingForeignQualityScalarsXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
               xmlns:xmp="http://ns.adobe.com/xap/1.0/"
               xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
               xmlns:xmpDM="http://ns.adobe.com/xmp/1.0/DynamicMedia/">
        <rdf:Description rdf:about=""
                         xmp:Rating="5"
                         xmp:Label="Blue"
                         photoshop:Urgency="3"
                         xmpDM:pick="-1"
                         xmpDM:good="false"/>
      </rdf:RDF>
    </x:xmpmeta>
    """
