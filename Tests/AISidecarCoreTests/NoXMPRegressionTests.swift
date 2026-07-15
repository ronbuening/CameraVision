import CoreGraphics
import Foundation
import XCTest
@testable import AISidecarCore

final class NoXMPRegressionTests: XCTestCase {
    func testAnalyzePipelineRemainsXMPSilent() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("Analyze.JPG", width: 80, height: 60, in: root)
        let cache = output.appendingPathComponent("cache")

        _ = try await AnalyzeShellPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_010_000))
        ).run(
            inputPath: image.path,
            configuration: config(outputDir: output.path, cacheDir: cache.path)
        )

        try assertNoXMPFiles(in: [root, output, cache])
    }

    func testQualityEnabledAnalyzePipelineRemainsXMPSilent() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("AnalyzeQuality.JPG", width: 80, height: 60, in: root)
        let cache = output.appendingPathComponent("cache")
        let context = ModelRuntimeContext(
            model: "test:model",
            modelDigest: "sha256:test",
            runtime: "test",
            runtimeVersion: "1.0",
            endpoint: URL(string: "http://localhost:11434")!,
            installedVisionTags: ["test:model"]
        )

        _ = try await AnalyzePipeline(
            logger: Logger(sink: { _ in }),
            runner: RecordedFixtureRunner(fixture: RecordedModelFixture(context: context, records: [])),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_010_050))
        ).run(
            inputPath: image.path,
            configuration: config(
                outputDir: output.path,
                cacheDir: cache.path,
                taskProfile: .taggingWithQuality
            )
        )

        try assertNoXMPFiles(in: [root, output, cache])
    }

    func testBenchmarkSelfTestRemainsXMPSilent() throws {
        let root = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        _ = try Milestone9BenchmarkRunner().run(options: BenchmarkOptions(
            outputDir: root.path,
            selfTest: true
        ))

        try assertNoXMPFiles(in: [root])
    }

    func testPurgeDoesNotModifyXMPFiles() throws {
        let root = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let cache = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let xmp = cache.appendingPathComponent("Existing.xmp")
        let xmpData = Data("<xmp/>".utf8)
        try xmpData.write(to: xmp)
        let derivative = cache.appendingPathComponent("\(String(repeating: "a", count: 64))-whole_image.jpg")
        try Data("derivative".utf8).write(to: derivative)

        _ = try DerivativeCache(directoryPath: cache.path, sizeCapBytes: 1024).purge()

        XCTAssertEqual(try Data(contentsOf: xmp), xmpData)
    }

    func testModelInputExportRemainsXMPSilent() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        let image = try writeTestImage("Export.JPG", width: 80, height: 60, in: root)
        let cache = root.appendingPathComponent("cache")

        _ = try await ModelInputExportPipeline(
            logger: Logger(sink: { _ in }),
            maskProvider: StaticForegroundMaskProvider([
                StaticMaskSpec(index: 1, rect: CGRect(x: 20, y: 15, width: 30, height: 20))
            ]),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_010_100))
        ).run(
            inputPath: image.path,
            exportDirectoryPath: export.path,
            configuration: config(outputDir: nil, cacheDir: cache.path, mode: .both)
        )

        try assertNoXMPFiles(in: [root, export, cache])
    }

    func testNormalizeValidationAndPlanningHelpersRemainXMPSilent() throws {
        let root = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let xmp = root.appendingPathComponent("Existing.xmp")
        let xmpData = Data("<xmp/>".utf8)
        try xmpData.write(to: xmp)

        _ = try NormalizationInvocationValidator.validate(
            NormalizationInvocationRequest(inputPath: root.path)
        )
        _ = try ApplySessionInvocationValidator.validate(
            ApplySessionInvocationRequest(sessionPath: root.appendingPathComponent("session.json").path)
        )
        _ = try DefaultVocabulary.load()
        _ = NormalizationArtifactPlanner.planNormalize(
            inputBasePath: root.path,
            outputDir: nil,
            writeReportPath: nil,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(try Data(contentsOf: xmp), xmpData)
    }

    private func config(
        outputDir: String?,
        cacheDir: String,
        mode: AnalysisMode = .whole,
        taskProfile: ModelTaskProfile = .tagging
    ) -> ResolvedRunConfiguration {
        ResolvedRunConfiguration(
            mode: mode,
            existing: .overwrite,
            recursive: false,
            taskProfile: taskProfile,
            outputDir: outputDir,
            model: ResolvedRunConfiguration.builtInDefaults.model,
            modelEndpoint: ResolvedRunConfiguration.builtInDefaults.modelEndpoint,
            profile: ResolvedRunConfiguration.builtInDefaults.profile,
            logLevel: .debug,
            logFormat: .json,
            dryRun: false,
            debugDerivatives: false,
            sourceIdentityPolicy: .sha256,
            derivativeCacheDir: cacheDir,
            derivativeCacheSizeBytes: 20 * 1024 * 1024
        )
    }

    private func fixedDateProvider(_ date: Date) -> @Sendable () -> Date {
        { date }
    }
}
