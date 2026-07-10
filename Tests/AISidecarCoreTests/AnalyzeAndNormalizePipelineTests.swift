import Foundation
import XCTest
@testable import AISidecarCore

final class AnalyzeAndNormalizePipelineTests: XCTestCase {
    func testAnalyzeAndNormalizeFolderRunWritesRawSessionReportAndXMP() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: vocabularyPath).deletingLastPathComponent())
        }
        _ = try writeTestImage("Bird.JPG", in: root)

        let result = try await pipeline().run(
            inputPath: root.path,
            runConfiguration: runConfiguration(outputDir: output.path, recursive: true),
            normalizationConfiguration: normalizationConfiguration(outputDir: output.path, vocabularyPath: vocabularyPath)
        )

        XCTAssertEqual(result.analyzeResult.records.map(\.status), [.written])
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.JPG.ai.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.normalizeResult.session.artifacts.reportPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.normalizeResult.session.artifacts.summaryPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.normalizeResult.session.artifacts.progressPath))

        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: output.appendingPathComponent("Bird.xmp").path)
        XCTAssertEqual(snapshot.flatKeywords, ["Birds"])
        XCTAssertEqual(snapshot.hierarchicalKeywords, ["Subject|Wildlife|Birds"])
        XCTAssertEqual(result.normalizeResult.report.workflow, .analyze)
        XCTAssertEqual(result.normalizeResult.report.inputSummary.sourceAssetCount, 1)
        XCTAssertEqual(result.normalizeResult.report.inputSummary.sourceAISidecarCount, 1)
        XCTAssertEqual(result.normalizeResult.report.inputSummary.xmpWritePlanCount, 1)
        XCTAssertEqual(result.normalizeResult.report.xmpExportReport?.targetReports.first?.status, .created)
        XCTAssertFalse(result.normalizeResult.report.xmpWritePlans.first?.flatKeywordProvenance.isEmpty ?? true)

        let decodedReport = try decodeReport(at: result.normalizeResult.report.artifacts.reportPath)
        XCTAssertEqual(decodedReport.xmpExportReport?.writtenCount, 1)
        XCTAssertEqual(decodedReport.errors, [])
        let progress = try decodeProgress(at: decodedReport.artifacts.progressPath)
        XCTAssertTrue(progress.contains {
            $0.stage == .xmpTarget
                && $0.status == .completed
                && $0.targetRelativePath == "Bird.xmp"
        })
    }

    func testPartialAnalysisFailureNormalizesOnlySuccessfulRawSidecarsAndReportsFailure() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: vocabularyPath).deletingLastPathComponent())
        }
        _ = try writeTestImage("Bird.JPG", in: root)
        try Data("not an image".utf8).write(to: root.appendingPathComponent("Notes.txt"))

        let result = try await pipeline().run(
            inputPath: root.path,
            runConfiguration: runConfiguration(outputDir: output.path, recursive: false),
            normalizationConfiguration: normalizationConfiguration(outputDir: output.path, vocabularyPath: vocabularyPath)
        )

        XCTAssertEqual(result.analyzeResult.records.map(\.status), [.failed, .written])
        XCTAssertEqual(result.normalizeResult.report.inputSummary.sourceAssetCount, 1)
        XCTAssertEqual(result.normalizeResult.report.inputSummary.failureCount, 1)
        XCTAssertEqual(result.normalizeResult.report.errors.map(\.code), [.unsupportedFormat])
        XCTAssertEqual(result.normalizeResult.report.xmpExportReport?.inputFailures.map(\.error.code), [.unsupportedFormat])
        XCTAssertEqual(result.normalizeResult.report.xmpExportReport?.targetReports.first?.status, .created)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.xmp").path))
    }

    func testNoWriteAIJSONRemovesNewRawSidecarsButKeepsNormalizationProvenance() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: vocabularyPath).deletingLastPathComponent())
        }
        _ = try writeTestImage("Bird.JPG", in: root)
        var normalize = normalizationConfiguration(outputDir: output.path, vocabularyPath: vocabularyPath)
        normalize.writeAIJSON = false

        let result = try await pipeline().run(
            inputPath: root.path,
            runConfiguration: runConfiguration(outputDir: output.path, recursive: true),
            normalizationConfiguration: normalize
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.JPG.ai.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.xmp").path))
        XCTAssertEqual(result.normalizeResult.session.sourceAISidecars.count, 1)
        XCTAssertEqual(result.normalizeResult.report.sourceAssets.first?.sourceSidecarPath, output.appendingPathComponent("Bird.JPG.ai.json").path)
        XCTAssertEqual(result.normalizeResult.report.xmpExportReport?.writtenCount, 1)
    }

    func testModelPrepareFailureLeavesNoNormalizationArtifactsOrXMP() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: vocabularyPath).deletingLastPathComponent())
        }
        _ = try writeTestImage("Bird.JPG", in: root)
        let prepareError = SidecarError(
            code: .modelTagNotFound,
            stage: .model,
            message: "missing model",
            recoverable: false
        )

        do {
            _ = try await pipeline(runner: AnalyzeNormalizeVisionRunner(prepareError: prepareError)).run(
                inputPath: root.path,
                runConfiguration: runConfiguration(outputDir: output.path, recursive: true),
                normalizationConfiguration: normalizationConfiguration(outputDir: output.path, vocabularyPath: vocabularyPath)
            )
            XCTFail("Expected model preparation to fail.")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelTagNotFound)
        }

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }

    func testGPSContextAndCoordinateCandidateAreNotExportedAsLocationKeywords() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: vocabularyPath).deletingLastPathComponent())
        }
        _ = try writeTestImage(
            "GPSBird.JPG",
            gps: (latitude: 40.7128, longitude: -74.0060),
            in: root
        )
        let runner = AnalyzeNormalizeVisionRunner(
            response: Self.response([
                "main_subjects": .array([Self.candidate("bird", confidence: "high")]),
                "proposed_keywords": .array([
                    Self.candidate("40.7128, -74.0060", confidence: "high", evidence: "GPS coordinates only")
                ])
            ])
        )

        let result = try await pipeline(runner: runner).run(
            inputPath: root.path,
            runConfiguration: runConfiguration(outputDir: output.path, recursive: true, gpsContext: .exact),
            normalizationConfiguration: normalizationConfiguration(outputDir: output.path, vocabularyPath: vocabularyPath)
        )

        let prompts = await runner.capturedPrompts()
        XCTAssertTrue(prompts.allSatisfy { $0.contains("MODEL INPUT CONTEXT") })
        XCTAssertTrue(prompts.allSatisfy { $0.contains("latitude: 40.7128") })
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: output.appendingPathComponent("GPSBird.xmp").path)
        XCTAssertEqual(snapshot.flatKeywords, ["Birds"])
        XCTAssertEqual(snapshot.hierarchicalKeywords, ["Subject|Wildlife|Birds"])
        XCTAssertFalse(snapshot.flatKeywords.contains { $0.contains("40.7128") || $0.contains("-74.0060") })
        XCTAssertFalse(snapshot.hierarchicalKeywords.contains { $0.contains("40.7128") || $0.contains("-74.0060") })
        XCTAssertEqual(result.normalizeResult.report.xmpExportReport?.writtenCount, 1)
    }

    private func pipeline(runner: any VisionModelRunner = AnalyzeNormalizeVisionRunner()) -> AnalyzeAndNormalizePipeline {
        AnalyzeAndNormalizePipeline(
            logger: Logger(sink: { _ in }),
            runner: runner,
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_003_000))
        )
    }

    private func runConfiguration(
        outputDir: String,
        recursive: Bool,
        gpsContext: GPSContextMode = .coarse
    ) -> ResolvedRunConfiguration {
        ResolvedRunConfiguration(
            mode: .whole,
            existing: .overwrite,
            recursive: recursive,
            outputDir: outputDir,
            model: ResolvedRunConfiguration.builtInDefaults.model,
            modelEndpoint: ResolvedRunConfiguration.builtInDefaults.modelEndpoint,
            modelKeepAlive: ModelRunOptions.default.keepAlive,
            profile: ResolvedRunConfiguration.builtInDefaults.profile,
            logLevel: .debug,
            logFormat: .json,
            dryRun: false,
            debugDerivatives: false,
            sourceIdentityPolicy: .sha256,
            derivativeCacheDir: URL(fileURLWithPath: outputDir).appendingPathComponent("cache").path,
            derivativeCacheSizeBytes: 20 * 1024 * 1024,
            stageConcurrency: 1,
            gpsContext: gpsContext
        )
    }

    private func normalizationConfiguration(
        outputDir: String,
        vocabularyPath: String
    ) -> ResolvedNormalizationConfiguration {
        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .controlledVocabulary
        configuration.recursive = true
        configuration.outputDir = outputDir
        configuration.vocabularyPath = vocabularyPath
        configuration.normalizationMode = .singleImage
        return configuration
    }

    private func writeVocabulary() throws -> String {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("vocabulary.json")
        try vocabularyData(entries: minimalVocabularyEntries()).write(to: file)
        return file.path
    }

    private func decodeReport(at path: String) throws -> NormalizationReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NormalizationReport.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    private func decodeProgress(at path: String) throws -> [NormalizationProgressRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let text = String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
        return try text
            .split(separator: "\n")
            .map { try decoder.decode(NormalizationProgressRecord.self, from: Data($0.utf8)) }
    }

    private func fixedDateProvider(_ date: Date) -> @Sendable () -> Date {
        { date }
    }

    fileprivate static func response(_ fields: [String: JSONValue]) -> JSONValue {
        var object: [String: JSONValue] = [
            "summary": .string("fixture"),
            "uncertainty_notes": .string("")
        ]
        for (field, value) in fields {
            object[field] = value
        }
        return .object(object)
    }

    fileprivate static func candidate(
        _ term: String,
        confidence: String,
        evidence: String = "visible evidence"
    ) -> JSONValue {
        .object([
            "term": .string(term),
            "confidence": .string(confidence),
            "evidence": .string(evidence)
        ])
    }
}

private actor AnalyzeNormalizeVisionRunner: VisionModelRunner {
    private let context = ModelRuntimeContext(
        model: "test:model",
        modelDigest: "sha256:testdigest",
        runtime: "test-runtime",
        runtimeVersion: "1.0",
        endpoint: URL(string: "http://localhost:11434")!,
        installedVisionTags: ["test:model"]
    )
    private let prepareError: SidecarError?
    private let response: JSONValue
    private var prompts: [String] = []

    init(
        prepareError: SidecarError? = nil,
        response: JSONValue = AnalyzeAndNormalizePipelineTests.response([
            "main_subjects": .array([AnalyzeAndNormalizePipelineTests.candidate("bird", confidence: "high")])
        ])
    ) {
        self.prepareError = prepareError
        self.response = response
    }

    func prepare(configuration _: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        if let prepareError {
            throw prepareError
        }
        return context
    }

    func analyze(
        image: DerivativeRecord,
        inputRole: ModelInputRole,
        prompt: VersionedPrompt,
        schema: JSONSchemaDocument,
        options: ModelRunOptions,
        runtime: ModelRuntimeContext,
        isInterrupted _: (@Sendable () -> Bool)? = nil
    ) async -> ModelRunRecord {
        prompts.append(prompt.text)
        return ModelRunRecord(
            inputRole: inputRole,
            model: runtime.model,
            modelDigest: runtime.modelDigest,
            runtime: runtime.runtime,
            runtimeVersion: runtime.runtimeVersion,
            promptVersion: prompt.version,
            promptSHA256: prompt.sha256,
            responseSchemaVersion: schema.version,
            requestOptions: options,
            inputDerivativeSHA256: image.sha256,
            rawResponseText: #"{"fixture":true}"#,
            parsedResponseJSON: response,
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    func capturedPrompts() -> [String] {
        prompts
    }
}
