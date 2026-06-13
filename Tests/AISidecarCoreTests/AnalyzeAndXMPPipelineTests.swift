import Foundation
import XCTest
@testable import AISidecarCore

final class AnalyzeAndXMPPipelineTests: XCTestCase {
    func testAnalyzeAndWriteCreatesRawSidecarAndXMP() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("Bird.JPG", in: root)

        let result = try await pipeline(runner: modelRunner()).run(
            inputPath: image.path,
            runConfiguration: runConfiguration(outputDir: output.path),
            exportConfiguration: exportConfiguration(outputDir: output.path)
        )

        XCTAssertEqual(result.analyzeResult.records.map(\.status), [.written])
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.JPG.ai.json").path))
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: output.appendingPathComponent("Bird.xmp").path)
        XCTAssertEqual(snapshot.flatKeywords, ["wading bird"])
        XCTAssertEqual(result.exportResult.report?.targetReports.first?.status, .created)
    }

    func testNoWriteAIJSONRemovesNewRawSidecarAfterExtraction() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("Bird.JPG", in: root)
        var export = exportConfiguration(outputDir: output.path)
        export.writeAIJSON = false

        let result = try await pipeline(runner: modelRunner()).run(
            inputPath: image.path,
            runConfiguration: runConfiguration(outputDir: output.path),
            exportConfiguration: export
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.JPG.ai.json").path))
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: output.appendingPathComponent("Bird.xmp").path)
        XCTAssertEqual(snapshot.flatKeywords, ["wading bird"])
        let provenance = try XCTUnwrap(
            result.exportResult.report?.targetReports.first?.plan.flatKeywordsToAdd.first?.candidates.first?.provenance
        )
        XCTAssertEqual(provenance.model, "test:model")
        XCTAssertEqual(provenance.modelDigest, "sha256:test")
        XCTAssertEqual(provenance.runtime, "test")
        XCTAssertEqual(provenance.runtimeVersion, "1.0")
        XCTAssertEqual(provenance.promptVersion, "prompt/1")
        XCTAssertEqual(provenance.responseSchemaVersion, "schema/1")
    }

    func testModelPrepareFailureLeavesNoXMP() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("Bird.JPG", in: root)

        do {
            _ = try await pipeline(runner: PrepareFailingRunner()).run(
                inputPath: image.path,
                runConfiguration: runConfiguration(outputDir: output.path),
                exportConfiguration: exportConfiguration(outputDir: output.path)
            )
            XCTFail("Expected model preparation to fail.")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelTagNotFound)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Bird.xmp").path))
    }

    func testXMPFailureDoesNotClearDerivativeCacheAfterAnalyzeSuccess() async throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let image = try writeTestImage("Bird.JPG", in: root)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try existingDevelopSettingsXMP.write(to: output.appendingPathComponent("Bird.xmp"), atomically: true, encoding: .utf8)
        var export = exportConfiguration(outputDir: output.path)
        export.xmpConflictPolicy = .fail
        export.backupSidecars = false
        let cacheDir = output.appendingPathComponent("cache")

        let result = try await pipeline(runner: modelRunner()).run(
            inputPath: image.path,
            runConfiguration: runConfiguration(
                outputDir: output.path,
                cacheDir: cacheDir.path,
                clearDerivativeCacheAfterSuccess: true
            ),
            exportConfiguration: export
        )

        XCTAssertEqual(result.analyzeResult.records.map(\.status), [.written])
        XCTAssertEqual(result.exportResult.report?.targetReports.first?.status, .failed)
        XCTAssertFalse(try cacheContents(at: cacheDir).isEmpty)
    }

    private func pipeline(runner: any VisionModelRunner) -> AnalyzeAndXMPPipeline {
        AnalyzeAndXMPPipeline(
            logger: Logger(sink: { _ in }),
            runner: runner,
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        )
    }

    private func runConfiguration(
        outputDir: String,
        cacheDir: String? = nil,
        clearDerivativeCacheAfterSuccess: Bool = false
    ) -> ResolvedRunConfiguration {
        ResolvedRunConfiguration(
            mode: .whole,
            existing: .overwrite,
            recursive: false,
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
            derivativeCacheDir: cacheDir ?? URL(fileURLWithPath: outputDir).appendingPathComponent("cache").path,
            derivativeCacheSizeBytes: 20 * 1024 * 1024,
            clearDerivativeCacheAfterSuccess: clearDerivativeCacheAfterSuccess,
            stageConcurrency: 1
        )
    }

    private func exportConfiguration(outputDir: String) -> ResolvedXMPExportConfiguration {
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.outputDir = outputDir
        return configuration
    }

    private func modelRunner() -> MockVisionModelRunner {
        MockVisionModelRunner(
            context: ModelRuntimeContext(
                model: "test:model",
                modelDigest: "sha256:test",
                runtime: "test",
                runtimeVersion: "1.0",
                endpoint: URL(string: "http://localhost:11434")!,
                installedVisionTags: ["test:model"]
            ),
            record: ModelRunRecord(
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
                            "term": .string("wading bird"),
                            "confidence": .string("high"),
                            "evidence": .string("fixture")
                        ])
                    ])
                ]),
                jsonValid: true,
                durationMs: 1,
                error: nil
            )
        )
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

private struct PrepareFailingRunner: VisionModelRunner {
    func prepare(configuration _: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        throw SidecarError(
            code: .modelTagNotFound,
            stage: .model,
            message: "missing model",
            recoverable: false
        )
    }

    func analyze(
        image _: DerivativeRecord,
        inputRole _: ModelInputRole,
        prompt _: VersionedPrompt,
        schema _: JSONSchemaDocument,
        options _: ModelRunOptions,
        runtime: ModelRuntimeContext
    ) async -> ModelRunRecord {
        ModelRunRecord(
            inputRole: .wholeImage,
            model: runtime.model,
            modelDigest: runtime.modelDigest,
            runtime: runtime.runtime,
            runtimeVersion: runtime.runtimeVersion,
            promptVersion: "",
            promptSHA256: "",
            responseSchemaVersion: "",
            requestOptions: .default,
            inputDerivativeSHA256: "",
            rawResponseText: "",
            parsedResponseJSON: nil,
            jsonValid: false,
            durationMs: 0,
            error: nil
        )
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
