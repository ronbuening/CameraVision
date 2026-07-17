import Foundation
import XCTest

@testable import AISidecarCore

final class XMPQualityExportIntegrationTests: XCTestCase {
    func testOwnedEngineWritesCustomGoodGradeAndStampsTaggingAndQualitySidecars() throws {
        let fixture = try makeFixture(confidence: "high", existingXMP: qualityExistingXMP)
        let preWriteSnapshot = try OwnedXMPSidecarEngine().readSnapshot(at: fixture.target.path)
        let configuration = qualityConfiguration(output: fixture.output, dryRun: false)

        let result = try XMPExportPipeline(
            logger: Logger(sink: { _ in }),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            filenameSuffix: { "quality" }
        ).runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)
        XCTAssertEqual(plan.status, .planned)
        XCTAssertEqual(plan.qualityTier, .good)
        XCTAssertEqual(plan.ratingWrite?.plannedValue, "4")
        XCTAssertEqual(plan.ratingWrite?.action, .write)
        XCTAssertEqual(plan.labelWrite?.plannedValue, "Green")
        XCTAssertEqual(plan.labelWrite?.action, .write)
        XCTAssertEqual(plan.urgencyWrite?.plannedValue, "2")
        XCTAssertEqual(plan.urgencyWrite?.action, .write)
        XCTAssertTrue(plan.qualityExplanation?.contains("tier=good") == true)
        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["AI Quality good"])
        XCTAssertEqual(plan.hierarchicalKeywordsToAdd.map(\.term), ["AI Quality|good"])
        XCTAssertEqual(plan.sourceMembers.first?.qualitySidecarPath, fixture.qualitySidecar.path)

        let report = try XCTUnwrap(result.report?.targetReports.first)
        XCTAssertEqual(report.status, .written)
        XCTAssertEqual(report.writeResult?.resultingRating, "4")
        XCTAssertEqual(report.writeResult?.resultingLabel, "Green")
        XCTAssertEqual(report.writeResult?.resultingUrgency, "2")

        let postWriteSnapshot = try OwnedXMPSidecarEngine().readSnapshot(at: fixture.target.path)
        XCTAssertEqual(postWriteSnapshot.rating, "4")
        XCTAssertEqual(postWriteSnapshot.label, "Green")
        XCTAssertEqual(postWriteSnapshot.urgency, "2")
        XCTAssertEqual(postWriteSnapshot.flatKeywords, ["existing bird", "AI Quality good"])
        XCTAssertEqual(postWriteSnapshot.hierarchicalKeywords, ["existing habitat", "AI Quality|good"])
        XCTAssertEqual(postWriteSnapshot.unmanagedContentFingerprint, preWriteSnapshot.unmanagedContentFingerprint)
        let writtenXMP = try String(contentsOf: fixture.target, encoding: .utf8)
        XCTAssertTrue(writtenXMP.contains("<crs:Exposure2012>+0.35</crs:Exposure2012>"))
        XCTAssertTrue(writtenXMP.contains("<crs:Contrast2012>12</crs:Contrast2012>"))

        let taggingStamp = try XCTUnwrap(
            RawSidecarExportStamp.contents(sidecarPath: fixture.taggingSidecar.path)
        )
        let qualityStamp = try XCTUnwrap(
            RawSidecarExportStamp.contents(sidecarPath: fixture.qualitySidecar.path)
        )
        XCTAssertEqual(taggingStamp, qualityStamp)
        XCTAssertEqual(taggingStamp.targetXMPPath, fixture.target.path)
        XCTAssertEqual(taggingStamp.rating, "4")
        XCTAssertEqual(taggingStamp.label, "Green")
        XCTAssertEqual(taggingStamp.urgency, "2")
        XCTAssertEqual(taggingStamp.qualityTier, .good)
    }

    func testDryRunPlansQualityMetadataWithoutCreatingXMPOrStampingSidecars() throws {
        let fixture = try makeFixture(confidence: "high", existingXMP: nil)
        let taggingBefore = try Data(contentsOf: fixture.taggingSidecar)
        let qualityBefore = try Data(contentsOf: fixture.qualitySidecar)
        let configuration = qualityConfiguration(output: fixture.output, dryRun: true)

        let result = try XMPExportPipeline(
            logger: Logger(sink: { _ in }),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            filenameSuffix: { "dry-run" }
        ).runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)
        XCTAssertEqual(plan.status, .planned)
        XCTAssertEqual(plan.qualityTier, .good)
        XCTAssertEqual(plan.ratingWrite?.plannedValue, "4")
        XCTAssertEqual(plan.labelWrite?.plannedValue, "Green")
        XCTAssertEqual(plan.urgencyWrite?.plannedValue, "2")
        XCTAssertEqual(plan.preview?.resultingRating, "4")
        XCTAssertEqual(plan.preview?.resultingLabel, "Green")
        XCTAssertEqual(plan.preview?.resultingUrgency, "2")
        let encodedPlan = try JSONCoding.documentEncoder().encode(result.changePlan)
        let planObject = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: encodedPlan) as? [String: Any])?["target_plans"]
                as? [[String: Any]]
        ).first
        XCTAssertEqual((planObject?["rating_write"] as? [String: Any])?["action"] as? String, "write")
        XCTAssertEqual((planObject?["label_write"] as? [String: Any])?["planned_value"] as? String, "Green")
        XCTAssertEqual((planObject?["urgency_write"] as? [String: Any])?["planned_value"] as? String, "2")
        XCTAssertEqual((planObject?["quality_explanation"] as? [String])?.first, "tier=good")
        XCTAssertNil(result.report)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.target.path))
        XCTAssertEqual(try Data(contentsOf: fixture.taggingSidecar), taggingBefore)
        XCTAssertEqual(try Data(contentsOf: fixture.qualitySidecar), qualityBefore)
        XCTAssertFalse(RawSidecarExportStamp.isStamped(sidecarPath: fixture.taggingSidecar.path))
        XCTAssertFalse(RawSidecarExportStamp.isStamped(sidecarPath: fixture.qualitySidecar.path))
    }

    func testBelowMinimumConfidenceIsReportedUngradedWithoutScalarWrites() throws {
        let fixture = try makeFixture(confidence: "low", existingXMP: nil)
        let configuration = qualityConfiguration(output: fixture.output, dryRun: true)

        let result = try XMPExportPipeline(
            logger: Logger(sink: { _ in }),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            filenameSuffix: { "ungraded" }
        ).runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)
        XCTAssertEqual(plan.status, .planned)
        XCTAssertNil(plan.qualityTier)
        XCTAssertNil(plan.ratingWrite)
        XCTAssertNil(plan.labelWrite)
        XCTAssertNil(plan.urgencyWrite)
        XCTAssertEqual(plan.flatKeywordsToAdd, [])
        XCTAssertEqual(plan.hierarchicalKeywordsToAdd, [])
        XCTAssertEqual(plan.qualityExplanation?.first, "ungraded reason=below_minimum_confidence")
        XCTAssertTrue(plan.qualityExplanation?.contains("confidence=low") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.target.path))
        XCTAssertFalse(RawSidecarExportStamp.isStamped(sidecarPath: fixture.taggingSidecar.path))
        XCTAssertFalse(RawSidecarExportStamp.isStamped(sidecarPath: fixture.qualitySidecar.path))
    }

    func testPreservedForeignScalarsRemainInXMPButAreNotClaimedByStamp() throws {
        let fixture = try makeFixture(confidence: "high", existingXMP: qualityForeignScalarsXMP)
        let configuration = qualityConfiguration(output: fixture.output, dryRun: false)

        let result = try XMPExportPipeline(logger: Logger(sink: { _ in })).runFromJSON(
            fromJSONPath: fixture.jsonRoot.path,
            configuration: configuration
        )

        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)
        XCTAssertEqual(plan.ratingWrite?.action, .skipExisting)
        XCTAssertEqual(plan.labelWrite?.action, .skipExisting)
        XCTAssertEqual(plan.urgencyWrite?.action, .skipExisting)
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: fixture.target.path)
        XCTAssertEqual(snapshot.rating, "5")
        XCTAssertEqual(snapshot.label, "Blue")
        XCTAssertEqual(snapshot.urgency, "3")
        let stamp = try XCTUnwrap(
            RawSidecarExportStamp.contents(sidecarPath: fixture.taggingSidecar.path)
        )
        XCTAssertNil(stamp.rating)
        XCTAssertNil(stamp.label)
        XCTAssertNil(stamp.urgency)
        XCTAssertEqual(stamp.qualityTier, .good)
    }

    func testQualityOnlySidecarWithoutTaggingSiblingWritesAndStamps() throws {
        let fixture = try makeFixture(confidence: "high", existingXMP: nil)
        try FileManager.default.removeItem(at: fixture.taggingSidecar)
        let configuration = qualityConfiguration(output: fixture.output, dryRun: false)

        let result = try XMPExportPipeline(logger: Logger(sink: { _ in })).runFromJSON(
            fromJSONPath: fixture.jsonRoot.path,
            configuration: configuration
        )

        XCTAssertEqual(result.report?.targetReports.first?.status, .created)
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: fixture.target.path)
        XCTAssertEqual(snapshot.rating, "4")
        XCTAssertEqual(snapshot.label, "Green")
        XCTAssertEqual(snapshot.urgency, "2")
        let stamp = try XCTUnwrap(
            RawSidecarExportStamp.contents(sidecarPath: fixture.qualitySidecar.path)
        )
        XCTAssertEqual(stamp.qualityTier, .good)
        XCTAssertEqual(stamp.rating, "4")
    }

    func testDisabledGradingPreservesOnlyPriorOwnershipThatStillMatchesXMP() throws {
        let fixture = try makeFixture(confidence: "high", existingXMP: qualityPartiallyEditedScalarsXMP)
        try stampFixture(
            fixture,
            rating: "4",
            label: "Green",
            qualityTier: .good
        )
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.outputDir = fixture.output.path
        configuration.backupSidecars = false
        configuration.xmpConflictPolicy = .merge

        _ = try XMPExportPipeline(logger: Logger(sink: { _ in })).runFromJSON(
            fromJSONPath: fixture.jsonRoot.path,
            configuration: configuration
        )

        let stamp = try XCTUnwrap(
            RawSidecarExportStamp.contents(sidecarPath: fixture.taggingSidecar.path)
        )
        XCTAssertEqual(stamp.rating, "4")
        XCTAssertNil(stamp.label)
        XCTAssertEqual(stamp.qualityTier, .good)
    }

    func testEnabledUngradedRunClearsPriorTierFromBothContributorStamps() throws {
        let fixture = try makeFixture(confidence: "low", existingXMP: qualityExistingXMP)
        try stampFixture(fixture, qualityTier: .good)
        let configuration = qualityConfiguration(output: fixture.output, dryRun: false)

        _ = try XMPExportPipeline(logger: Logger(sink: { _ in })).runFromJSON(
            fromJSONPath: fixture.jsonRoot.path,
            configuration: configuration
        )

        for path in [fixture.taggingSidecar.path, fixture.qualitySidecar.path] {
            let stamp = try XCTUnwrap(RawSidecarExportStamp.contents(sidecarPath: path))
            XCTAssertNil(stamp.qualityTier)
        }
    }

    func testProgressRecordsCarryScalarWriteIndicators() throws {
        let written = try makeFixture(confidence: "high", existingXMP: nil)
        let writtenResult = try XMPExportPipeline(logger: Logger(sink: { _ in })).runFromJSON(
            fromJSONPath: written.jsonRoot.path,
            configuration: qualityConfiguration(output: written.output, dryRun: false)
        )
        let writtenRecord = try progressRecordObject(at: XCTUnwrap(writtenResult.progressLogPath))
        XCTAssertEqual(writtenRecord["status"] as? String, "created")
        XCTAssertEqual(writtenRecord["wrote_rating"] as? Bool, true)
        XCTAssertEqual(writtenRecord["wrote_label"] as? Bool, true)
        XCTAssertEqual(writtenRecord["wrote_urgency"] as? Bool, true)

        let skipped = try makeFixture(confidence: "high", existingXMP: qualityForeignScalarsXMP)
        let skippedResult = try XMPExportPipeline(logger: Logger(sink: { _ in })).runFromJSON(
            fromJSONPath: skipped.jsonRoot.path,
            configuration: qualityConfiguration(output: skipped.output, dryRun: false)
        )
        let skippedRecord = try progressRecordObject(at: XCTUnwrap(skippedResult.progressLogPath))
        XCTAssertEqual(skippedRecord["wrote_rating"] as? Bool, false)
        XCTAssertEqual(skippedRecord["wrote_label"] as? Bool, false)
        XCTAssertEqual(skippedRecord["wrote_urgency"] as? Bool, false)

        let disabled = try makeFixture(confidence: "high", existingXMP: qualityForeignScalarsXMP)
        var disabledConfiguration = ResolvedXMPExportConfiguration.builtInDefaults
        disabledConfiguration.outputDir = disabled.output.path
        disabledConfiguration.backupSidecars = false
        disabledConfiguration.xmpConflictPolicy = .merge
        let disabledResult = try XMPExportPipeline(logger: Logger(sink: { _ in })).runFromJSON(
            fromJSONPath: disabled.jsonRoot.path,
            configuration: disabledConfiguration
        )
        let disabledRecord = try progressRecordObject(at: XCTUnwrap(disabledResult.progressLogPath))
        XCTAssertNil(disabledRecord["wrote_rating"])
        XCTAssertNil(disabledRecord["wrote_label"])
        XCTAssertNil(disabledRecord["wrote_urgency"])
    }

    private struct Fixture {
        let jsonRoot: URL
        let output: URL
        let source: URL
        let taggingSidecar: URL
        let qualitySidecar: URL
        let target: URL
    }

    private func makeFixture(confidence: String, existingXMP: String?) throws -> Fixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aisidecar-quality-export-tests")
            .appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let jsonRoot = root.appendingPathComponent("sidecars")
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: jsonRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let source = root.appendingPathComponent("Bird.JPG")
        let sourceData = Data("source image fixture".utf8)
        try sourceData.write(to: source, options: .atomic)
        let identity = try SourceIdentityCalculator.compute(for: source, policy: .sha256)
        let sourceImage = SourceImage(
            path: source.path,
            relativePath: "Bird.JPG",
            fileName: "Bird.JPG",
            fileExtension: "JPG",
            fileSize: Int64(sourceData.count),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: .jpg,
            identity: identity
        )

        let taggingSidecar = jsonRoot.appendingPathComponent("Bird.JPG.ai.json")
        try writeSidecar(
            at: taggingSidecar,
            source: sourceImage,
            profile: .tagging,
            modelRuns: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let qualitySidecar = jsonRoot.appendingPathComponent("Bird.JPG.quality.ai.json")
        try writeSidecar(
            at: qualitySidecar,
            source: sourceImage,
            profile: .qualityOnly,
            modelRuns: [qualityRun(confidence: confidence)],
            createdAt: Date(timeIntervalSince1970: 1_700_000_200)
        )

        let target = output.appendingPathComponent("Bird.xmp")
        if let existingXMP {
            try Data(existingXMP.utf8).write(to: target, options: .atomic)
        }
        return Fixture(
            jsonRoot: jsonRoot,
            output: output,
            source: source,
            taggingSidecar: taggingSidecar,
            qualitySidecar: qualitySidecar,
            target: target
        )
    }

    private func writeSidecar(
        at url: URL,
        source: SourceImage,
        profile: ModelTaskProfile,
        modelRuns: [ModelRunRecord],
        createdAt: Date
    ) throws {
        let sidecar = RawJSONSidecar(
            source: source,
            runConfiguration: ResolvedRunConfiguration.builtInDefaults.with(taskProfile: profile),
            modelRuns: modelRuns,
            createdAt: createdAt
        )
        let data = try RawJSONSidecarDocument(sidecar: sidecar).encodedData()
        try data.write(to: url, options: .atomic)
    }

    private func qualityRun(confidence: String) -> ModelRunRecord {
        let qualityAssessment: JSONValue = .object([
            "composition": .string("strong"),
            "confidence": .string(confidence),
            "concerns": .array([]),
            "focus": .string("strong"),
            "overall_effectiveness": .string("acceptable"),
            "strengths": .array([]),
        ])
        return ModelRunRecord(
            inputRole: .wholeImage,
            model: "test:model",
            modelDigest: "sha256:test",
            runtime: "test",
            runtimeVersion: "1",
            promptVersion: "prompt.whole_image.quality",
            promptSHA256: String(repeating: "a", count: 64),
            responseSchemaVersion: "schema.test",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "b", count: 64),
            rawResponseText: "fixture",
            parsedResponseJSON: .object(["quality_assessment": qualityAssessment]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func qualityConfiguration(output: URL, dryRun: Bool) -> ResolvedXMPExportConfiguration {
        var policy = QualityGradingPolicy(
            minimumConfidence: .medium,
            writeRating: true,
            writeLabel: true,
            writeUrgency: true,
            writeKeywords: true
        )
        policy.labelMap[.good] = "Green"
        policy.urgencyMap[.good] = 2

        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.outputDir = output.path
        configuration.dryRun = dryRun
        configuration.sourceVerification = .fail
        configuration.backupSidecars = false
        configuration.xmpConflictPolicy = .merge
        configuration.qualityGrading = ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: .preserve,
            policy: policy
        )
        return configuration
    }

    private func progressRecordObject(at path: String) throws -> [String: Any] {
        let contents = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        let line = try XCTUnwrap(
            contents.split(separator: "\n").last.map(String.init)
        )
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
    }

    private func stampFixture(
        _ fixture: Fixture,
        rating: String? = nil,
        label: String? = nil,
        urgency: String? = nil,
        qualityTier: QualityTier? = nil
    ) throws {
        let contents = RawSidecarExportStamp.Contents(
            targetXMPPath: fixture.target.path,
            xmpSHA256: String(repeating: "d", count: 64),
            writerRecipeVersion: OwnedXMPSidecarEngine.writerRecipeVersion,
            engineVersion: OwnedXMPSidecarEngine.engineVersion,
            exportedAt: Date(timeIntervalSince1970: 1_750_000_000),
            rating: rating,
            label: label,
            urgency: urgency,
            qualityTier: qualityTier
        )
        try RawSidecarExportStamp.stamp(sidecarPath: fixture.taggingSidecar.path, contents: contents)
        try RawSidecarExportStamp.stamp(sidecarPath: fixture.qualitySidecar.path, contents: contents)
    }
}

private let qualityExistingXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="fixture">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
               xmlns:dc="http://purl.org/dc/elements/1.1/"
               xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
               xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/">
        <rdf:Description rdf:about="">
          <dc:subject>
            <rdf:Bag>
              <rdf:li>existing bird</rdf:li>
            </rdf:Bag>
          </dc:subject>
          <lr:hierarchicalSubject>
            <rdf:Bag>
              <rdf:li>existing habitat</rdf:li>
            </rdf:Bag>
          </lr:hierarchicalSubject>
          <crs:Exposure2012>+0.35</crs:Exposure2012>
          <crs:Contrast2012>12</crs:Contrast2012>
        </rdf:Description>
      </rdf:RDF>
    </x:xmpmeta>
    """

private let qualityForeignScalarsXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
               xmlns:xmp="http://ns.adobe.com/xap/1.0/"
               xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
        <rdf:Description rdf:about="" xmp:Rating="5" xmp:Label="Blue" photoshop:Urgency="3"/>
      </rdf:RDF>
    </x:xmpmeta>
    """

private let qualityPartiallyEditedScalarsXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
               xmlns:xmp="http://ns.adobe.com/xap/1.0/">
        <rdf:Description rdf:about="" xmp:Rating="4" xmp:Label="Blue"/>
      </rdf:RDF>
    </x:xmpmeta>
    """
