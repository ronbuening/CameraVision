import Foundation
import XCTest
@testable import AISidecarCore

final class XMPExportPipelineTests: XCTestCase {
    func testFromJSONFolderWritesXMPReportProgressAndSummary() throws {
        let fixture = try makeFromJSONFixture()
        var configuration = exportConfiguration(outputDir: fixture.output.path)
        configuration.recursive = false

        let result = try XMPExportPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        ).runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        let target = fixture.output.appendingPathComponent("Bird.xmp")
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: target.path)
        XCTAssertEqual(snapshot.flatKeywords, ["wading bird"])
        XCTAssertEqual(snapshot.hierarchicalKeywords, ["wading bird"])
        XCTAssertEqual(result.report?.schemaVersion, XMPExportSchemaIdentifiers.exportReport)
        XCTAssertEqual(result.report?.targetReports.first?.status, .created)
        XCTAssertEqual(result.report?.targetReports.first?.sourceHashChecks.first?.unchanged, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(result.progressLogPath)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(result.reportPath)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(result.summaryPath)))
        let summary = try String(contentsOf: URL(fileURLWithPath: try XCTUnwrap(result.summaryPath)), encoding: .utf8)
        XCTAssertTrue(summary.contains("Lightroom Classic"))
        XCTAssertTrue(summary.contains("Capture One"))
    }

    func testDryRunAddsPreviewWithoutWritingXMP() throws {
        let fixture = try makeFromJSONFixture(existingXMP: existingDevelopSettingsXMP)
        var configuration = exportConfiguration(outputDir: fixture.output.path)
        configuration.dryRun = true

        let result = try XMPExportPipeline(
            logger: Logger(sink: { _ in })
        ).runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)
        XCTAssertEqual(plan.preview?.existingFlatKeywords, ["existing bird"])
        XCTAssertEqual(plan.preview?.flatKeywordsToAdd, ["wading bird"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("Bird.xmp").path))
        XCTAssertNil(result.report)
    }

    func testConflictPolicyFailLeavesExistingXMPUnchanged() throws {
        let fixture = try makeFromJSONFixture(existingXMP: existingDevelopSettingsXMP)
        var configuration = exportConfiguration(outputDir: fixture.output.path)
        configuration.xmpConflictPolicy = .fail
        configuration.backupSidecars = false

        let result = try XMPExportPipeline(
            logger: Logger(sink: { _ in })
        ).runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        XCTAssertEqual(result.report?.targetReports.first?.status, .failed)
        XCTAssertEqual(result.report?.targetReports.first?.errors.map(\.code), [.sidecarExists])
        XCTAssertEqual(
            try String(contentsOf: fixture.output.appendingPathComponent("Bird.xmp"), encoding: .utf8),
            existingDevelopSettingsXMP
        )
    }

    func testBackupAndMergeCreatesBackupAndPreservesExistingMetadata() throws {
        let fixture = try makeFromJSONFixture(existingXMP: existingDevelopSettingsXMP)
        let configuration = exportConfiguration(outputDir: fixture.output.path)

        let result = try XMPExportPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        ).runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        let report = try XCTUnwrap(result.report?.targetReports.first)
        let backup = try XCTUnwrap(report.backup)
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: fixture.output.appendingPathComponent("Bird.xmp").path)
        XCTAssertEqual(report.status, .written)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.backupPath))
        XCTAssertEqual(snapshot.flatKeywords, ["existing bird", "wading bird"])
        XCTAssertEqual(snapshot.hierarchicalKeywords, ["existing habitat", "wading bird"])
        XCTAssertTrue(report.validation?.unmanagedContentPreserved == true)
    }

    func testValidationFailureRestoresBackupAndContinuesBatch() throws {
        let fixture = try makeFromJSONFixture(existingXMP: existingDevelopSettingsXMP)
        let configuration = exportConfiguration(outputDir: fixture.output.path)

        let result = try XMPExportPipeline(
            engine: ValidationFailingEngine(),
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        ).runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        let report = try XCTUnwrap(result.report?.targetReports.first)
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.errors.first?.code, .validationFailed)
        XCTAssertNotNil(report.backup?.restoredAt)
        XCTAssertEqual(
            try String(contentsOf: fixture.output.appendingPathComponent("Bird.xmp"), encoding: .utf8),
            existingDevelopSettingsXMP
        )
    }

    func testInterruptionAfterBackupRestoresOriginalSidecar() throws {
        let fixture = try makeFromJSONFixture(existingXMP: existingDevelopSettingsXMP)
        let monitor = InterruptionMonitor()
        let configuration = exportConfiguration(outputDir: fixture.output.path)

        let result = try XMPExportPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000)),
            afterBackup: { monitor.requestInterruption() }
        ).runFromJSON(
            fromJSONPath: fixture.jsonRoot.path,
            configuration: configuration,
            interruptionMonitor: monitor
        )

        let report = try XCTUnwrap(result.report?.targetReports.first)
        XCTAssertTrue(result.interrupted)
        XCTAssertEqual(report.status, .interrupted)
        XCTAssertNotNil(report.backup?.restoredAt)
        XCTAssertEqual(
            try String(contentsOf: fixture.output.appendingPathComponent("Bird.xmp"), encoding: .utf8),
            existingDevelopSettingsXMP
        )
    }

    private func makeFromJSONFixture(existingXMP: String? = nil) throws -> FromJSONFixture {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let jsonRoot = root.appendingPathComponent("json")
        let output = root.appendingPathComponent("xmp")
        let source = try writeSource("Bird.JPG", data: Data("source".utf8), in: root.appendingPathComponent("source"))
        let sourceImage = try makeSourceImage(for: source)
        try writeSidecar(
            RawJSONSidecar(
                source: sourceImage,
                runConfiguration: .builtInDefaults,
                modelRuns: [modelRun(term: "wading bird")]
            ),
            named: "Bird.JPG.ai.json",
            in: jsonRoot
        )
        if let existingXMP {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try existingXMP.write(to: output.appendingPathComponent("Bird.xmp"), atomically: true, encoding: .utf8)
        }
        return FromJSONFixture(root: root, jsonRoot: jsonRoot, output: output, source: source)
    }

    private func exportConfiguration(outputDir: String) -> ResolvedXMPExportConfiguration {
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.outputDir = outputDir
        configuration.sourceVerification = .fail
        return configuration
    }

    private func writeSource(_ relativePath: String, data: Data, in root: URL) throws -> URL {
        let file = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        return file.standardizedFileURL
    }

    private func writeSidecar(_ sidecar: RawJSONSidecar, named relativePath: String, in root: URL) throws {
        let file = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(sidecar).write(to: file)
    }

    private func makeSourceImage(for url: URL) throws -> SourceImage {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return SourceImage(
            path: url.path,
            relativePath: url.lastPathComponent,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modifiedAt: (attributes[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0),
            detectedType: .jpg,
            identity: try SourceIdentityCalculator.compute(for: url, policy: .sha256)
        )
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
                        "evidence": .string("fixture")
                    ])
                ])
            ]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func fixedDateProvider(_ date: Date) -> @Sendable () -> Date {
        { date }
    }
}

private struct FromJSONFixture {
    var root: URL
    var jsonRoot: URL
    var output: URL
    var source: URL
}

private struct ValidationFailingEngine: MetadataWriteEngine {
    private let engine = OwnedXMPSidecarEngine()

    func prepare(configuration: ResolvedXMPExportConfiguration) throws -> MetadataWriteEngineContext {
        try engine.prepare(configuration: configuration)
    }

    func readSnapshot(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        try engine.readSnapshot(at: targetXMPPath)
    }

    func preview(_ request: XMPWriteRequest) throws -> XMPWritePreview {
        try engine.preview(request)
    }

    func apply(_ request: XMPWriteRequest) throws -> XMPWriteResult {
        try engine.apply(request)
    }

    func validateReadable(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        var snapshot = try engine.validateReadable(at: targetXMPPath)
        snapshot.flatKeywords = snapshot.flatKeywords.filter { $0 != "wading bird" }
        snapshot.hierarchicalKeywords = snapshot.hierarchicalKeywords.filter { $0 != "wading bird" }
        return snapshot
    }

    func shutdown() throws {
        try engine.shutdown()
    }
}

private let existingDevelopSettingsXMP = """
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
