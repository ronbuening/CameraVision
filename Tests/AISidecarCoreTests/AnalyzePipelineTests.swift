import CoreGraphics
import XCTest
@testable import AISidecarCore

final class AnalyzePipelineTests: XCTestCase {
    func testWholeModeWritesModelRunAndProvenance() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("A.JPG", in: root)
        let runner = RecordingVisionModelRunner()

        let result = try await pipeline(runner: runner).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .whole,
                cacheDir: output.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.written])
        let sidecar = try decodeSidecar(output.appendingPathComponent("A.JPG.ai.json"))
        XCTAssertEqual(sidecar.modelRuns.map(\.inputRole), [.wholeImage])
        let run = try XCTUnwrap(sidecar.modelRuns.first)
        XCTAssertEqual(run.model, "test:model")
        XCTAssertEqual(run.modelDigest, "sha256:testdigest")
        XCTAssertEqual(run.runtime, "test-runtime")
        XCTAssertEqual(run.runtimeVersion, "1.0")
        XCTAssertFalse(run.promptVersion.isEmpty)
        XCTAssertFalse(run.promptSHA256.isEmpty)
        XCTAssertFalse(run.responseSchemaVersion.isEmpty)
        XCTAssertEqual(run.requestOptions.keepAlive, "30m")
        XCTAssertEqual(run.inputDerivativeSHA256, sidecar.derivatives.first { $0.role == .wholeImage }?.sha256)
        XCTAssertEqual(sidecar.runConfiguration.stageConcurrency, 2)
        XCTAssertTrue(sidecar.errors.isEmpty)
    }

    func testBothModeWritesTwoRunsPerImageAndSerializesModelCalls() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeTestImage("Birds/A.JPG", width: 120, height: 80, in: root)
        _ = try writeTestImage("Birds/B.JPG", width: 120, height: 80, in: root)
        let runner = RecordingVisionModelRunner(delayNanoseconds: 5_000_000)

        let result = try await pipeline(
            maskProvider: StaticForegroundMaskProvider([
                StaticMaskSpec(index: 1, rect: CGRect(x: 40, y: 20, width: 30, height: 20))
            ]),
            runner: runner
        ).run(
            inputPath: root.path,
            configuration: config(
                recursive: true,
                outputDir: output.path,
                mode: .both,
                cacheDir: output.appendingPathComponent("cache").path,
                stageConcurrency: 2
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.written, .written])
        for relativePath in ["Birds/A.JPG.ai.json", "Birds/B.JPG.ai.json"] {
            let sidecar = try decodeSidecar(output.appendingPathComponent(relativePath))
            XCTAssertEqual(sidecar.derivatives.map(\.role), [.fullResolution, .wholeImage, .subjectIsolated])
            XCTAssertEqual(sidecar.modelRuns.map(\.inputRole), [.wholeImage, .subjectIsolated])
            XCTAssertEqual(sidecar.subjectIsolation?.status, .success)
        }
        let calls = await runner.capturedCalls()
        let maxInFlight = await runner.maximumInFlight()
        XCTAssertEqual(calls.map(\.inputRole), [
            .wholeImage,
            .subjectIsolated,
            .wholeImage,
            .subjectIsolated
        ])
        XCTAssertEqual(maxInFlight, 1)
    }

    func testModelFailureIsPreservedInRunTopLevelErrorsAndProgress() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("BrokenModel.JPG", in: root)
        let modelError = SidecarError(
            code: .modelInvalidJSON,
            stage: .model,
            message: "fixture invalid JSON",
            recoverable: true
        )
        let runner = RecordingVisionModelRunner(failures: [RoleFailure(role: .wholeImage, error: modelError)])

        let result = try await pipeline(runner: runner).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .whole,
                cacheDir: output.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.failed])
        XCTAssertEqual(result.records.first?.errors.map(\.code), [.modelInvalidJSON])
        let sidecar = try decodeSidecar(output.appendingPathComponent("BrokenModel.JPG.ai.json"))
        XCTAssertEqual(sidecar.modelRuns.first?.error?.code, .modelInvalidJSON)
        XCTAssertEqual(sidecar.modelRuns.first?.jsonValid, false)
        XCTAssertEqual(sidecar.errors.map(\.code), [.modelInvalidJSON])
    }

    func testPrepareFailureFailsBeforeProgressSidecarsSummaryOrCache() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeTestImage("A.JPG", in: root)
        let prepareError = SidecarError(
            code: .modelTagNotFound,
            stage: .model,
            message: "missing model",
            recoverable: false
        )
        let runner = RecordingVisionModelRunner(prepareError: prepareError)

        do {
            _ = try await pipeline(runner: runner).run(
                inputPath: root.path,
                configuration: config(
                    recursive: false,
                    outputDir: output.path,
                    mode: .whole,
                    cacheDir: output.appendingPathComponent("cache").path
                )
            )
            XCTFail("Expected model prepare to fail fast.")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelTagNotFound)
        }

        let outputContents = try FileManager.default.contentsOfDirectory(atPath: output.path)
        XCTAssertTrue(outputContents.isEmpty)
        let prepareCount = await runner.prepareCount()
        let calls = await runner.capturedCalls()
        XCTAssertEqual(prepareCount, 1)
        XCTAssertTrue(calls.isEmpty)
    }

    func testExistingSkipAvoidsPrepareRenderAndModelWork() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeFile("AlreadyDone.JPG", data: Data("not an image".utf8), in: root)
        let sidecar = output.appendingPathComponent("AlreadyDone.JPG.ai.json")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: sidecar)
        let runner = RecordingVisionModelRunner(
            prepareError: SidecarError(
                code: .modelTagNotFound,
                stage: .model,
                message: "should not prepare",
                recoverable: false
            )
        )

        let result = try await pipeline(runner: runner).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                existing: .skip,
                mode: .whole,
                cacheDir: output.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.skippedExisting])
        let prepareCount = await runner.prepareCount()
        let calls = await runner.capturedCalls()
        XCTAssertEqual(prepareCount, 0)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("cache").path))
    }

    private func pipeline(
        maskProvider: (any ForegroundMaskProvider)? = nil,
        runner: RecordingVisionModelRunner
    ) -> AnalyzePipeline {
        AnalyzePipeline(
            logger: Logger(sink: { _ in }),
            maskProvider: maskProvider,
            runner: runner,
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_002_000))
        )
    }

    private func config(
        recursive: Bool,
        outputDir: String?,
        existing: ExistingPolicy = .overwrite,
        mode: AnalysisMode,
        cacheDir: String,
        stageConcurrency: Int = 2
    ) -> ResolvedRunConfiguration {
        ResolvedRunConfiguration(
            mode: mode,
            existing: existing,
            recursive: recursive,
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
            stageConcurrency: stageConcurrency
        )
    }

    private func decodeSidecar(_ url: URL) throws -> RawJSONSidecar {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RawJSONSidecar.self, from: Data(contentsOf: url))
    }

    private func writeFile(_ relativePath: String, data: Data, in root: URL) throws -> URL {
        let file = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file)
        return file
    }

    private func fixedDateProvider(_ date: Date) -> @Sendable () -> Date {
        { date }
    }
}

private struct CapturedModelCall: Sendable, Equatable {
    var inputRole: ModelInputRole
    var derivativeSHA256: String
    var promptVersion: String
    var schemaVersion: String
}

private struct RoleFailure: Sendable {
    var role: ModelInputRole
    var error: SidecarError
}

private actor RecordingVisionModelRunner: VisionModelRunner {
    private let context: ModelRuntimeContext
    private let prepareError: SidecarError?
    private let failures: [RoleFailure]
    private let delayNanoseconds: UInt64
    private var prepareCalls = 0
    private var calls: [CapturedModelCall] = []
    private var inFlight = 0
    private var maxInFlight = 0

    init(
        prepareError: SidecarError? = nil,
        failures: [RoleFailure] = [],
        delayNanoseconds: UInt64 = 0
    ) {
        self.context = ModelRuntimeContext(
            model: "test:model",
            modelDigest: "sha256:testdigest",
            runtime: "test-runtime",
            runtimeVersion: "1.0",
            endpoint: URL(string: "http://localhost:11434")!,
            installedVisionTags: ["test:model"]
        )
        self.prepareError = prepareError
        self.failures = failures
        self.delayNanoseconds = delayNanoseconds
    }

    func prepare(configuration _: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        prepareCalls += 1
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
        runtime: ModelRuntimeContext
    ) async -> ModelRunRecord {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        calls.append(
            CapturedModelCall(
                inputRole: inputRole,
                derivativeSHA256: image.sha256,
                promptVersion: prompt.version,
                schemaVersion: schema.version
            )
        )
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        inFlight -= 1

        if let failure = failures.first(where: { $0.role == inputRole }) {
            return record(
                image: image,
                inputRole: inputRole,
                prompt: prompt,
                schema: schema,
                options: options,
                runtime: runtime,
                parsed: nil,
                jsonValid: false,
                error: failure.error
            )
        }

        return record(
            image: image,
            inputRole: inputRole,
            prompt: prompt,
            schema: schema,
            options: options,
            runtime: runtime,
            parsed: .object(["input_role": .string(inputRole.rawValue)]),
            jsonValid: true,
            error: nil
        )
    }

    func capturedCalls() -> [CapturedModelCall] {
        calls
    }

    func maximumInFlight() -> Int {
        maxInFlight
    }

    func prepareCount() -> Int {
        prepareCalls
    }

    private func record(
        image: DerivativeRecord,
        inputRole: ModelInputRole,
        prompt: VersionedPrompt,
        schema: JSONSchemaDocument,
        options: ModelRunOptions,
        runtime: ModelRuntimeContext,
        parsed: JSONValue?,
        jsonValid: Bool,
        error: SidecarError?
    ) -> ModelRunRecord {
        ModelRunRecord(
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
            parsedResponseJSON: parsed,
            jsonValid: jsonValid,
            durationMs: 1,
            error: error
        )
    }
}
