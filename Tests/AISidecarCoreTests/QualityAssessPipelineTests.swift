import CoreGraphics
import Foundation
import XCTest

@testable import AISidecarCore

final class QualityAssessPipelineTests: XCTestCase {
    func testFolderRunWritesQualitySidecarWithStandaloneContractsAndQualityArtifacts() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeTestImage("Bird.JPG", width: 120, height: 80, in: root)
        let runner = try QualityOnlyFixtureRunner()

        let result = try await pipeline(runner: runner).run(
            inputPath: root.path,
            configuration: config(output: output, mode: .both),
            progressHandler: nil
        )

        XCTAssertEqual(result.records.map(\.status), [.written])
        XCTAssertTrue(result.progressLogPath?.contains(ArtifactNames.qualityProgressPrefix) == true)
        XCTAssertTrue(result.summaryPath?.contains(ArtifactNames.qualitySummaryPrefix) == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.JPG.ai.json").path))

        let sidecarURL = output.appendingPathComponent("Bird.JPG.quality.ai.json")
        let sidecar = try RawJSONSidecarReader().read(from: sidecarURL).sidecar
        XCTAssertEqual(sidecar.runConfiguration.taskProfile, .qualityOnly)
        XCTAssertEqual(
            sidecar.modelRuns.map(\.promptVersion),
            [
                "aisidecar.prompt.whole_image_quality/1.0.0",
                "aisidecar.prompt.subject_isolated_quality/1.0.0",
            ]
        )
        XCTAssertEqual(
            sidecar.modelRuns.map(\.responseSchemaVersion),
            [
                "urn:aisidecar:response:whole-image-quality:1.0.0",
                "urn:aisidecar:response:subject-isolated-quality:1.0.0",
            ]
        )
        for run in sidecar.modelRuns {
            try JSONSchemaValidator.validate(
                try XCTUnwrap(run.parsedResponseJSON),
                against: ResponseSchemas.schema(for: run.inputRole, task: .qualityOnly)
            )
        }
    }

    func testDryRunWritesNothingAndPlansQualityPath() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("Bird.JPG", in: root)
        var configuration = config(output: output, mode: .whole)
        configuration.dryRun = true

        let result = try await pipeline(runner: try QualityOnlyFixtureRunner()).run(
            inputPath: image.path,
            configuration: configuration
        )

        XCTAssertEqual(result.records.map(\.status), [.dryRun])
        XCTAssertEqual(
            result.records.first?.sidecarPath, output.appendingPathComponent("Bird.JPG.quality.ai.json").path)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
    }

    func testExistingPoliciesTargetQualitySidecarWithoutTouchingTaggingSidecar() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("Bird.JPG", in: root)
        let taggingURL = output.appendingPathComponent("Bird.JPG.ai.json")
        let taggingData = Data(#"{"tagging":"preserve"}"#.utf8)
        try taggingData.write(to: taggingURL)

        var overwrite = config(output: output, mode: .whole)
        overwrite.existing = .overwrite
        let first = try await pipeline(runner: try QualityOnlyFixtureRunner()).run(
            inputPath: image.path,
            configuration: overwrite
        )
        XCTAssertEqual(first.records.map(\.status), [.written])
        XCTAssertEqual(try Data(contentsOf: taggingURL), taggingData)

        let qualityURL = output.appendingPathComponent("Bird.JPG.quality.ai.json")
        let qualityData = try Data(contentsOf: qualityURL)
        var skip = overwrite
        skip.existing = .skip
        let second = try await pipeline(runner: try QualityOnlyFixtureRunner()).run(
            inputPath: image.path,
            configuration: skip
        )
        XCTAssertEqual(second.records.map(\.status), [.skippedExisting])
        XCTAssertEqual(try Data(contentsOf: qualityURL), qualityData)
        XCTAssertEqual(try Data(contentsOf: taggingURL), taggingData)
    }

    func testQualityOnlySuppressesGPSModelInputContext() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage(
            "GPSBird.JPG",
            width: 120,
            height: 80,
            gps: (latitude: 45.16, longitude: -122.64),
            in: root
        )
        let runner = try QualityOnlyFixtureRunner()

        _ = try await pipeline(runner: runner).run(
            inputPath: image.path,
            configuration: config(output: output, mode: .whole)
        )

        let calls = await runner.capturedCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(try XCTUnwrap(calls.first).promptText.contains("MODEL INPUT CONTEXT"))
        let sidecar = try RawJSONSidecarReader().read(
            from: output.appendingPathComponent("GPSBird.JPG.quality.ai.json")
        ).sidecar
        XCTAssertNil(sidecar.modelRuns.first?.modelInputContext)
    }

    func testInterruptionBetweenAssetsStopsWithoutPartialSecondSidecar() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeTestImage("A.JPG", in: root)
        _ = try writeTestImage("B.JPG", in: root)
        let monitor = InterruptionMonitor()

        let result = try await pipeline(runner: try QualityOnlyFixtureRunner()).run(
            inputPath: root.path,
            configuration: config(output: output, mode: .whole),
            interruptionMonitor: monitor,
            progressHandler: { _ in monitor.requestInterruption() }
        )

        XCTAssertTrue(result.interrupted)
        XCTAssertEqual(result.records.map(\.status), [.written])
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("A.JPG.quality.ai.json").path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("B.JPG.quality.ai.json").path))
    }

    private func pipeline(runner: any VisionModelRunner) -> QualityAssessPipeline {
        QualityAssessPipeline(
            logger: Logger(sink: { _ in }),
            maskProvider: StaticForegroundMaskProvider([
                StaticMaskSpec(index: 1, rect: CGRect(x: 40, y: 20, width: 30, height: 20))
            ]),
            runner: runner,
            now: { Date(timeIntervalSince1970: 1_800_004_000) },
            filenameSuffix: { "a3f2" }
        )
    }

    private func config(output: URL, mode: AnalysisMode) -> ResolvedRunConfiguration {
        ResolvedRunConfiguration(
            mode: mode,
            existing: .overwrite,
            recursive: false,
            outputDir: output.path,
            model: ResolvedRunConfiguration.builtInDefaults.model,
            modelEndpoint: ResolvedRunConfiguration.builtInDefaults.modelEndpoint,
            profile: ResolvedRunConfiguration.builtInDefaults.profile,
            logLevel: .debug,
            logFormat: .json,
            dryRun: false,
            debugDerivatives: false,
            sourceIdentityPolicy: .sha256,
            derivativeCacheDir: output.appendingPathComponent("cache").path,
            derivativeCacheSizeBytes: 20 * 1024 * 1024,
            stageConcurrency: 1,
            gpsContext: .exact
        )
    }
}

private struct QualityFixtureCall: Sendable {
    var promptText: String
}

private actor QualityOnlyFixtureRunner: VisionModelRunner {
    private let context = ModelRuntimeContext(
        model: "test:model",
        modelDigest: "sha256:testdigest",
        runtime: "test-runtime",
        runtimeVersion: "1.0",
        endpoint: URL(string: "http://localhost:11434")!,
        installedVisionTags: ["test:model"]
    )
    private let responses: [ModelInputRole: JSONValue]
    private var calls: [QualityFixtureCall] = []

    init() throws {
        self.responses = [
            .wholeImage: try Self.fixture(named: "whole_image_quality_only_valid"),
            .subjectIsolated: try Self.fixture(named: "subject_isolated_with_quality_valid").qualityOnlyResponse,
        ]
    }

    func prepare(configuration _: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        context
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
        calls.append(QualityFixtureCall(promptText: prompt.text))
        let parsed = responses[inputRole]
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
            rawResponseText: "fixture",
            parsedResponseJSON: parsed,
            jsonValid: parsed != nil,
            durationMs: 1,
            error: nil
        )
    }

    func capturedCalls() -> [QualityFixtureCall] {
        calls
    }

    private static func fixture(named name: String) throws -> JSONValue {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "model-responses")
                ?? Bundle.module.url(forResource: name, withExtension: "json")
        )
        return try JSONCoding.decoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
}

extension JSONValue {
    fileprivate var qualityOnlyResponse: JSONValue {
        guard let qualityAssessment = objectValue?["quality_assessment"] else {
            return self
        }
        return .object(["quality_assessment": qualityAssessment])
    }
}
