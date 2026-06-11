import CoreGraphics
import XCTest
@testable import AISidecarCore

final class ModelInputExportPipelineTests: XCTestCase {
    func testSingleFileWholeExportWritesOnlyWholeImageAndManifest() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        let image = try writeTestImage("A.JPG", in: root)

        let result = try await pipeline().run(
            inputPath: image.path,
            exportDirectoryPath: export.path,
            configuration: config(
                recursive: false,
                mode: .whole,
                cacheDir: root.appendingPathComponent("cache").path
            )
        )

        let manifest = try decodeManifest(result)
        let whole = export.appendingPathComponent("A.JPG.aisidecar.whole_image.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: whole.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.manifestPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.appendingPathComponent("A.JPG.aisidecar.full_resolution.tiff").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.appendingPathComponent("A.JPG.aisidecar.subject_isolated.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("A.JPG.ai.json").path))
        XCTAssertEqual(manifest.schemaVersion, "ai-sidecar-model-input-export/1.0")
        XCTAssertEqual(manifest.mode, .whole)
        XCTAssertEqual(manifest.records.map(\.status), [.exported])
        XCTAssertEqual(manifest.records.first?.outputs.map(\.role), [.wholeImage])
        XCTAssertEqual(manifest.records.first?.outputs.first?.action, .exported)
        XCTAssertEqual(manifest.summary.exported, 1)
        XCTAssertEqual(manifest.summary.failed, 0)
    }

    func testRecursiveFolderExportMirrorsRelativeTree() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        _ = try writeTestImage("2026/06/_DSC1234.JPG", in: root)
        _ = try writeTestImage("2026/07/_DSC1234.JPG", in: root)

        let result = try await pipeline().run(
            inputPath: root.path,
            exportDirectoryPath: export.path,
            configuration: config(
                recursive: true,
                mode: .whole,
                cacheDir: root.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.exported, .exported])
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.appendingPathComponent("2026/06/_DSC1234.JPG.aisidecar.whole_image.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.appendingPathComponent("2026/07/_DSC1234.JPG.aisidecar.whole_image.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.appendingPathComponent("_DSC1234.JPG.aisidecar.whole_image.jpg").path))
        XCTAssertEqual(try decodeManifest(result).summary.totalImages, 2)
    }

    func testSubjectExportWritesOnlySubjectIsolatedModelInput() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        let image = try writeTestImage("Subject.JPG", width: 120, height: 80, in: root)

        let result = try await pipeline(maskProvider: StaticForegroundMaskProvider([
            StaticMaskSpec(index: 1, rect: CGRect(x: 40, y: 20, width: 30, height: 20))
        ])).run(
            inputPath: image.path,
            exportDirectoryPath: export.path,
            configuration: config(
                recursive: false,
                mode: .subject,
                cacheDir: root.appendingPathComponent("cache").path
            )
        )

        let manifest = try decodeManifest(result)
        XCTAssertEqual(manifest.records.map(\.status), [.exported])
        XCTAssertEqual(manifest.records.first?.outputs.map(\.role), [.subjectIsolated])
        XCTAssertEqual(manifest.records.first?.subjectIsolation?.status, .success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.appendingPathComponent("Subject.JPG.aisidecar.subject_isolated.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.appendingPathComponent("Subject.JPG.aisidecar.whole_image.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.appendingPathComponent("Subject.JPG.aisidecar.full_resolution.tiff").path))
    }

    func testBothModeNoForegroundExportsWholeImageAndRecordsPartialError() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        let image = try writeTestImage("Both.JPG", width: 120, height: 80, in: root)

        let result = try await pipeline(maskProvider: StaticForegroundMaskProvider([])).run(
            inputPath: image.path,
            exportDirectoryPath: export.path,
            configuration: config(
                recursive: false,
                mode: .both,
                cacheDir: root.appendingPathComponent("cache").path
            )
        )

        let manifest = try decodeManifest(result)
        XCTAssertEqual(manifest.records.map(\.status), [.partial])
        XCTAssertEqual(manifest.records.first?.errors.first?.code, .subjectIsolationNoForeground)
        XCTAssertEqual(manifest.records.first?.outputs.map(\.role), [.wholeImage])
        XCTAssertEqual(manifest.summary.partial, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.appendingPathComponent("Both.JPG.aisidecar.whole_image.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.appendingPathComponent("Both.JPG.aisidecar.subject_isolated.jpg").path))
    }

    func testSubjectModeNoForegroundRecordsFailureWithoutOutput() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        let image = try writeTestImage("NoForeground.JPG", width: 120, height: 80, in: root)

        let result = try await pipeline(maskProvider: StaticForegroundMaskProvider([])).run(
            inputPath: image.path,
            exportDirectoryPath: export.path,
            configuration: config(
                recursive: false,
                mode: .subject,
                cacheDir: root.appendingPathComponent("cache").path
            )
        )

        let manifest = try decodeManifest(result)
        XCTAssertEqual(manifest.records.map(\.status), [.failed])
        XCTAssertEqual(manifest.records.first?.subjectIsolation?.status, .noForeground)
        XCTAssertEqual(manifest.records.first?.errors.first?.code, .subjectIsolationNoForeground)
        XCTAssertTrue(manifest.records.first?.outputs.isEmpty == true)
        XCTAssertEqual(manifest.summary.failed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.appendingPathComponent("NoForeground.JPG.aisidecar.subject_isolated.jpg").path))
    }

    func testExistingPolicyOverwriteReplacesOutput() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        let image = try writeTestImage("A.JPG", in: root)
        let output = export.appendingPathComponent("A.JPG.aisidecar.whole_image.jpg")
        let stale = Data("stale".utf8)
        try write(stale, to: output)

        let result = try await pipeline().run(
            inputPath: image.path,
            exportDirectoryPath: export.path,
            configuration: config(
                recursive: false,
                existing: .overwrite,
                mode: .whole,
                cacheDir: root.appendingPathComponent("cache").path
            )
        )

        XCTAssertNotEqual(try Data(contentsOf: output), stale)
        let manifest = try decodeManifest(result)
        XCTAssertEqual(manifest.records.map(\.status), [.exported])
        XCTAssertEqual(manifest.records.first?.outputs.first?.action, .exported)
    }

    func testExistingPolicySkipLeavesOutputUntouched() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        let image = try writeTestImage("A.JPG", in: root)
        let output = export.appendingPathComponent("A.JPG.aisidecar.whole_image.jpg")
        let stale = Data("stale".utf8)
        try write(stale, to: output)

        let result = try await pipeline().run(
            inputPath: image.path,
            exportDirectoryPath: export.path,
            configuration: config(
                recursive: false,
                existing: .skip,
                mode: .whole,
                cacheDir: root.appendingPathComponent("cache").path
            )
        )

        XCTAssertEqual(try Data(contentsOf: output), stale)
        let manifest = try decodeManifest(result)
        XCTAssertEqual(manifest.records.map(\.status), [.skippedExisting])
        XCTAssertEqual(manifest.records.first?.outputs.first?.action, .skippedExisting)
    }

    func testExistingPolicyFailAvoidsRenderingWhenOutputExists() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        let image = try writeTestImage("A.JPG", in: root)
        let cache = root.appendingPathComponent("cache")
        try write(Data("stale".utf8), to: export.appendingPathComponent("A.JPG.aisidecar.whole_image.jpg"))

        let result = try await pipeline().run(
            inputPath: image.path,
            exportDirectoryPath: export.path,
            configuration: config(
                recursive: false,
                existing: .fail,
                mode: .whole,
                cacheDir: cache.path
            )
        )

        let manifest = try decodeManifest(result)
        XCTAssertEqual(manifest.records.map(\.status), [.failed])
        XCTAssertEqual(manifest.records.first?.errors.first?.code, .sidecarExists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    func testClearDerivativeCacheAfterSuccessfulExportKeepsExportedFiles() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        let image = try writeTestImage("A.JPG", in: root)
        let cache = root.appendingPathComponent("cache")

        let result = try await pipeline().run(
            inputPath: image.path,
            exportDirectoryPath: export.path,
            configuration: config(
                recursive: false,
                mode: .whole,
                cacheDir: cache.path,
                clearDerivativeCacheAfterSuccess: true
            )
        )

        XCTAssertEqual(result.records.map(\.status), [.exported])
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.appendingPathComponent("A.JPG.aisidecar.whole_image.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.manifestPath))
        XCTAssertEqual(try cacheContents(at: cache), [])
    }

    func testExportModeRejectsDryRunAndDebugDerivatives() async throws {
        let root = try temporaryDirectory()
        let export = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: export)
        }
        let image = try writeTestImage("A.JPG", in: root)

        for invalidConfig in [
            config(
                recursive: false,
                mode: .whole,
                dryRun: true,
                cacheDir: root.appendingPathComponent("dry-cache").path
            ),
            config(
                recursive: false,
                mode: .whole,
                debugDerivatives: true,
                cacheDir: root.appendingPathComponent("debug-cache").path
            )
        ] {
            do {
                _ = try await pipeline().run(
                    inputPath: image.path,
                    exportDirectoryPath: export.path,
                    configuration: invalidConfig
                )
                XCTFail("Expected export configuration to fail.")
            } catch let error as SidecarError {
                XCTAssertEqual(error.code, .configInvalid)
            }
        }
    }

    private func pipeline(maskProvider: (any ForegroundMaskProvider)? = nil) -> ModelInputExportPipeline {
        ModelInputExportPipeline(
            logger: Logger(sink: { _ in }),
            maskProvider: maskProvider,
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_001_000))
        )
    }

    private func config(
        recursive: Bool,
        existing: ExistingPolicy = .overwrite,
        mode: AnalysisMode,
        dryRun: Bool = false,
        debugDerivatives: Bool = false,
        cacheDir: String,
        clearDerivativeCacheOnStart: Bool = false,
        clearDerivativeCacheAfterSuccess: Bool = false
    ) -> ResolvedRunConfiguration {
        ResolvedRunConfiguration(
            mode: mode,
            existing: existing,
            recursive: recursive,
            outputDir: nil,
            model: ResolvedRunConfiguration.builtInDefaults.model,
            modelEndpoint: ResolvedRunConfiguration.builtInDefaults.modelEndpoint,
            profile: ResolvedRunConfiguration.builtInDefaults.profile,
            logLevel: .debug,
            logFormat: .json,
            dryRun: dryRun,
            debugDerivatives: debugDerivatives,
            sourceIdentityPolicy: .sha256,
            derivativeCacheDir: cacheDir,
            derivativeCacheSizeBytes: 20 * 1024 * 1024,
            clearDerivativeCacheOnStart: clearDerivativeCacheOnStart,
            clearDerivativeCacheAfterSuccess: clearDerivativeCacheAfterSuccess
        )
    }

    private func decodeManifest(_ result: ModelInputExportResult) throws -> ModelInputExportManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            ModelInputExportManifest.self,
            from: Data(contentsOf: URL(fileURLWithPath: result.manifestPath))
        )
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
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
}
