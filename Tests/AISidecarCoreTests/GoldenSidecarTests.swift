import CoreGraphics
import Foundation
import XCTest
@testable import AISidecarCore

final class GoldenSidecarTests: XCTestCase {
    func testFullPipelineRecordedFixtureMatchesGoldenSidecar() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("Bird.JPG", width: 120, height: 80, in: root)
        let cacheDir = output.appendingPathComponent("cache")
        let maskProvider = StaticForegroundMaskProvider([
            StaticMaskSpec(index: 1, rect: CGRect(x: 45, y: 20, width: 30, height: 25))
        ])
        let configuration = config(outputDir: output.path, cacheDir: cacheDir.path)
        let fixture = try await recordedFixture(
            image: image,
            configuration: configuration,
            maskProvider: maskProvider
        )

        let result = try await AnalyzePipeline(
            logger: Logger(sink: { _ in }),
            maskProvider: maskProvider,
            runner: RecordedFixtureRunner(fixture: fixture),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_003_000))
        ).run(inputPath: image.path, configuration: configuration)

        XCTAssertEqual(result.records.map(\.status), [.written])
        let sidecarURL = output.appendingPathComponent("Bird.JPG.ai.json")
        let actual = try normalizedJSONString(for: try sidecarJSON(at: sidecarURL))
        let expected = try normalizedJSONString(for: try fixtureJSON(
            name: "phase1-both-normalized",
            extension: "json",
            subdirectory: "golden-sidecars"
        ))

        XCTAssertEqual(actual, expected)
        try assertNoXMPFiles(in: [root, output, cacheDir])
    }

    private func recordedFixture(
        image: URL,
        configuration: ResolvedRunConfiguration,
        maskProvider: StaticForegroundMaskProvider
    ) async throws -> RecordedModelFixture {
        let profile = try ModelInputProfileRegistry.resolve(name: configuration.profile)
        let source = try XCTUnwrap(
            ImageScanner().scan(
                inputPath: image.path,
                recursive: false,
                identityPolicy: configuration.sourceIdentityPolicy
            ).images.first
        )
        let cache = DerivativeCache(
            directoryPath: configuration.derivativeCacheDir,
            sizeCapBytes: configuration.derivativeCacheSizeBytes,
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_003_000))
        )
        let rendered = try ImageRenderer(cache: cache).renderWholeImageSet(
            source: source,
            profile: profile,
            debugDerivatives: false
        )
        let isolation = try await SubjectIsolationService(cache: cache, maskProvider: maskProvider).isolate(
            source: source,
            rendered: rendered,
            profile: profile,
            configuration: configuration
        )
        let whole = try XCTUnwrap(rendered.derivatives.first { $0.role == .wholeImage })
        let subject = try XCTUnwrap(isolation.derivative)
        let context = ModelRuntimeContext(
            model: "gemma4:26b-a4b-it-qat",
            modelDigest: "sha256:goldenmodeldigest",
            runtimeVersion: "0.12.6",
            endpoint: URL(string: "http://localhost:11434")!,
            installedVisionTags: ["gemma4:26b-a4b-it-qat"]
        )

        return RecordedModelFixture(
            context: context,
            records: [
                try modelRun(
                    role: .wholeImage,
                    derivative: whole,
                    context: context,
                    fixtureName: "whole_image_valid_v1_2"
                ),
                try modelRun(
                    role: .subjectIsolated,
                    derivative: subject,
                    context: context,
                    fixtureName: "subject_isolated_valid_v1_2"
                )
            ]
        )
    }

    private func modelRun(
        role: ModelInputRole,
        derivative: DerivativeRecord,
        context: ModelRuntimeContext,
        fixtureName: String
    ) throws -> ModelRunRecord {
        let parsedResponse = try fixtureJSON(name: fixtureName, extension: "json", subdirectory: "model-responses")
        let prompt = try PromptRegistry.prompt(for: role)
        let schema = try ResponseSchemas.schema(for: role)
        return ModelRunRecord(
            inputRole: role,
            model: context.model,
            modelDigest: context.modelDigest,
            runtime: context.runtime,
            runtimeVersion: context.runtimeVersion,
            promptVersion: prompt.version,
            promptSHA256: prompt.sha256,
            responseSchemaVersion: schema.version,
            requestOptions: .default,
            inputDerivativeSHA256: derivative.sha256,
            rawResponseText: try compactJSONString(for: parsedResponse),
            parsedResponseJSON: parsedResponse,
            jsonValid: true,
            durationMs: role == .wholeImage ? 17 : 19,
            error: nil
        )
    }

    private func config(outputDir: String, cacheDir: String) -> ResolvedRunConfiguration {
        ResolvedRunConfiguration(
            mode: .both,
            existing: .overwrite,
            recursive: false,
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
            derivativeCacheSizeBytes: 20 * 1024 * 1024,
            stageConcurrency: 1
        )
    }

    private func sidecarJSON(at url: URL) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    private func fixtureJSON(name: String, extension fileExtension: String, subdirectory: String) throws -> JSONValue {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
                ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
        )
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    private func normalizedJSONString(for value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(normalize(value))
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func compactJSONString(for value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func normalize(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            var normalized: [String: JSONValue] = [:]
            for (key, child) in object {
                normalized[key] = normalizedValue(forKey: key, value: child)
            }
            return .object(normalized)
        case .array(let values):
            return .array(values.map(normalize))
        default:
            return value
        }
    }

    private func normalizedValue(forKey key: String, value: JSONValue) -> JSONValue {
        switch key {
        case "path":
            return .string("<source-path>")
        case "cache_path":
            return .string("<cache-path>")
        case "output_dir", "derivative_cache_dir":
            return .string("<directory>")
        case "created_at", "modified_at":
            return .string("<timestamp>")
        case "duration_ms", "file_size":
            return .number(0)
        case "sha256":
            return .string("<sha256>")
        case "input_derivative_sha256":
            return .string("<derivative-sha256>")
        default:
            return normalize(value)
        }
    }

    private func fixedDateProvider(_ date: Date) -> @Sendable () -> Date {
        { date }
    }
}
