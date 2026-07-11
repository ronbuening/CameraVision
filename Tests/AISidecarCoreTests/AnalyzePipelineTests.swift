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
        XCTAssertFalse(run.requestOptions.thinkingEnabled)
        XCTAssertEqual(run.inputDerivativeSHA256, sidecar.derivatives.first { $0.role == .wholeImage }?.sha256)
        XCTAssertEqual(sidecar.runConfiguration.stageConcurrency, 2)
        XCTAssertNotNil(sidecar.timing)
        XCTAssertEqual(sidecar.timing?.subjectIsolationMs, 0)
        XCTAssertEqual(sidecar.timing?.modelMs, 0)
        XCTAssertEqual(sidecar.timing?.writeMs, 0)
        XCTAssertTrue(sidecar.errors.isEmpty)
    }

    func testPipelineUsesConfiguredModelRequestOptionsAndKeepsThinkingDisabled() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("A.JPG", in: root)
        let runner = RecordingVisionModelRunner()

        _ = try await pipeline(runner: runner).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .whole,
                cacheDir: output.appendingPathComponent("cache").path,
                modelKeepAlive: "5m",
                modelTimeoutSeconds: 90,
                modelRetryLimit: 4
            )
        )

        let sidecar = try decodeSidecar(output.appendingPathComponent("A.JPG.ai.json"))
        let capturedCalls = await runner.capturedCalls()
        let captured = try XCTUnwrap(capturedCalls.first)
        XCTAssertEqual(sidecar.runConfiguration.modelKeepAlive, "5m")
        XCTAssertEqual(sidecar.modelRuns.first?.requestOptions.keepAlive, "5m")
        XCTAssertEqual(sidecar.runConfiguration.modelTimeoutSeconds, 90)
        XCTAssertEqual(sidecar.runConfiguration.modelRetryLimit, 4)
        XCTAssertEqual(sidecar.modelRuns.first?.requestOptions.timeoutSeconds, 90)
        XCTAssertEqual(sidecar.modelRuns.first?.requestOptions.retryLimit, 4)
        XCTAssertEqual(captured.keepAlive, "5m")
        XCTAssertEqual(captured.timeoutSeconds, 90)
        XCTAssertEqual(captured.retryLimit, 4)
        XCTAssertFalse(captured.thinkingEnabled)
    }

    func testContextWindowZeroSendsNoNumCtxAndPositivePinsIt() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("A.JPG", in: root)

        // Built-in default (0) means "model default": no num_ctx reaches the runner.
        let defaultRunner = RecordingVisionModelRunner()
        _ = try await pipeline(runner: defaultRunner).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .whole,
                cacheDir: output.appendingPathComponent("cache").path
            )
        )
        let defaultCalls = await defaultRunner.capturedCalls()
        let defaultCall = try XCTUnwrap(defaultCalls.first)
        XCTAssertNil(defaultCall.contextWindow)

        let pinnedRunner = RecordingVisionModelRunner()
        _ = try await pipeline(runner: pinnedRunner).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                existing: .overwrite,
                mode: .whole,
                cacheDir: output.appendingPathComponent("cache").path,
                modelContextWindow: 16_384
            )
        )
        let pinnedCalls = await pinnedRunner.capturedCalls()
        let pinnedCall = try XCTUnwrap(pinnedCalls.first)
        XCTAssertEqual(pinnedCall.contextWindow, 16_384)
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
            XCTAssertEqual(sidecar.derivatives.map(\.role), [.wholeImage, .subjectIsolated])
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

    func testInterruptionBetweenRolesSkipsSecondRoleAndFailsClosed() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeTestImage("Bird.JPG", width: 120, height: 80, in: root)
        let monitor = InterruptionMonitor()
        let runner = RecordingVisionModelRunner(
            onAnalyze: { role in
                if role == .wholeImage {
                    monitor.requestInterruption()
                }
            }
        )

        let result = try await pipeline(
            maskProvider: StaticForegroundMaskProvider([
                StaticMaskSpec(index: 1, rect: CGRect(x: 40, y: 20, width: 30, height: 20))
            ]),
            runner: runner
        ).run(
            inputPath: root.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .both,
                cacheDir: output.appendingPathComponent("cache").path
            ),
            interruptionMonitor: monitor
        )

        XCTAssertTrue(result.interrupted)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.summary?.errors.map(\.code), [.interrupted])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.JPG.ai.json").path)
        )
        let calls = await runner.capturedCalls()
        let cancellationObserved = await runner.observedCancellation()
        XCTAssertEqual(calls.map(\.inputRole), [.wholeImage])
        XCTAssertTrue(cancellationObserved)
    }

    func testCancelledModelRunWritesNoSidecarAndCanBeRetriedWithExistingSkip() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("Bird.JPG", in: root)
        let runner = CancellationAwareVisionModelRunner()
        let configuration = config(
            recursive: false,
            outputDir: output.path,
            existing: .skip,
            mode: .whole,
            cacheDir: output.appendingPathComponent("cache").path
        )
        let inputPath = image.path
        let task = Task {
            let analysisPipeline = AnalyzePipeline(
                logger: Logger(sink: { _ in }),
                runner: runner,
                now: { Date(timeIntervalSince1970: 1_800_002_000) }
            )
            return try await analysisPipeline.run(
                inputPath: inputPath,
                configuration: configuration
            )
        }

        await runner.waitUntilStarted()
        task.cancel()
        let cancelledResult = try await task.value

        XCTAssertTrue(cancelledResult.interrupted)
        XCTAssertTrue(cancelledResult.records.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.JPG.ai.json").path)
        )
        let cancellationObserved = await runner.observedCancellation()
        XCTAssertTrue(cancellationObserved)

        let retryResult = try await pipeline(runner: RecordingVisionModelRunner()).run(
            inputPath: image.path,
            configuration: configuration,
            writesBatchArtifacts: false
        )
        XCTAssertEqual(retryResult.records.map(\.status), [.written])
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.JPG.ai.json").path)
        )
    }

    func testStageConcurrencyOneDoesNotRenderAheadDuringModelCall() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeTestImage("A.JPG", width: 1600, height: 1200, in: root)
        _ = try writeTestImage("B.JPG", width: 1600, height: 1200, in: root)
        _ = try writeTestImage("C.JPG", width: 1600, height: 1200, in: root)
        let cacheDir = output.appendingPathComponent("cache")
        let probe = CacheSnapshotProbe(cacheDir: cacheDir)
        let runner = RecordingVisionModelRunner(
            onAnalyze: { _ in
                await probe.captureFirstModelCallCacheState()
            }
        )

        let result = try await pipeline(runner: runner).run(
            inputPath: root.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .whole,
                cacheDir: cacheDir.path,
                stageConcurrency: 1
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.written, .written, .written])
        let capturedCount = await probe.firstWholeImageCount()
        let countDuringFirstModelCall = try XCTUnwrap(capturedCount)
        XCTAssertEqual(countDuringFirstModelCall, 1)
    }

    func testGPSContextIsSentToBothModelRolesAndRecordedInSidecar() async throws {
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
        let runner = RecordingVisionModelRunner()

        let result = try await pipeline(
            maskProvider: StaticForegroundMaskProvider([
                StaticMaskSpec(index: 1, rect: CGRect(x: 40, y: 20, width: 30, height: 20))
            ]),
            runner: runner
        ).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .both,
                cacheDir: output.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.written])
        let calls = await runner.capturedCalls()
        XCTAssertEqual(calls.map(\.inputRole), [.wholeImage, .subjectIsolated])
        XCTAssertTrue(calls.allSatisfy { $0.promptText.contains("MODEL INPUT CONTEXT") })
        XCTAssertTrue(calls.allSatisfy { $0.promptText.contains("latitude: 45.2") })
        XCTAssertTrue(calls.allSatisfy { $0.promptText.contains("longitude: -122.6") })

        let sidecar = try decodeSidecar(output.appendingPathComponent("GPSBird.JPG.ai.json"))
        XCTAssertEqual(sidecar.runConfiguration.gpsContext, .coarse)
        XCTAssertEqual(sidecar.modelRuns.map(\.modelInputContext?.gps?.mode), [.coarse, .coarse])
        for run in sidecar.modelRuns {
            XCTAssertEqual(run.modelInputContext?.gps?.latitude ?? 0, 45.2, accuracy: 0.000001)
            XCTAssertEqual(run.modelInputContext?.gps?.longitude ?? 0, -122.6, accuracy: 0.000001)
        }
    }

    func testBothModeNoForegroundWritesWholeRunWithRecoverableError() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("NoForeground.JPG", width: 120, height: 80, in: root)
        let runner = RecordingVisionModelRunner()

        let result = try await pipeline(
            maskProvider: StaticForegroundMaskProvider([]),
            runner: runner
        ).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .both,
                cacheDir: output.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.written])
        XCTAssertEqual(result.records.first?.errors.map(\.code), [.subjectIsolationNoForeground])
        let sidecar = try decodeSidecar(output.appendingPathComponent("NoForeground.JPG.ai.json"))
        XCTAssertEqual(sidecar.derivatives.map(\.role), [.wholeImage])
        XCTAssertEqual(sidecar.subjectIsolation?.status, .noForeground)
        XCTAssertEqual(sidecar.modelRuns.map(\.inputRole), [.wholeImage])
        XCTAssertEqual(sidecar.errors.map(\.code), [.subjectIsolationNoForeground])
        let calls = await runner.capturedCalls()
        XCTAssertEqual(calls.map(\.inputRole), [.wholeImage])
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

    func testSuccessfulModelRepairWritesValidRunWithoutTopLevelError() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("RepairedModel.JPG", in: root)
        let runner = RecordingVisionModelRunner(repairs: [RoleRepair(role: .wholeImage, outcome: .success)])

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
        XCTAssertTrue(result.records.first?.errors.isEmpty == true)
        let sidecar = try decodeSidecar(output.appendingPathComponent("RepairedModel.JPG.ai.json"))
        let run = try XCTUnwrap(sidecar.modelRuns.first)
        XCTAssertTrue(run.jsonValid)
        XCTAssertNil(run.error)
        XCTAssertTrue(sidecar.errors.isEmpty)
        XCTAssertEqual(run.responseAttempts?.map(\.kind), [.primary, .repair])
        XCTAssertEqual(run.responseAttempts?.map(\.jsonValid), [false, true])
    }

    func testFailedModelRepairRecordsFinalErrorAndAttempts() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("RepairFailed.JPG", in: root)
        let runner = RecordingVisionModelRunner(repairs: [RoleRepair(role: .wholeImage, outcome: .failure)])

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
        XCTAssertEqual(result.records.first?.errors.map(\.code), [.modelSchemaViolation])
        let sidecar = try decodeSidecar(output.appendingPathComponent("RepairFailed.JPG.ai.json"))
        let run = try XCTUnwrap(sidecar.modelRuns.first)
        XCTAssertFalse(run.jsonValid)
        XCTAssertEqual(run.error?.code, .modelSchemaViolation)
        XCTAssertEqual(sidecar.errors.map(\.code), [.modelSchemaViolation])
        XCTAssertEqual(run.responseAttempts?.map(\.kind), [.primary, .repair])
        XCTAssertEqual(run.responseAttempts?.map { $0.error?.code }, [
            SidecarErrorCode.modelInvalidJSON,
            SidecarErrorCode.modelSchemaViolation
        ])
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

    func testClearDerivativeCacheOnStartRemovesStaleArtifactsBeforeSkipRun() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeFile("AlreadyDone.JPG", data: Data("not an image".utf8), in: root)
        let sidecar = output.appendingPathComponent("AlreadyDone.JPG.ai.json")
        let cacheDir = output.appendingPathComponent("cache")
        let staleArtifact = cacheDir.appendingPathComponent("\(String(repeating: "a", count: 64))-recipe-v1-whole_image.jpg")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: staleArtifact)
        try Data("{}".utf8).write(to: sidecar)

        let result = try await pipeline(runner: RecordingVisionModelRunner()).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                existing: .skip,
                mode: .whole,
                cacheDir: cacheDir.path,
                clearDerivativeCacheOnStart: true
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.skippedExisting])
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleArtifact.path))
    }

    func testClearDerivativeCacheAfterSuccessfulRunRemovesGeneratedArtifacts() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("A.JPG", in: root)
        let cacheDir = output.appendingPathComponent("cache")

        let result = try await pipeline(runner: RecordingVisionModelRunner()).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .whole,
                cacheDir: cacheDir.path,
                clearDerivativeCacheAfterSuccess: true
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.written])
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("A.JPG.ai.json").path))
        XCTAssertEqual(try cacheContents(at: cacheDir), [])
    }

    func testOwnedBatchArtifactsDoNotBlockPostSuccessCacheClearOnRerun() async throws {
        let root = try temporaryDirectory()
        let cacheRoot = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: cacheRoot)
        }
        _ = try writeTestImage("A.JPG", in: root)
        let cacheDir = cacheRoot.appendingPathComponent("cache")
        let baseConfiguration = config(
            recursive: false,
            outputDir: nil,
            existing: .skip,
            mode: .whole,
            cacheDir: cacheDir.path
        )

        let first = try await pipeline(runner: RecordingVisionModelRunner()).run(
            inputPath: root.path,
            configuration: baseConfiguration
        )

        XCTAssertEqual(first.records.map(\.status), [.written])
        XCTAssertFalse(try cacheContents(at: cacheDir).isEmpty)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.hasPrefix(ArtifactNames.batchProgressPrefix) }.isEmpty
        )

        var rerunConfiguration = baseConfiguration
        rerunConfiguration.clearDerivativeCacheAfterSuccess = true
        let rerun = try await pipeline(runner: RecordingVisionModelRunner()).run(
            inputPath: root.path,
            configuration: rerunConfiguration
        )

        XCTAssertEqual(rerun.records.map(\.status), [.skippedExisting])
        XCTAssertTrue(rerun.scanResult.errors.isEmpty)
        XCTAssertEqual(try cacheContents(at: cacheDir), [])
    }

    func testClearDerivativeCacheAfterSuccessDoesNotRunForFailedAnalysis() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("BrokenModel.JPG", in: root)
        let cacheDir = output.appendingPathComponent("cache")
        let modelError = SidecarError(
            code: .modelInvalidJSON,
            stage: .model,
            message: "fixture invalid JSON",
            recoverable: true
        )

        let result = try await pipeline(
            runner: RecordingVisionModelRunner(failures: [RoleFailure(role: .wholeImage, error: modelError)])
        ).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .whole,
                cacheDir: cacheDir.path,
                clearDerivativeCacheAfterSuccess: true
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.failed])
        XCTAssertFalse(try cacheContents(at: cacheDir).isEmpty)
    }

    private func pipeline(
        maskProvider: (any ForegroundMaskProvider)? = nil,
        runner: any VisionModelRunner
    ) -> AnalyzePipeline {
        AnalyzePipeline(
            logger: Logger(sink: { _ in }),
            maskProvider: maskProvider,
            runner: runner,
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_002_000)),
            filenameSuffix: { "a3f2" }
        )
    }

    private func config(
        recursive: Bool,
        outputDir: String?,
        existing: ExistingPolicy = .overwrite,
        mode: AnalysisMode,
        cacheDir: String,
        stageConcurrency: Int = 2,
        modelKeepAlive: String = ModelRunOptions.default.keepAlive,
        modelTimeoutSeconds: Double = ModelRunOptions.default.timeoutSeconds,
        modelRetryLimit: Int = ModelRunOptions.default.retryLimit,
        clearDerivativeCacheOnStart: Bool = false,
        clearDerivativeCacheAfterSuccess: Bool = false,
        modelContextWindow: Int = ResolvedRunConfiguration.builtInDefaults.modelContextWindow
    ) -> ResolvedRunConfiguration {
        ResolvedRunConfiguration(
            mode: mode,
            existing: existing,
            recursive: recursive,
            outputDir: outputDir,
            model: ResolvedRunConfiguration.builtInDefaults.model,
            modelEndpoint: ResolvedRunConfiguration.builtInDefaults.modelEndpoint,
            modelKeepAlive: modelKeepAlive,
            modelTimeoutSeconds: modelTimeoutSeconds,
            modelRetryLimit: modelRetryLimit,
            profile: ResolvedRunConfiguration.builtInDefaults.profile,
            logLevel: .debug,
            logFormat: .json,
            dryRun: false,
            debugDerivatives: false,
            sourceIdentityPolicy: .sha256,
            derivativeCacheDir: cacheDir,
            derivativeCacheSizeBytes: 20 * 1024 * 1024,
            clearDerivativeCacheOnStart: clearDerivativeCacheOnStart,
            clearDerivativeCacheAfterSuccess: clearDerivativeCacheAfterSuccess,
            stageConcurrency: stageConcurrency,
            modelContextWindow: modelContextWindow
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

    private func cacheContents(at directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func fixedDateProvider(_ date: Date) -> @Sendable () -> Date {
        { date }
    }

    // MARK: - CORE-1: in-process progress handler

    func testProgressHandlerReceivesEveryEmittedRecordAlongsideLogWrites() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeTestImage("A.JPG", in: root)
        _ = try writeTestImage("B.JPG", in: root)
        let captured = RecordBox()

        let result = try await pipeline(runner: RecordingVisionModelRunner()).run(
            inputPath: root.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .whole,
                cacheDir: output.appendingPathComponent("cache").path
            ),
            progressHandler: { captured.append($0) }
        )

        XCTAssertEqual(captured.records, result.records, "handler sees exactly the emitted records, in order")
        let progressLogPath = try XCTUnwrap(result.progressLogPath)
        XCTAssertEqual(
            progressLogPath,
            output.appendingPathComponent("batch-progress-2027-01-15T083320Z-a3f2.jsonl").path
        )
        XCTAssertEqual(
            result.summaryPath,
            output.appendingPathComponent("batch-summary-2027-01-15T083320Z-a3f2.json").path
        )
        let logLines = try String(contentsOfFile: progressLogPath, encoding: .utf8)
            .split(separator: "\n").count
        XCTAssertEqual(logLines, result.records.count, "hook is additive — the JSONL log is unchanged")
    }

    // MARK: - CORE-2: batch-artifact opt-out

    func testWritesBatchArtifactsFalseWritesSidecarsButNoReports() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeTestImage("A.JPG", in: root)

        let result = try await pipeline(runner: RecordingVisionModelRunner()).run(
            inputPath: root.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                mode: .whole,
                cacheDir: output.appendingPathComponent("cache").path
            ),
            writesBatchArtifacts: false
        )

        XCTAssertNil(result.progressLogPath)
        XCTAssertNil(result.summaryPath)
        XCTAssertEqual(result.records.map(\.status), [.written])
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("A.JPG.ai.json").path))
        let reportFiles = try FileManager.default.contentsOfDirectory(atPath: output.path)
            .filter { $0.hasPrefix("batch-") }
        XCTAssertTrue(reportFiles.isEmpty, "no batch-progress/batch-summary artifacts in GUI mode")
    }

    // MARK: - CORE-3: sliced runs equal one full run

    func testTwoSliceRunMatchesSingleFullRun() async throws {
        let root = try temporaryDirectory()
        let slicedOutput = try temporaryDirectory()
        let fullOutput = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: slicedOutput)
            try? FileManager.default.removeItem(at: fullOutput)
        }
        let first = try writeTestImage("A.JPG", in: root)
        _ = try writeTestImage("B.JPG", in: root)
        _ = try writeTestImage("C.JPG", in: root)
        let names = ["A.JPG.ai.json", "B.JPG.ai.json", "C.JPG.ai.json"]

        func sliceConfig(outputDir: String) -> ResolvedRunConfiguration {
            // `.skip` in every run: the GUI pause/resume pattern re-invokes the
            // pipeline and relies on skip semantics to make re-runs additive.
            config(
                recursive: false,
                outputDir: outputDir,
                existing: .skip,
                mode: .whole,
                cacheDir: outputDir + "/cache"
            )
        }

        // Slice 1: just the first file. Slice 2: the whole folder, skipping it.
        let slice1 = try await pipeline(runner: RecordingVisionModelRunner()).run(
            inputPath: first.path,
            configuration: sliceConfig(outputDir: slicedOutput.path)
        )
        XCTAssertEqual(slice1.records.map(\.status), [.written])
        let slice2 = try await pipeline(runner: RecordingVisionModelRunner()).run(
            inputPath: root.path,
            configuration: sliceConfig(outputDir: slicedOutput.path),
            writesBatchArtifacts: false
        )
        XCTAssertEqual(
            slice2.records.map(\.status).sorted { "\($0)" < "\($1)" },
            [.skippedExisting, .written, .written].sorted { "\($0)" < "\($1)" }
        )

        let full = try await pipeline(runner: RecordingVisionModelRunner()).run(
            inputPath: root.path,
            configuration: sliceConfig(outputDir: fullOutput.path),
            writesBatchArtifacts: false
        )
        XCTAssertEqual(full.records.map(\.status), [.written, .written, .written])

        for name in names {
            let sliced = try Data(contentsOf: slicedOutput.appendingPathComponent(name))
            let fullData = try Data(contentsOf: fullOutput.appendingPathComponent(name))
            XCTAssertEqual(
                normalizedSidecarJSON(sliced, strippingOutputDir: slicedOutput.path),
                normalizedSidecarJSON(fullData, strippingOutputDir: fullOutput.path),
                "\(name): sliced result must match the uninterrupted run"
            )
        }
    }

    /// Sidecars embed the output directory in recorded paths; normalize it so
    /// the sliced and full runs (different output dirs) compare equal.
    private func normalizedSidecarJSON(_ data: Data, strippingOutputDir dir: String) -> String {
        String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: dir, with: "<out>")
    }
}

/// Thread-safe capture box for the @Sendable progress handler.
private final class RecordBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ProgressRecord] = []

    func append(_ record: ProgressRecord) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(record)
    }

    var records: [ProgressRecord] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct CapturedModelCall: Sendable, Equatable {
    var inputRole: ModelInputRole
    var derivativeSHA256: String
    var promptVersion: String
    var promptText: String
    var schemaVersion: String
    var keepAlive: String
    var timeoutSeconds: Double
    var retryLimit: Int
    var thinkingEnabled: Bool
    var contextWindow: Int?
}

private struct RoleFailure: Sendable {
    var role: ModelInputRole
    var error: SidecarError
}

private enum RepairOutcome: Sendable, Equatable {
    case success
    case failure
}

private struct RoleRepair: Sendable {
    var role: ModelInputRole
    var outcome: RepairOutcome
}

private actor RecordingVisionModelRunner: VisionModelRunner {
    private let context: ModelRuntimeContext
    private let prepareError: SidecarError?
    private let failures: [RoleFailure]
    private let repairs: [RoleRepair]
    private let delayNanoseconds: UInt64
    private let onAnalyze: (@Sendable (ModelInputRole) async -> Void)?
    private var prepareCalls = 0
    private var calls: [CapturedModelCall] = []
    private var inFlight = 0
    private var maxInFlight = 0
    private var cancellationObserved = false

    init(
        prepareError: SidecarError? = nil,
        failures: [RoleFailure] = [],
        repairs: [RoleRepair] = [],
        delayNanoseconds: UInt64 = 0,
        onAnalyze: (@Sendable (ModelInputRole) async -> Void)? = nil
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
        self.repairs = repairs
        self.delayNanoseconds = delayNanoseconds
        self.onAnalyze = onAnalyze
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
        runtime: ModelRuntimeContext,
        isInterrupted _: (@Sendable () -> Bool)? = nil
    ) async -> ModelRunRecord {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        calls.append(
            CapturedModelCall(
                inputRole: inputRole,
                derivativeSHA256: image.sha256,
                promptVersion: prompt.version,
                promptText: prompt.text,
                schemaVersion: schema.version,
                keepAlive: options.keepAlive,
                timeoutSeconds: options.timeoutSeconds,
                retryLimit: options.retryLimit,
                thinkingEnabled: options.thinkingEnabled,
                contextWindow: options.contextWindow
            )
        )
        await onAnalyze?(inputRole)
        if Task.isCancelled {
            cancellationObserved = true
        }
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

        if let repair = repairs.first(where: { $0.role == inputRole }) {
            return repairedRecord(
                image: image,
                inputRole: inputRole,
                prompt: prompt,
                schema: schema,
                options: options,
                runtime: runtime,
                outcome: repair.outcome
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

    func observedCancellation() -> Bool {
        cancellationObserved
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
        error: SidecarError?,
        responseAttempts: [ModelResponseAttemptRecord]? = nil
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
            error: error,
            responseAttempts: responseAttempts
        )
    }

    private func repairedRecord(
        image: DerivativeRecord,
        inputRole: ModelInputRole,
        prompt: VersionedPrompt,
        schema: JSONSchemaDocument,
        options: ModelRunOptions,
        runtime: ModelRuntimeContext,
        outcome: RepairOutcome
    ) -> ModelRunRecord {
        let primaryError = SidecarError(
            code: .modelInvalidJSON,
            stage: .model,
            message: "fixture primary invalid JSON",
            recoverable: true
        )
        let finalError = SidecarError(
            code: .modelSchemaViolation,
            stage: .model,
            message: "fixture repair schema violation",
            recoverable: true
        )
        let repairIsValid = outcome == .success
        let repairParsed: JSONValue = repairIsValid
            ? .object(["summary": .string("repaired")])
            : .object(["summary": .number(5)])
        let attempts = [
            ModelResponseAttemptRecord(
                kind: .primary,
                promptVersion: prompt.version,
                promptSHA256: prompt.sha256,
                responseSchemaVersion: schema.version,
                requestOptions: options,
                rawResponseText: "not json",
                parsedResponseJSON: nil,
                jsonValid: false,
                durationMs: 1,
                error: primaryError
            ),
            ModelResponseAttemptRecord(
                kind: .repair,
                promptVersion: "aisidecar.prompt.model_response_repair/1.0.0",
                promptSHA256: String(repeating: "b", count: 64),
                responseSchemaVersion: schema.version,
                requestOptions: options,
                rawResponseText: repairIsValid ? #"{"summary":"repaired"}"# : #"{"summary":5}"#,
                parsedResponseJSON: repairParsed,
                jsonValid: repairIsValid,
                durationMs: 1,
                error: repairIsValid ? nil : finalError
            )
        ]
        return record(
            image: image,
            inputRole: inputRole,
            prompt: prompt,
            schema: schema,
            options: options,
            runtime: runtime,
            parsed: repairParsed,
            jsonValid: repairIsValid,
            error: repairIsValid ? nil : finalError,
            responseAttempts: attempts
        )
    }
}

private actor CancellationAwareVisionModelRunner: VisionModelRunner {
    private var started = false
    private var cancelled = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func observedCancellation() -> Bool {
        cancelled
    }

    func prepare(configuration _: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        ModelRuntimeContext(
            model: "test:model",
            modelDigest: "sha256:testdigest",
            runtime: "test-runtime",
            runtimeVersion: "1.0",
            endpoint: URL(string: "http://localhost:11434")!,
            installedVisionTags: ["test:model"]
        )
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
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        } catch is CancellationError {
            cancelled = true
        } catch {}

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
            rawResponseText: "",
            parsedResponseJSON: nil,
            jsonValid: false,
            durationMs: 0,
            error: SidecarError(
                code: .interrupted,
                stage: .model,
                message: "Model request cancelled.",
                recoverable: true
            )
        )
    }
}

private actor CacheSnapshotProbe {
    private let cacheDir: URL
    private var capturedWholeImageCount: Int?

    init(cacheDir: URL) {
        self.cacheDir = cacheDir
    }

    func captureFirstModelCallCacheState() async {
        guard capturedWholeImageCount == nil else {
            return
        }
        // Give any incorrectly scheduled render-ahead work time to write its
        // cache artifact while the current model call is still active.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path)) ?? []
        capturedWholeImageCount = names.filter { $0.hasSuffix("-whole_image.jpg") }.count
    }

    func firstWholeImageCount() -> Int? {
        capturedWholeImageCount
    }
}
