import XCTest
@testable import AISidecarCore

final class AnalyzeShellPipelineTests: XCTestCase {
    func testSingleFileRunWritesOnlySidecarWithoutBatchArtifacts() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeTestImage("A.JPG", in: root)

        let result = try AnalyzeShellPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_050))
        ).run(
            inputPath: image.path,
            configuration: config(recursive: false, outputDir: nil, cacheDir: root.appendingPathComponent("cache").path)
        )

        XCTAssertEqual(result.records.map(\.status), [.written])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("A.JPG.ai.json").path))
        XCTAssertNil(result.progressLogPath)
        XCTAssertNil(result.summaryPath)
        XCTAssertNil(result.summary)
        let batchArtifacts = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("batch-") }
        XCTAssertTrue(batchArtifacts.isEmpty)
    }

    func testRecursiveFolderRunWritesMirroredShellSidecarsProgressLogAndSummary() throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeTestImage("2026/06/_DSC1234.JPG", in: root)
        _ = try writeTestImage("2026/07/_DSC1234.JPG", in: root)
        _ = try writeFile("2026/07/notes.txt", data: Data("notes".utf8), in: root)
        let logs = LockedLogSink()
        let pipeline = AnalyzeShellPipeline(
            logger: Logger(minimumLevel: .debug, format: .json, sink: logs.append),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        )

        let result = try pipeline.run(
            inputPath: root.path,
            configuration: config(recursive: true, outputDir: output.path, cacheDir: output.appendingPathComponent("cache").path)
        )

        let juneSidecar = output.appendingPathComponent("2026/06/_DSC1234.JPG.ai.json")
        let julySidecar = output.appendingPathComponent("2026/07/_DSC1234.JPG.ai.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: juneSidecar.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: julySidecar.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("_DSC1234.JPG.ai.json").path))
        XCTAssertEqual(result.records.map(\.status), [.failed, .written, .written])
        XCTAssertEqual(result.records.first?.errors.first?.code, .unsupportedFormat)
        XCTAssertNotNil(result.progressLogPath)
        XCTAssertNotNil(result.summaryPath)
        XCTAssertEqual(result.summary?.written, 2)
        XCTAssertEqual(result.summary?.failed, 1)
        XCTAssertEqual(result.summary?.totalImages, 2)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(RawJSONSidecar.self, from: Data(contentsOf: juneSidecar))
        XCTAssertEqual(sidecar.schemaVersion, "ai-sidecar-json/1.0")
        XCTAssertEqual(sidecar.source.relativePath, "2026/06/_DSC1234.JPG")
        XCTAssertEqual(sidecar.modelInputProfile.name, "gemma4-26b-default")
        XCTAssertEqual(sidecar.derivatives.map(\.role), [.fullResolution, .wholeImage])
        XCTAssertTrue(sidecar.modelRuns.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("2026/06/_DSC1234.xmp").path))

        let progressLines = String(decoding: try Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(result.progressLogPath))), as: UTF8.self)
            .split(separator: "\n")
        XCTAssertEqual(progressLines.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(result.summaryPath)))
        XCTAssertFalse(logs.lines.isEmpty)
    }

    func testDryRunCreatesNoSidecarsProgressLogOrSummary() throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        try FileManager.default.removeItem(at: output)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeFile("A.NEF", data: Data("nef".utf8), in: root)

        let result = try AnalyzeShellPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_100))
        ).run(
            inputPath: root.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                dryRun: true,
                cacheDir: output.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.dryRun])
        XCTAssertNil(result.progressLogPath)
        XCTAssertNil(result.summaryPath)
        XCTAssertNil(result.summary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testRerunWithExistingSkipSkipsAlreadyWrittenSidecars() throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeTestImage("A.JPG", in: root)
        let configuration = config(
            recursive: false,
            outputDir: output.path,
            existing: .skip,
            cacheDir: output.appendingPathComponent("cache").path
        )

        _ = try AnalyzeShellPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_200))
        ).run(inputPath: root.path, configuration: configuration)

        let second = try AnalyzeShellPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_300))
        ).run(inputPath: root.path, configuration: configuration)

        XCTAssertEqual(second.records.map(\.status), [.skippedExisting])
        XCTAssertEqual(second.summary?.skipped, 1)
        XCTAssertEqual(second.summary?.written, 0)
    }

    func testExistingSkipAvoidsRenderingInvalidInput() throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeFile("Broken.JPG", data: Data("not an image".utf8), in: root)
        let existing = output.appendingPathComponent("Broken.JPG.ai.json")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: existing)

        let result = try AnalyzeShellPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_350))
        ).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                existing: .skip,
                cacheDir: output.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.skippedExisting])
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("cache").path))
    }

    func testRenderFailureWritesErrorSidecarAndFailedRecord() throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeFile("Broken.JPG", data: Data("not an image".utf8), in: root)

        let result = try AnalyzeShellPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_360))
        ).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                cacheDir: output.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.failed])
        XCTAssertEqual(result.records.first?.errors.first?.code, .decodeFailed)
        let sidecarURL = output.appendingPathComponent("Broken.JPG.ai.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(RawJSONSidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(sidecar.modelInputProfile.name, "gemma4-26b-default")
        XCTAssertTrue(sidecar.derivatives.isEmpty)
        XCTAssertEqual(sidecar.errors.first?.code, .decodeFailed)
    }

    func testDebugDerivativesAreCopiedBesideSourceAndRecorded() throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("Bird.JPG", in: root)

        let result = try AnalyzeShellPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_370))
        ).run(
            inputPath: image.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                debugDerivatives: true,
                cacheDir: output.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.written])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(
            RawJSONSidecar.self,
            from: Data(contentsOf: output.appendingPathComponent("Bird.JPG.ai.json"))
        )
        XCTAssertEqual(
            sidecar.derivatives.compactMap(\.debugPath).sorted(),
            [
                root.appendingPathComponent("Bird.JPG.aisidecar.full_resolution.tiff").path,
                root.appendingPathComponent("Bird.JPG.aisidecar.whole_image.jpg").path
            ].sorted()
        )
        XCTAssertTrue(sidecar.derivatives.allSatisfy { derivative in
            guard let debugPath = derivative.debugPath else { return false }
            return FileManager.default.fileExists(atPath: debugPath)
        })
    }

    func testInterruptedRunWritesInterruptedSummaryWithoutPartialSidecar() throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try writeFile("A.NEF", data: Data("nef".utf8), in: root)
        let monitor = InterruptionMonitor()
        monitor.requestInterruption()

        let result = try AnalyzeShellPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_400))
        ).run(
            inputPath: root.path,
            configuration: config(
                recursive: false,
                outputDir: output.path,
                cacheDir: output.appendingPathComponent("cache").path
            ),
            interruptionMonitor: monitor
        )

        XCTAssertTrue(result.interrupted)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.summary?.errors.map(\.code), [.interrupted])
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("A.NEF.ai.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(result.summaryPath)))
    }

    private func config(
        recursive: Bool,
        outputDir: String?,
        existing: ExistingPolicy = .skip,
        dryRun: Bool = false,
        debugDerivatives: Bool = false,
        cacheDir: String
    ) -> ResolvedRunConfiguration {
        ResolvedRunConfiguration(
            mode: .both,
            existing: existing,
            recursive: recursive,
            outputDir: outputDir,
            model: ResolvedRunConfiguration.builtInDefaults.model,
            modelEndpoint: ResolvedRunConfiguration.builtInDefaults.modelEndpoint,
            profile: ResolvedRunConfiguration.builtInDefaults.profile,
            logLevel: .debug,
            logFormat: .json,
            dryRun: dryRun,
            debugDerivatives: debugDerivatives,
            sourceIdentityPolicy: .sha256,
            derivativeCacheDir: cacheDir,
            derivativeCacheSizeBytes: 20 * 1024 * 1024
        )
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

private final class LockedLogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ line: String) {
        lock.lock()
        storage.append(line)
        lock.unlock()
    }
}
