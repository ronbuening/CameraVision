import CryptoKit
import Foundation
import XCTest

@testable import AISidecarCore

final class ApplySessionPipelineTests: XCTestCase {
    func testDefaultOffApplyMatchesPreQN6ArtifactHashes() async throws {
        let fixture = try await makeSessionFixture(dryRun: false)
        let output = fixture.root.appendingPathComponent("apply-output")
        let exportTimestamp = Date(timeIntervalSince1970: 1_800_000_450)
        let result = try ApplySessionPipeline(
            xmpPipeline: XMPExportPipeline(
                logger: Logger(sink: { _ in }),
                now: { exportTimestamp },
                filenameSuffix: { "qn6-baseline" }
            )
        ).run(
            sessionPath: fixture.sessionPath,
            configuration: applyConfiguration(outputDir: output),
            timestamp: Date(timeIntervalSince1970: 1_800_000_500)
        )

        let sessionName = URL(fileURLWithPath: fixture.sessionPath).deletingPathExtension().lastPathComponent
        let sessionTokenPrefix = Timestamp.filenameSafe(Date(timeIntervalSince1970: 1_800_000_400)) + "-"
        let sessionTokenRange = try XCTUnwrap(sessionName.range(of: sessionTokenPrefix))
        let sessionToken = String(sessionName[sessionTokenRange.lowerBound...])
        let reportName = URL(fileURLWithPath: result.report.artifacts.reportPath)
            .deletingPathExtension()
            .lastPathComponent
        let applyTokenPrefix = "normalization-apply-report-"
        let applyTokenRange = try XCTUnwrap(reportName.range(of: applyTokenPrefix))
        let applyToken = String(reportName[applyTokenRange.upperBound...])
        let artifacts = [
            "progress": result.report.artifacts.progressPath,
            "raw_sidecar": fixture.taggingSidecar.path,
            "report": result.report.artifacts.reportPath,
            "session": fixture.sessionPath,
            "summary": result.report.artifacts.summaryPath,
            "xmp": output.appendingPathComponent("Bird.xmp").path,
        ]
        var actual: [String: String] = [:]
        for (key, path) in artifacts {
            actual[key] = try sha256(
                normalizedData(
                    at: path,
                    root: fixture.root,
                    sessionToken: sessionToken,
                    applyToken: applyToken
                ))
        }

        XCTAssertEqual(actual, try applyBaselineHashes())
    }

    func testDefaultOffApplyDoesNotReadCurrentQualityInputsOrPlanningSnapshot() async throws {
        let fixture = try await makeSessionFixture(dryRun: false)
        let reads = ApplySessionPlanningReadCounter()
        let pipeline = ApplySessionPipeline(
            snapshotReader: { path in
                reads.recordSnapshotRead()
                return .empty(targetPath: path, exists: false)
            },
            currentSidecarPairResolver: { _ in
                reads.recordSidecarRead()
                return RawJSONSidecarInputBatch(inputs: [], failures: [])
            },
            xmpPipeline: XMPExportPipeline(logger: Logger(sink: { _ in }))
        )

        _ = try pipeline.run(
            sessionPath: fixture.sessionPath,
            configuration: applyConfiguration(outputDir: fixture.root.appendingPathComponent("default-off")),
            timestamp: Date(timeIntervalSince1970: 1_800_000_501)
        )

        XCTAssertEqual(reads.sidecarReadCount, 0)
        XCTAssertEqual(reads.snapshotReadCount, 0)
    }

    func testApplySessionWritesStoredDecisionsAndMergesCurrentXMP() async throws {
        let fixture = try await makeSessionFixture(dryRun: false)
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

    func testApplySessionRejectsStaleSourcesUnlessExplicitlyAllowed() async throws {
        let fixture = try await makeSessionFixture(dryRun: false)
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

    func testApplySessionDryRunResolvesMovedSourceRootAndRecomputesTargetPath() async throws {
        let oldPlanOutput = try temporaryDirectory()
        let fixture = try await makeSessionFixture(dryRun: true, normalizationOutput: oldPlanOutput)
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

    func testApplySessionResolvesSymlinkedSourceImage() async throws {
        let fixture = try await makeSessionFixture(dryRun: true)
        let realRoot = try temporaryDirectory()
        let realSource = realRoot.appendingPathComponent("Bird.JPG")
        try FileManager.default.moveItem(at: fixture.sourceURL, to: realSource)
        try FileManager.default.createSymbolicLink(at: fixture.sourceURL, withDestinationURL: realSource)

        let applyOutput = try temporaryDirectory()
        var configuration = applyConfiguration(outputDir: applyOutput)
        configuration.dryRun = true

        let result = try applyPipeline().run(
            sessionPath: fixture.sessionPath,
            configuration: configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_850)
        )

        let plan = try XCTUnwrap(result.changePlan.targetPlans.first)
        XCTAssertEqual(plan.sourceMembers.first?.sourcePath, fixture.sourceURL.path)
        XCTAssertFalse(result.report.errors.contains { $0.code == .sourceMissing })
        XCTAssertEqual(result.exportReport?.inputFailures.map(\.error.code), [])
        XCTAssertEqual(result.exportReport?.targetReports.first?.status, .dryRun)
    }

    func testApplySessionInterruptedAfterSourceResolutionDoesNotWriteXMP() async throws {
        let fixture = try await makeSessionFixture(dryRun: false)
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
        XCTAssertTrue(
            try decodeProgress(at: result.report.artifacts.progressPath).contains {
                $0.stage == .xmpTarget
                    && $0.status == .failed
                    && $0.errors.map(\.code) == [.interrupted]
            })
    }

    func testApplySessionFailsClosedForMalformedCurrentXMP() async throws {
        let fixture = try await makeSessionFixture(dryRun: false)
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

    func testApplySessionRestoresBackupAfterValidationFailure() async throws {
        let fixture = try await makeSessionFixture(dryRun: false)
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

    func testApplySessionRejectsDuplicateGroupTargetWithoutTrapping() async throws {
        let fixture = try await makeSessionFixture(dryRun: false)
        var session = try NormalizationSessionReader().read(from: fixture.sessionPath)
        let duplicate = try XCTUnwrap(session.sameBaseNameGroups.first)
        session.sameBaseNameGroups.append(duplicate)
        try NormalizationSessionWriter().write(session, to: fixture.sessionPath)

        XCTAssertThrowsError(
            try applyPipeline().run(
                sessionPath: fixture.sessionPath,
                configuration: applyConfiguration(outputDir: try temporaryDirectory())
            )
        ) { error in
            let sidecarError = error as? SidecarError
            XCTAssertEqual(sidecarError?.code, .sessionStale)
            XCTAssertEqual(sidecarError?.stage, .normalize)
            XCTAssertTrue(sidecarError?.message.contains(duplicate.targetRelativePath) == true)
        }
    }

    func testApplySessionRejectsDuplicateStoredWritePlanTargetWithoutTrapping() async throws {
        let fixture = try await makeSessionFixture(dryRun: true)
        var session = try NormalizationSessionReader().read(from: fixture.sessionPath)
        let duplicate = try XCTUnwrap(session.xmpWritePlans.first)
        session.xmpWritePlans.append(duplicate)
        try NormalizationSessionWriter().write(session, to: fixture.sessionPath)

        XCTAssertThrowsError(
            try applyPipeline().run(
                sessionPath: fixture.sessionPath,
                configuration: applyConfiguration(outputDir: try temporaryDirectory())
            )
        ) { error in
            let sidecarError = error as? SidecarError
            XCTAssertEqual(sidecarError?.code, .sessionStale)
            XCTAssertEqual(sidecarError?.stage, .normalize)
            XCTAssertTrue(
                sidecarError?.message.contains(duplicate.xmpChangePlan.targetRelativePath) == true
            )
        }
    }

    func testApplySessionRejectsDuplicateSourceAssetIDWithoutTrapping() async throws {
        let fixture = try await makeSessionFixture(dryRun: false)
        var session = try NormalizationSessionReader().read(from: fixture.sessionPath)
        let duplicate = try XCTUnwrap(session.sourceAssets.first)
        session.sourceAssets.append(duplicate)
        try NormalizationSessionWriter().write(session, to: fixture.sessionPath)

        XCTAssertThrowsError(
            try applyPipeline().run(
                sessionPath: fixture.sessionPath,
                configuration: applyConfiguration(outputDir: try temporaryDirectory())
            )
        ) { error in
            let sidecarError = error as? SidecarError
            XCTAssertEqual(sidecarError?.code, .sessionStale)
            XCTAssertEqual(sidecarError?.stage, .normalize)
            XCTAssertTrue(sidecarError?.message.contains(duplicate.assetID) == true)
        }
    }

    func testApplySessionRejectsDuplicateSourceSidecarAssetIDWithoutTrapping() async throws {
        let fixture = try await makeSessionFixture(dryRun: false)
        var session = try NormalizationSessionReader().read(from: fixture.sessionPath)
        let duplicate = try XCTUnwrap(session.sourceAISidecars.first)
        session.sourceAISidecars.append(duplicate)
        try NormalizationSessionWriter().write(session, to: fixture.sessionPath)

        XCTAssertThrowsError(
            try applyPipeline().run(
                sessionPath: fixture.sessionPath,
                configuration: applyConfiguration(outputDir: try temporaryDirectory())
            )
        ) { error in
            let sidecarError = error as? SidecarError
            XCTAssertEqual(sidecarError?.code, .sessionStale)
            XCTAssertEqual(sidecarError?.stage, .normalize)
            XCTAssertTrue(sidecarError?.message.contains(duplicate.sourceAssetID) == true)
        }
    }

    private func makeSessionFixture(
        dryRun: Bool,
        normalizationOutput: URL? = nil
    ) async throws -> ApplySessionFixture {
        let root = try temporaryDirectory()
        let jsonRoot = root.appendingPathComponent("json")
        let sourceRoot = root.appendingPathComponent("source")
        let output = normalizationOutput ?? root.appendingPathComponent("normalization")
        let vocabularyPath = try writeVocabulary(in: root)
        let source = try writeTestImage("Bird.JPG", in: sourceRoot)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_100)],
            ofItemAtPath: source.path
        )
        let sourceImage = try scannedSourceImage(source, relativePath: "Bird.JPG")
        let taggingSidecar = try writeRawSidecar(
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

        let result: NormalizePipelineResult
        if dryRun {
            result = try await NormalizePipeline().runDryRun(
                mode: .fromJSON(path: jsonRoot.path),
                configuration: configuration,
                timestamp: Date(timeIntervalSince1970: 1_800_000_400),
                sessionID: "apply-session-fixture"
            )
        } else {
            result = try await NormalizePipeline().runSessionOnly(
                mode: .fromJSON(path: jsonRoot.path),
                configuration: configuration,
                timestamp: Date(timeIntervalSince1970: 1_800_000_400),
                sessionID: "apply-session-fixture"
            )
        }

        return ApplySessionFixture(
            root: root,
            sourceRoot: sourceRoot,
            sourceURL: source,
            taggingSidecar: taggingSidecar,
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
    ) throws -> URL {
        let destination = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Pinned fields keep the hashed fixture bytes machine-independent;
        // see NormalizeQualityDefaultOffIdentityTests.fixtureRunConfiguration.
        let sidecar = RawJSONSidecar(
            source: source,
            runConfiguration: NormalizeQualityDefaultOffIdentityTests.fixtureRunConfiguration(),
            modelRuns: modelRuns,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try RawJSONSidecarDocument(sidecar: sidecar).encodedData().write(to: destination)
        return destination
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
                        "evidence": .string("visible bird"),
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
        return
            try text
            .split(separator: "\n")
            .map { try decoder.decode(NormalizationProgressRecord.self, from: Data($0.utf8)) }
    }

    private func normalizedData(
        at path: String,
        root: URL,
        sessionToken: String,
        applyToken: String
    ) throws -> Data {
        var text = String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
        // Generated from QN5 commit fdf6cae before QN6 changed apply-session.
        // Normalize only temporary paths and the planners' random filename tokens.
        // raw_sidecar re-pinned 2026-07-19 after fixing the fixture's
        // machine-specific run configuration (cache dir, concurrency); the
        // pipeline-produced artifact hashes were unchanged by that fix.
        text = text.replacingOccurrences(of: root.standardizedFileURL.path, with: "$ROOT")
        text = text.replacingOccurrences(of: sessionToken, with: "$SESSION_TOKEN")
        text = text.replacingOccurrences(of: applyToken, with: "$APPLY_TOKEN")
        return Data(text.utf8)
    }

    private func applyBaselineHashes() throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "qn6-default-off-apply-artifact-sha256",
                withExtension: "json",
                subdirectory: "normalization"
            )
                ?? Bundle.module.url(
                    forResource: "qn6-default-off-apply-artifact-sha256",
                    withExtension: "json"
                )
        )
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct ApplySessionFixture {
    var root: URL
    var sourceRoot: URL
    var sourceURL: URL
    var taggingSidecar: URL
    var sessionPath: String
}

private final class ApplySessionPlanningReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var sidecarReads = 0
    private var snapshotReads = 0

    var sidecarReadCount: Int {
        lock.withLock { sidecarReads }
    }

    var snapshotReadCount: Int {
        lock.withLock { snapshotReads }
    }

    func recordSidecarRead() {
        lock.withLock { sidecarReads += 1 }
    }

    func recordSnapshotRead() {
        lock.withLock { snapshotReads += 1 }
    }
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
