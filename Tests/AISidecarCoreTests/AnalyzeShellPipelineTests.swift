import XCTest
@testable import AISidecarCore

final class AnalyzeShellPipelineTests: XCTestCase {
    func testSingleFileRunWritesOnlySidecarWithoutBatchArtifacts() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeFile("A.NEF", data: Data("nef".utf8), in: root)

        let result = try AnalyzeShellPipeline(
            logger: Logger(sink: { _ in }),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_050))
        ).run(
            inputPath: image.path,
            configuration: config(recursive: false, outputDir: nil)
        )

        XCTAssertEqual(result.records.map(\.status), [.written])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("A.NEF.ai.json").path))
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
        _ = try writeFile("2026/06/_DSC1234.NEF", data: Data("nef".utf8), in: root)
        _ = try writeFile("2026/07/_DSC1234.NEF", data: Data("jpg".utf8), in: root)
        _ = try writeFile("2026/07/notes.txt", data: Data("notes".utf8), in: root)
        let logs = LockedLogSink()
        let pipeline = AnalyzeShellPipeline(
            logger: Logger(minimumLevel: .debug, format: .json, sink: logs.append),
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        )

        let result = try pipeline.run(
            inputPath: root.path,
            configuration: config(recursive: true, outputDir: output.path)
        )

        let juneSidecar = output.appendingPathComponent("2026/06/_DSC1234.NEF.ai.json")
        let julySidecar = output.appendingPathComponent("2026/07/_DSC1234.NEF.ai.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: juneSidecar.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: julySidecar.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("_DSC1234.NEF.ai.json").path))
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
        XCTAssertEqual(sidecar.source.relativePath, "2026/06/_DSC1234.NEF")
        XCTAssertTrue(sidecar.derivatives.isEmpty)
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
            configuration: config(recursive: false, outputDir: output.path, dryRun: true)
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
        _ = try writeFile("A.NEF", data: Data("nef".utf8), in: root)
        let configuration = config(recursive: false, outputDir: output.path, existing: .skip)

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
            configuration: config(recursive: false, outputDir: output.path),
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
        dryRun: Bool = false
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
            debugDerivatives: false,
            sourceIdentityPolicy: .sha256
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
