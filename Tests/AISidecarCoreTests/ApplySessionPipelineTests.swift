import Foundation
import XCTest
@testable import AISidecarCore

final class ApplySessionPipelineTests: XCTestCase {
    func testApplySessionWritesStoredDecisionsAndMergesCurrentXMP() throws {
        let fixture = try makeSessionFixture(dryRun: false)
        let output = try temporaryDirectory()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try existingDevelopSettingsXMPForApplySession.write(
            to: output.appendingPathComponent("Bird.xmp"),
            atomically: true,
            encoding: .utf8
        )

        let result = try applyPipeline().run(
            sessionPath: fixture.sessionPath,
            configuration: applyConfiguration(outputDir: output),
            timestamp: Date(timeIntervalSince1970: 1_800_000_500)
        )

        let target = output.appendingPathComponent("Bird.xmp")
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: target.path)
        XCTAssertEqual(snapshot.flatKeywords, ["existing bird", "Birds"])
        XCTAssertEqual(snapshot.hierarchicalKeywords, ["existing habitat", "Subject|Wildlife|Birds"])
        XCTAssertEqual(result.exportReport?.targetReports.first?.status, .written)
        XCTAssertEqual(result.report.xmpExportReport?.engine.engineName, OwnedXMPSidecarEngine.engineName)
        XCTAssertTrue(result.report.xmpExportReport?.targetReports.first?.validation?.unmanagedContentPreserved == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.report.artifacts.reportPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.report.artifacts.summaryPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.report.artifacts.progressPath))
        XCTAssertEqual(
            try decodeProgress(at: result.report.artifacts.progressPath).map(\.stage),
            [.inputResolution, .xmpPlanning, .xmpTarget, .artifactWrite]
        )
    }

    func testApplySessionRejectsStaleSourcesUnlessExplicitlyAllowed() throws {
        let fixture = try makeSessionFixture(dryRun: false)
        try Data("changed source bytes".utf8).write(to: fixture.sourceURL)

        let rejectedOutput = try temporaryDirectory()
        let rejected = try applyPipeline().run(
            sessionPath: fixture.sessionPath,
            configuration: applyConfiguration(outputDir: rejectedOutput),
            timestamp: Date(timeIntervalSince1970: 1_800_000_600)
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: rejectedOutput.appendingPathComponent("Bird.xmp").path))
        XCTAssertEqual(rejected.exportReport?.targetReports.first?.status, .failed)
        XCTAssertEqual(rejected.exportReport?.targetReports.first?.errors.map(\.code), [.sessionStale])
        XCTAssertEqual(rejected.report.errors.map(\.code), [.sessionStale])

        let allowedOutput = try temporaryDirectory()
        var allowedConfiguration = applyConfiguration(outputDir: allowedOutput)
        allowedConfiguration.allowStale = true
        let allowed = try applyPipeline().run(
            sessionPath: fixture.sessionPath,
            configuration: allowedConfiguration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_700)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: allowedOutput.appendingPathComponent("Bird.xmp").path))
        XCTAssertEqual(allowed.exportReport?.targetReports.first?.status, .created)
        XCTAssertTrue(allowed.report.warnings.contains { $0.code == .sessionStale })
        XCTAssertTrue(
            allowed.report.xmpWritePlans.first?.xmpChangePlan.sourceVerificationWarnings.contains {
                $0.code == .sessionStale
            } == true
        )
    }

    func testApplySessionDryRunResolvesMovedSourceRootAndRecomputesTargetPath() throws {
        let oldPlanOutput = try temporaryDirectory()
        let fixture = try makeSessionFixture(dryRun: true, normalizationOutput: oldPlanOutput)
        let movedRoot = try temporaryDirectory()
        let movedSource = movedRoot.appendingPathComponent("Bird.JPG")
        try FileManager.default.moveItem(at: fixture.sourceURL, to: movedSource)

        let applyOutput = try temporaryDirectory()
        var configuration = applyConfiguration(outputDir: applyOutput)
        configuration.dryRun = true
        configuration.sourceRoot = movedRoot.path

        let result = try applyPipeline().run(
            sessionPath: fixture.sessionPath,
            configuration: configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_800)
        )

        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)
        XCTAssertEqual(plan.targetXMPPath, applyOutput.appendingPathComponent("Bird.xmp").path)
        XCTAssertEqual(plan.sourceMembers.first?.sourcePath, movedSource.path)
        XCTAssertNotNil(plan.preview)
        XCTAssertTrue(plan.groupWarnings.contains { $0.message.contains("recomputed XMP target") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: applyOutput.appendingPathComponent("Bird.xmp").path))
        XCTAssertEqual(result.exportReport?.targetReports.first?.status, .dryRun)
    }

    func testApplySessionInterruptedAfterSourceResolutionDoesNotWriteXMP() throws {
        let fixture = try makeSessionFixture(dryRun: false)
        let originalSourceData = try Data(contentsOf: fixture.sourceURL)
        let output = try temporaryDirectory()
        let monitor = InterruptionMonitor()
        let result = try ApplySessionPipeline(
            afterSourceResolution: { monitor.requestInterruption() }
        ).run(
            sessionPath: fixture.sessionPath,
            configuration: applyConfiguration(outputDir: output),
            timestamp: Date(timeIntervalSince1970: 1_800_001_100),
            interruptionMonitor: monitor
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.xmp").path))
        XCTAssertTrue(result.interrupted)
        XCTAssertEqual(result.exportReport?.inputFailures.map(\.error.code), [.interrupted])
        XCTAssertEqual(result.report.errors.map(\.code), [.interrupted])
        XCTAssertEqual(try Data(contentsOf: fixture.sourceURL), originalSourceData)
        XCTAssertTrue(try decodeProgress(at: result.report.artifacts.progressPath).contains {
            $0.stage == .xmpTarget
                && $0.status == .failed
                && $0.errors.map(\.code) == [.interrupted]
        })
    }

    func testApplySessionFailsClosedForMalformedCurrentXMP() throws {
        let fixture = try makeSessionFixture(dryRun: false)
        let output = try temporaryDirectory()
        let target = output.appendingPathComponent("Bird.xmp")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let malformed = "<x:xmpmeta><rdf:RDF>"
        try malformed.write(to: target, atomically: true, encoding: .utf8)

        let result = try applyPipeline().run(
            sessionPath: fixture.sessionPath,
            configuration: applyConfiguration(outputDir: output),
            timestamp: Date(timeIntervalSince1970: 1_800_000_900)
        )

        XCTAssertEqual(result.exportReport?.targetReports.first?.status, .failed)
        XCTAssertEqual(result.exportReport?.targetReports.first?.errors.first?.code, .xmpParseFailed)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), malformed)
    }

    func testApplySessionRestoresBackupAfterValidationFailure() throws {
        let fixture = try makeSessionFixture(dryRun: false)
        let output = try temporaryDirectory()
        let target = output.appendingPathComponent("Bird.xmp")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try existingDevelopSettingsXMPForApplySession.write(to: target, atomically: true, encoding: .utf8)

        let pipeline = ApplySessionPipeline(
            xmpPipeline: XMPExportPipeline(
                engine: ValidationFailingOwnedEngine(),
                logger: Logger(sink: { _ in })
            )
        )
        let result = try pipeline.run(
            sessionPath: fixture.sessionPath,
            configuration: applyConfiguration(outputDir: output),
            timestamp: Date(timeIntervalSince1970: 1_800_001_000)
        )

        let targetReport = try XCTUnwrap(result.exportReport?.targetReports.first)
        XCTAssertEqual(targetReport.status, .failed)
        XCTAssertEqual(targetReport.errors.first?.code, .validationFailed)
        XCTAssertNotNil(targetReport.backup?.restoredAt)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), existingDevelopSettingsXMPForApplySession)
    }

    func testApplySessionRejectsUnsupportedSessionSchema() throws {
        let root = try temporaryDirectory()
        let sessionPath = root.appendingPathComponent("normalization-session.json")
        try #"{"schema_version":"ai-sidecar-normalization/2.0"}"#.write(
            to: sessionPath,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try applyPipeline().run(
                sessionPath: sessionPath.path,
                configuration: applyConfiguration(outputDir: try temporaryDirectory())
            )
        ) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .schemaUnsupported)
        }
    }

    private func makeSessionFixture(
        dryRun: Bool,
        normalizationOutput: URL? = nil
    ) throws -> ApplySessionFixture {
        let root = try temporaryDirectory()
        let jsonRoot = root.appendingPathComponent("json")
        let sourceRoot = root.appendingPathComponent("source")
        let output = normalizationOutput ?? root.appendingPathComponent("normalization")
        let vocabularyPath = try writeVocabulary(in: root)
        let source = try writeTestImage("Bird.JPG", in: sourceRoot)
        let sourceImage = try scannedSourceImage(source, relativePath: "Bird.JPG")
        try writeRawSidecar(
            source: sourceImage,
            named: "Bird.JPG.ai.json",
            in: jsonRoot,
            modelRuns: [
                modelRun(term: "bird")
            ]
        )

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .controlledVocabulary
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = output.path
        configuration.vocabularyPath = vocabularyPath
        configuration.normalizationMode = .singleImage
        configuration.dryRun = dryRun

        let result = dryRun
            ? try NormalizePipeline().runDryRun(
                mode: .fromJSON(path: jsonRoot.path),
                configuration: configuration,
                timestamp: Date(timeIntervalSince1970: 1_800_000_400),
                sessionID: "apply-session-fixture"
            )
            : try NormalizePipeline().runSessionOnly(
                mode: .fromJSON(path: jsonRoot.path),
                configuration: configuration,
                timestamp: Date(timeIntervalSince1970: 1_800_000_400),
                sessionID: "apply-session-fixture"
            )

        return ApplySessionFixture(
            root: root,
            sourceRoot: sourceRoot,
            sourceURL: source,
            sessionPath: try XCTUnwrap(result.session.artifacts.sessionPath)
        )
    }

    private func applyConfiguration(outputDir: URL) -> ResolvedApplySessionConfiguration {
        var configuration = ResolvedApplySessionConfiguration.builtInDefaults
        configuration.outputDir = outputDir.path
        return configuration
    }

    private func applyPipeline() -> ApplySessionPipeline {
        ApplySessionPipeline(
            xmpPipeline: XMPExportPipeline(logger: Logger(sink: { _ in }))
        )
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
        modelRuns: [ModelRunRecord]
    ) throws {
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
        try RawJSONSidecarDocument(sidecar: sidecar).encodedData().write(to: destination)
    }

    private func writeVocabulary(in root: URL) throws -> String {
        let file = root.appendingPathComponent("vocabulary.json")
        try vocabularyData(entries: minimalVocabularyEntries()).write(to: file)
        return file.path
    }

    private func modelRun(term: String) -> ModelRunRecord {
        ModelRunRecord(
            inputRole: .wholeImage,
            model: "test:model",
            modelDigest: "sha256:test",
            runtime: "test",
            runtimeVersion: "1.0",
            promptVersion: "prompt/1",
            promptSHA256: String(repeating: "a", count: 64),
            responseSchemaVersion: "schema/1",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "b", count: 64),
            rawResponseText: "{}",
            parsedResponseJSON: .object([
                "proposed_keywords": .array([
                    .object([
                        "term": .string(term),
                        "confidence": .string("high"),
                        "evidence": .string("visible bird")
                    ])
                ])
            ]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func decodeProgress(at path: String) throws -> [NormalizationProgressRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        return try text
            .split(separator: "\n")
            .map { try decoder.decode(NormalizationProgressRecord.self, from: Data($0.utf8)) }
    }
}

private struct ApplySessionFixture {
    var root: URL
    var sourceRoot: URL
    var sourceURL: URL
    var sessionPath: String
}

private struct ValidationFailingOwnedEngine: MetadataWriteEngine {
    private let owned = OwnedXMPSidecarEngine()

    func prepare(configuration: ResolvedXMPExportConfiguration) throws -> MetadataWriteEngineContext {
        try owned.prepare(configuration: configuration)
    }

    func readSnapshot(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        try owned.readSnapshot(at: targetXMPPath)
    }

    func preview(_ request: XMPWriteRequest) throws -> XMPWritePreview {
        try owned.preview(request)
    }

    func apply(_ request: XMPWriteRequest) throws -> XMPWriteResult {
        try owned.apply(request)
    }

    func validateReadable(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        XMPMetadataSnapshot.empty(targetPath: targetXMPPath, exists: true)
    }

    func shutdown() throws {
        try owned.shutdown()
    }
}

private let existingDevelopSettingsXMPForApplySession = """
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
