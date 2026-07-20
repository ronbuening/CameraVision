import CryptoKit
import Foundation
import XCTest

@testable import AISidecarCore

final class NormalizeQualityDefaultOffIdentityTests: XCTestCase {
    func testDefaultOffRunMatchesPreQN3ArtifactHashes() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let jsonRoot = root.appendingPathComponent("json")
        let sourceRoot = root.appendingPathComponent("source")
        let outputRoot = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        let sourceURL = try writeTestImage("Bird.JPG", in: sourceRoot)
        let sourceModifiedAt = Date(timeIntervalSince1970: 1_700_000_100)
        try FileManager.default.setAttributes([.modificationDate: sourceModifiedAt], ofItemAtPath: sourceURL.path)
        var source = try XCTUnwrap(
            ImageScanner().scan(inputPath: sourceURL.path, recursive: false, identityPolicy: .sha256).images.first
        )
        source.relativePath = "Bird.JPG"

        try FileManager.default.createDirectory(at: jsonRoot, withIntermediateDirectories: true)
        let taggingSidecar = jsonRoot.appendingPathComponent("Bird.JPG.ai.json")
        let sidecar = RawJSONSidecar(
            source: source,
            runConfiguration: Self.fixtureRunConfiguration(),
            modelRuns: [taggingRun()],
            createdAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        try RawJSONSidecarDocument(sidecar: sidecar).encodedData().write(to: taggingSidecar)

        let vocabularyPath = root.appendingPathComponent("vocabulary.json")
        try vocabularyData(entries: minimalVocabularyEntries()).write(to: vocabularyPath)

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .controlledVocabulary
        configuration.vocabularyPath = vocabularyPath.path
        configuration.normalizationMode = .singleImage
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = outputRoot.path
        configuration.backupSidecars = false
        configuration.xmpConflictPolicy = .merge
        configuration.qualityGrading = .builtInDefaults

        let normalizationTimestamp = Date(timeIntervalSince1970: 1_800_000_100)
        let normalizeResult = try NormalizePipeline().runWritePlan(
            mode: .fromJSON(path: jsonRoot.path),
            configuration: configuration,
            timestamp: normalizationTimestamp,
            sessionID: "qn3-default-off-baseline"
        )
        let changePlan = try XCTUnwrap(normalizeResult.changePlan)
        let exportTimestamp = Date(timeIntervalSince1970: 1_800_000_200)
        let exportResult = try XMPExportPipeline(
            logger: Logger(sink: { _ in }),
            now: { exportTimestamp },
            filenameSuffix: { "qn3-baseline" }
        ).runChangePlan(
            changePlan,
            inputPath: jsonRoot.path,
            configuration: xmpConfiguration(from: configuration)
        )
        let finalResult = try NormalizationXMPExecutionRecorder().recordExecution(
            normalizeResult: normalizeResult,
            exportResult: exportResult,
            progressMessage: "Normalize XMP target processed."
        )

        let sessionPath = try XCTUnwrap(finalResult.session.artifacts.sessionPath)
        let sessionName = URL(fileURLWithPath: sessionPath).deletingPathExtension().lastPathComponent
        let tokenPrefix = Timestamp.filenameSafe(normalizationTimestamp) + "-"
        let tokenRange = try XCTUnwrap(sessionName.range(of: tokenPrefix))
        let runToken = String(sessionName[tokenRange.lowerBound...])
        let artifacts = [
            "progress": finalResult.report.artifacts.progressPath,
            "raw_sidecar": taggingSidecar.path,
            "report": finalResult.report.artifacts.reportPath,
            "session": sessionPath,
            "summary": finalResult.report.artifacts.summaryPath,
            "xmp": outputRoot.appendingPathComponent("Bird.xmp").path,
        ]
        var actual: [String: String] = [:]
        for (key, path) in artifacts {
            actual[key] = try sha256(normalizedData(at: path, root: root, runToken: runToken))
        }

        XCTAssertEqual(actual, try baselineHashes())
    }

    /// `builtInDefaults` embeds machine-specific values — a home-based
    /// derivative cache path and a CPU-count stage concurrency — so a fixture
    /// sidecar built from it hashes differently on every machine. Pin both so
    /// the byte-identity baseline holds on CI and locally alike.
    static func fixtureRunConfiguration() -> ResolvedRunConfiguration {
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.derivativeCacheDir = "/fixture/derivative-cache"
        configuration.stageConcurrency = 2
        return configuration
    }

    private func taggingRun() -> ModelRunRecord {
        ModelRunRecord(
            inputRole: .wholeImage,
            model: "test:model",
            modelDigest: "sha256:testdigest",
            runtime: "test-runtime",
            runtimeVersion: "1.0",
            promptVersion: "prompt/1",
            promptSHA256: String(repeating: "a", count: 64),
            responseSchemaVersion: "schema/1",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "b", count: 64),
            rawResponseText: "{}",
            parsedResponseJSON: .object([
                "summary": .string("fixture"),
                "uncertainty_notes": .string(""),
                "main_subjects": .array([
                    .object([
                        "term": .string("bird"),
                        "confidence": .string("high"),
                        "evidence": .string("visible evidence"),
                    ])
                ]),
            ]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func xmpConfiguration(
        from configuration: ResolvedNormalizationConfiguration
    ) -> ResolvedXMPExportConfiguration {
        ResolvedXMPExportConfiguration(
            recursive: configuration.recursive,
            outputDir: configuration.outputDir,
            logLevel: configuration.logLevel,
            logFormat: configuration.logFormat,
            dryRun: configuration.dryRun,
            sourceRoot: configuration.sourceRoot,
            sourceVerification: configuration.sourceVerification,
            writeFlatKeywords: configuration.writeFlatKeywords,
            writeHierarchicalKeywords: configuration.writeHierarchicalKeywords,
            backupSidecars: configuration.backupSidecars,
            xmpConflictPolicy: configuration.xmpConflictPolicy,
            minConfidence: configuration.minConfidence,
            allowSpecificTags: configuration.allowSpecificTags,
            pairScope: configuration.pairScope,
            writeAIJSON: configuration.writeAIJSON,
            qualityGrading: configuration.qualityGrading
        )
    }

    private func normalizedData(at path: String, root: URL, runToken: String) throws -> Data {
        var text = String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
        // The baseline was generated at QN2 commit 5ea2b9a. Normalize only the
        // temporary root and planner's random four-hex token before byte hashing.
        // raw_sidecar re-pinned 2026-07-19 after fixing the fixture's
        // machine-specific run configuration (cache dir, concurrency); the
        // pipeline-produced artifact hashes were unchanged by that fix.
        text = text.replacingOccurrences(of: root.standardizedFileURL.path, with: "$ROOT")
        text = text.replacingOccurrences(of: runToken, with: "$RUN_TOKEN")
        return Data(text.utf8)
    }

    private func baselineHashes() throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "qn3-default-off-artifact-sha256",
                withExtension: "json",
                subdirectory: "normalization"
            )
                ?? Bundle.module.url(forResource: "qn3-default-off-artifact-sha256", withExtension: "json")
        )
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
