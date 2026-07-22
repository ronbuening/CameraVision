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
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000)),
            filenameSuffix: { "a3f2" }
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
        XCTAssertEqual(
            result.progressLogPath,
            fixture.output.appendingPathComponent("xmp-export-progress-2027-01-15T080000Z-a3f2.jsonl").path
        )
        XCTAssertEqual(
            result.reportPath,
            fixture.output.appendingPathComponent("xmp-export-report-2027-01-15T080000Z-a3f2.json").path
        )
        XCTAssertEqual(
            result.summaryPath,
            fixture.output.appendingPathComponent("xmp-export-summary-2027-01-15T080000Z-a3f2.md").path
        )
        let summary = try String(contentsOf: URL(fileURLWithPath: try XCTUnwrap(result.summaryPath)), encoding: .utf8)
        XCTAssertTrue(summary.contains("Lightroom Classic"))
        XCTAssertTrue(summary.contains("Capture One"))
    }

    func testFolderArtifactsResolveInsideSymlinkedInputFolder() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("xmp-artifacts-\(UUID().uuidString)", isDirectory: true)
        let realFolder = root.appendingPathComponent("real", isDirectory: true)
        let link = root.appendingPathComponent("link")
        try fileManager.createDirectory(at: realFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: realFolder)

        let artifacts = ExportArtifactPaths.resolve(
            inputPath: link.path,
            outputDir: nil,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            runSuffix: "symlink",
            fileManager: fileManager
        )

        XCTAssertEqual(artifacts.directory, link.path)
    }

    func testStampSkipsMembersWithoutRawSidecarAndNeverWritesToImagePaths() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("Bird.JPG")
        let target = root.appendingPathComponent("Bird.xmp")
        let sourceData = Data("source image bytes".utf8)
        try sourceData.write(to: source)
        let logs = XMPLogSink()
        let member = SourceMemberPlan(
            sourcePath: source.path,
            sourceRelativePath: "Bird.JPG",
            sourceFileName: "Bird.JPG",
            sourceType: .jpg,
            sourceSidecarPath: nil,
            sourceSidecarRelativePath: nil,
            sourceIdentityStatus: .matched,
            pairKind: .jpeg,
            selected: true,
            skipReason: nil,
            flatKeywordContributionCount: 1,
            hierarchicalKeywordContributionCount: 0
        )
        let plan = XMPChangePlan(
            status: .planned,
            targetXMPPath: target.path,
            targetRelativePath: "Bird.xmp",
            pairScope: .union,
            sourceMembers: [member],
            flatKeywordsToAdd: [PlannedKeyword(term: "bird", normalizedKey: "bird", candidates: [])],
            hierarchicalKeywordsToAdd: [],
            skippedCandidates: [],
            candidateExtractionIssues: [],
            sourceVerificationWarnings: [],
            groupWarnings: [],
            existingPolicy: .backupAndMerge,
            backupPlan: BackupPlan(
                backupSidecars: true,
                backupRequiredBeforeMerge: true,
                conflictPolicy: .backupAndMerge
            ),
            validationPlan: .phase2Default,
            failures: []
        )
        let document = XMPChangePlanDocument(dryRun: false, targetPlans: [plan], inputFailures: [])

        let result = try XMPExportPipeline(
            logger: Logger(sink: logs.append)
        ).runChangePlan(
            document,
            inputPath: root.path,
            configuration: exportConfiguration(outputDir: root.path)
        )

        XCTAssertEqual(result.report?.targetReports.first?.status, .created)
        XCTAssertEqual(try Data(contentsOf: source), sourceData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(logs.lines.contains { $0.contains("write_xmp.stamp_skipped") })
    }

    func testUnchangedRerunBackfillsMissingSidecarStampWithoutChurningStampedOnes() throws {
        let fixture = try makeFromJSONFixture()
        let configuration = exportConfiguration(outputDir: fixture.output.path)
        _ = try XMPExportPipeline(logger: Logger(sink: { _ in }), filenameSuffix: { "a3f2" })
            .runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)
        let sidecar = fixture.jsonRoot.appendingPathComponent("Bird.JPG.ai.json")
        XCTAssertTrue(RawSidecarExportStamp.isStamped(sidecarPath: sidecar.path))

        // Simulate a run whose XMP write succeeded but whose stamp failed.
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any]
        )
        object.removeValue(forKey: RawSidecarExportStamp.key)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: sidecar)
        XCTAssertFalse(RawSidecarExportStamp.isStamped(sidecarPath: sidecar.path))

        let rerun = try XMPExportPipeline(logger: Logger(sink: { _ in }), filenameSuffix: { "b4c1" })
            .runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        XCTAssertEqual(rerun.report?.targetReports.first?.status, .unchanged)
        XCTAssertTrue(RawSidecarExportStamp.isStamped(sidecarPath: sidecar.path))

        let bytesBefore = try Data(contentsOf: sidecar)
        _ = try XMPExportPipeline(logger: Logger(sink: { _ in }), filenameSuffix: { "c5d2" })
            .runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)
        XCTAssertEqual(try Data(contentsOf: sidecar), bytesBefore)
    }

    func testStampRewritePreservesFloatAndSlashFormatting() throws {
        let fixture = try makeFromJSONFixture()
        let sidecar = fixture.jsonRoot.appendingPathComponent("Bird.JPG.ai.json")
        var sidecarJSON = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: sidecar))
        var fixtureObject = try XCTUnwrap(sidecarJSON.objectValue)
        fixtureObject["future_path"] = .string("/future/path")
        sidecarJSON = .object(fixtureObject)
        try JSONCoding.documentEncoder(iso8601Dates: false).encode(sidecarJSON).write(to: sidecar)

        try RawSidecarExportStamp.stamp(
            sidecarPath: sidecar.path,
            contents: RawSidecarExportStamp.Contents(
                targetXMPPath: "/exports/Bird.xmp",
                xmpSHA256: String(repeating: "a", count: 64),
                writerRecipeVersion: OwnedXMPSidecarEngine.writerRecipeVersion,
                engineVersion: OwnedXMPSidecarEngine.engineVersion,
                exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        let rewritten = try String(contentsOf: sidecar, encoding: .utf8)
        XCTAssertTrue(rewritten.contains(#""subject_crop_margin_fraction" : 0.08"#))
        XCTAssertFalse(rewritten.contains("0.080000000000000002"))
        XCTAssertTrue(rewritten.contains(#""future_path" : "/future/path""#))
        XCTAssertTrue(rewritten.contains(#""target_xmp_path" : "/exports/Bird.xmp""#))
        XCTAssertFalse(rewritten.contains(#"\/future\/path"#))
    }

    func testUnreadableSourceAtExportStartRecordsFailedHashCheckAndFailsTarget() throws {
        try XCTSkipIf(getuid() == 0, "chmod 000 is not enforced for root")
        let fixture = try makeFromJSONFixture()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: fixture.source.path
            )
        }
        let configuration = exportConfiguration(outputDir: fixture.output.path)

        let result = try XMPExportPipeline(
            engine: SourceLockingEngine(sourcePath: fixture.source.path),
            logger: Logger(sink: { _ in }),
            filenameSuffix: { "a3f2" }
        ).runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        let report = try XCTUnwrap(result.report?.targetReports.first)
        let check = try XCTUnwrap(report.sourceHashChecks.first)
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.errors.map(\.code), [.validationFailed])
        XCTAssertEqual(check.sourcePath, fixture.source.path)
        XCTAssertNil(check.beforeSHA256)
        XCTAssertNil(check.afterSHA256)
        XCTAssertFalse(check.unchanged)
        XCTAssertEqual(check.error?.code, .validationFailed)
        XCTAssertTrue(check.error?.message.contains("Unable to read source image before XMP export") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("Bird.xmp").path))
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
        let suffixes = CountingSuffixProvider(values: ["a3f2", "beef"])

        let result = try XMPExportPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000)),
            filenameSuffix: suffixes.next
        ).runFromJSON(fromJSONPath: fixture.jsonRoot.path, configuration: configuration)

        let report = try XCTUnwrap(result.report?.targetReports.first)
        let backup = try XCTUnwrap(report.backup)
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(
            at: fixture.output.appendingPathComponent("Bird.xmp").path)
        XCTAssertEqual(report.status, .written)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.backupPath))
        XCTAssertEqual(
            backup.backupPath,
            fixture.output.appendingPathComponent("Bird.xmp.bak-2027-01-15T080000Z-a3f2").path
        )
        XCTAssertEqual(
            result.reportPath,
            fixture.output.appendingPathComponent("xmp-export-report-2027-01-15T080000Z-a3f2.json").path
        )
        XCTAssertEqual(suffixes.callCount, 1, "one suffix is generated and shared by all export artifacts")
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

    func testScalarValidationFailureRestoresBackupAndOriginalScalar() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Rated.xmp")
        try existingRatingXMP.write(to: target, atomically: true, encoding: .utf8)
        let plan = XMPChangePlan(
            status: .planned,
            targetXMPPath: target.path,
            targetRelativePath: "Rated.xmp",
            pairScope: .union,
            sourceMembers: [],
            flatKeywordsToAdd: [],
            hierarchicalKeywordsToAdd: [],
            skippedCandidates: [],
            candidateExtractionIssues: [],
            sourceVerificationWarnings: [],
            groupWarnings: [],
            existingPolicy: .backupAndMerge,
            backupPlan: BackupPlan(
                backupSidecars: true,
                backupRequiredBeforeMerge: true,
                conflictPolicy: .backupAndMerge
            ),
            validationPlan: .phase2Default,
            failures: [],
            ratingWrite: PlannedScalarWrite(
                field: "xmp:Rating",
                plannedValue: "4",
                existingValue: "3",
                action: .overwrite
            )
        )
        let document = XMPChangePlanDocument(dryRun: false, targetPlans: [plan], inputFailures: [])

        let result = try XMPExportPipeline(
            engine: ValidationFailingEngine(),
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000)),
            filenameSuffix: { "a3f2" }
        ).runChangePlan(
            document,
            inputPath: root.path,
            configuration: exportConfiguration(outputDir: root.path)
        )

        let report = try XCTUnwrap(result.report?.targetReports.first)
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.errors.first?.code, .validationFailed)
        XCTAssertTrue(report.errors.first?.message.contains("xmp:Rating") == true)
        XCTAssertNotNil(report.backup?.restoredAt)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), existingRatingXMP)
        XCTAssertEqual(try OwnedXMPSidecarEngine().readSnapshot(at: target.path).rating, "3")
    }

    func testThrownScalarReadabilityValidationRemovesNewSidecar() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("NewRated.xmp")
        let plan = XMPChangePlan(
            status: .planned,
            targetXMPPath: target.path,
            targetRelativePath: "NewRated.xmp",
            pairScope: .union,
            sourceMembers: [],
            flatKeywordsToAdd: [],
            hierarchicalKeywordsToAdd: [],
            skippedCandidates: [],
            candidateExtractionIssues: [],
            sourceVerificationWarnings: [],
            groupWarnings: [],
            existingPolicy: .backupAndMerge,
            backupPlan: BackupPlan(
                backupSidecars: true,
                backupRequiredBeforeMerge: true,
                conflictPolicy: .backupAndMerge
            ),
            validationPlan: .phase2Default,
            failures: [],
            ratingWrite: PlannedScalarWrite(
                field: "xmp:Rating",
                plannedValue: "4",
                existingValue: nil,
                action: .write
            )
        )
        let document = XMPChangePlanDocument(dryRun: false, targetPlans: [plan], inputFailures: [])

        let result = try XMPExportPipeline(
            engine: ThrowingPostWriteValidationEngine(),
            logger: Logger(sink: { _ in }),
            filenameSuffix: { "a3f2" }
        ).runChangePlan(
            document,
            inputPath: root.path,
            configuration: exportConfiguration(outputDir: root.path)
        )

        let report = try XCTUnwrap(result.report?.targetReports.first)
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.errors.first?.code, .validationFailed)
        XCTAssertTrue(report.writeResult?.created == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
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
                        "evidence": .string("fixture"),
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

private final class CountingSuffixProvider: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [String]
    private var index = 0

    init(values: [String]) {
        self.values = values
    }

    var callCount: Int {
        lock.withLock { index }
    }

    func next() -> String {
        lock.withLock {
            defer { index += 1 }
            return values[min(index, values.count - 1)]
        }
    }
}

private struct SourceLockingEngine: MetadataWriteEngine {
    private let sourcePath: String
    private let engine = OwnedXMPSidecarEngine()

    init(sourcePath: String) {
        self.sourcePath = sourcePath
    }

    func prepare(configuration: ResolvedXMPExportConfiguration) throws -> MetadataWriteEngineContext {
        try engine.prepare(configuration: configuration)
    }

    func readSnapshot(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        try engine.readSnapshot(at: targetXMPPath)
    }

    func preview(_ request: XMPWriteRequest) throws -> XMPWritePreview {
        let preview = try engine.preview(request)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sourcePath)
        return preview
    }

    func apply(_ request: XMPWriteRequest) throws -> XMPWriteResult {
        try engine.apply(request)
    }

    func validateReadable(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        try engine.validateReadable(at: targetXMPPath)
    }

    func shutdown() throws {
        try engine.shutdown()
    }
}

private struct FromJSONFixture {
    var root: URL
    var jsonRoot: URL
    var output: URL
    var source: URL
}

private final class XMPLogSink: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }
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
        snapshot.rating = nil
        return snapshot
    }

    func shutdown() throws {
        try engine.shutdown()
    }
}

private struct ThrowingPostWriteValidationEngine: MetadataWriteEngine {
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

    func validateReadable(at _: String) throws -> XMPMetadataSnapshot {
        throw SidecarError(
            code: .validationFailed,
            stage: .write,
            message: "Injected post-write scalar readability failure.",
            recoverable: true
        )
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

private let existingRatingXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:xmp="http://ns.adobe.com/xap/1.0/">
      <rdf:Description rdf:about="" xmp:Rating="3"/>
    </rdf:RDF>
    """
