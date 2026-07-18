import Foundation
import XCTest

@testable import AISidecarCore

final class NormalizeAndWritePipelineTests: XCTestCase {
    func testFromJSONNormalWriteCreatesNormalizationArtifactsAndXMP() throws {
        let jsonRoot = try temporaryDirectory()
        let sourceRoot = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: jsonRoot)
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: vocabularyPath).deletingLastPathComponent())
        }
        let image = try writeTestImage("Bird.JPG", in: sourceRoot)
        let source = try scannedSourceImage(image, relativePath: "Bird.JPG")
        _ = try writeRawSidecar(source: source, named: "Bird.JPG.ai.json", in: jsonRoot)

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .controlledVocabulary
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = output.path
        configuration.vocabularyPath = vocabularyPath
        configuration.normalizationMode = .singleImage

        let result = try NormalizeAndWritePipeline(logger: Logger(sink: { _ in })).run(
            mode: .fromJSON(path: jsonRoot.path),
            configuration: configuration
        )

        let sessionPath = try XCTUnwrap(result.normalizeResult.session.artifacts.sessionPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.normalizeResult.report.artifacts.reportPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.normalizeResult.report.artifacts.summaryPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.normalizeResult.report.artifacts.progressPath))
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: output.appendingPathComponent("Bird.xmp").path)
        XCTAssertEqual(snapshot.flatKeywords, ["Birds"])
        XCTAssertEqual(snapshot.hierarchicalKeywords, ["Subject|Wildlife|Birds"])
        XCTAssertEqual(result.normalizeResult.report.workflow, .fromJSON)
        XCTAssertEqual(result.normalizeResult.report.xmpExportReport?.writtenCount, 1)
        XCTAssertEqual(result.normalizeResult.report.xmpExportReport?.targetReports.first?.status, .created)
        XCTAssertEqual(result.normalizeResult.report.errors, [])
        XCTAssertTrue(
            try decodeProgress(at: result.normalizeResult.report.artifacts.progressPath).contains {
                $0.stage == .xmpTarget
                    && $0.status == .completed
                    && $0.targetRelativePath == "Bird.xmp"
            })
    }

    func testNormalizeAndWriteCarriesQualityGradingIntoExportConfiguration() throws {
        var fixture = try makeFixture()
        let grading = ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: .refresh,
            policy: QualityGradingPolicy(
                writeFlag: false,
                keywordRoot: "Review Quality",
                ratingMap: [.good: 4]
            )
        )
        fixture.configuration.qualityGrading = grading

        let result = try NormalizeAndWritePipeline(logger: Logger(sink: { _ in })).run(
            mode: .fromJSON(path: fixture.jsonRoot.path),
            configuration: fixture.configuration
        )

        XCTAssertEqual(result.exportResult.report?.configuration.qualityGrading, grading)
    }

    func testInterruptedBeforeSessionWriteLeavesNoNormalizationArtifacts() throws {
        let fixture = try makeFixture()
        let monitor = InterruptionMonitor()
        monitor.requestInterruption()

        XCTAssertThrowsError(
            try NormalizePipeline().runSessionOnly(
                mode: .fromJSON(path: fixture.jsonRoot.path),
                configuration: fixture.configuration,
                interruptionMonitor: monitor
            )
        ) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .interrupted)
        }

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.output.path).isEmpty)
    }

    func testInterruptedAfterSessionWriteBeforeXMPWriteRecordsFailureWithoutSidecar() throws {
        let fixture = try makeFixture()
        let monitor = InterruptionMonitor()
        let result = try NormalizeAndWritePipeline(
            logger: Logger(sink: { _ in }),
            afterNormalization: { monitor.requestInterruption() }
        ).run(
            mode: .fromJSON(path: fixture.jsonRoot.path),
            configuration: fixture.configuration,
            interruptionMonitor: monitor
        )

        XCTAssertTrue(result.exportResult.interrupted)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: try XCTUnwrap(result.normalizeResult.session.artifacts.sessionPath)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("Bird.xmp").path))
        XCTAssertEqual(result.normalizeResult.report.errors.map(\.code), [.interrupted])
        XCTAssertEqual(result.normalizeResult.report.xmpExportReport?.inputFailures.map(\.error.code), [.interrupted])
        XCTAssertTrue(
            try decodeProgress(at: result.normalizeResult.report.artifacts.progressPath).contains {
                $0.stage == .xmpTarget
                    && $0.status == .failed
                    && $0.errors.map(\.code) == [.interrupted]
            })
    }

    func testInterruptedDuringXMPBackupRestoresExistingSidecarAndLeavesSourceUnchanged() throws {
        let fixture = try makeFixture(existingXMP: existingDevelopSettingsXMPForNormalizeWrite)
        let originalSourceData = try Data(contentsOf: fixture.sourceURL)
        let monitor = InterruptionMonitor()
        let result = try NormalizeAndWritePipeline(
            exportPipeline: XMPExportPipeline(
                logger: Logger(sink: { _ in }),
                afterBackup: { monitor.requestInterruption() }
            )
        ).run(
            mode: .fromJSON(path: fixture.jsonRoot.path),
            configuration: fixture.configuration,
            interruptionMonitor: monitor
        )

        let targetReport = try XCTUnwrap(result.normalizeResult.report.xmpExportReport?.targetReports.first)
        XCTAssertTrue(result.exportResult.interrupted)
        XCTAssertEqual(targetReport.status, .interrupted)
        XCTAssertNotNil(targetReport.backup?.restoredAt)
        XCTAssertEqual(
            try String(contentsOf: fixture.output.appendingPathComponent("Bird.xmp"), encoding: .utf8),
            existingDevelopSettingsXMPForNormalizeWrite
        )
        XCTAssertEqual(try Data(contentsOf: fixture.sourceURL), originalSourceData)
    }

    private func makeFixture(existingXMP: String? = nil) throws -> NormalizeWriteFixture {
        let jsonRoot = try temporaryDirectory()
        let sourceRoot = try temporaryDirectory()
        let output = try temporaryDirectory()
        let vocabularyPath = try writeVocabulary()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: jsonRoot)
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: vocabularyPath).deletingLastPathComponent())
        }
        let image = try writeTestImage("Bird.JPG", in: sourceRoot)
        let source = try scannedSourceImage(image, relativePath: "Bird.JPG")
        _ = try writeRawSidecar(source: source, named: "Bird.JPG.ai.json", in: jsonRoot)
        if let existingXMP {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try existingXMP.write(to: output.appendingPathComponent("Bird.xmp"), atomically: true, encoding: .utf8)
        }

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .controlledVocabulary
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = output.path
        configuration.vocabularyPath = vocabularyPath
        configuration.normalizationMode = .singleImage

        return NormalizeWriteFixture(
            jsonRoot: jsonRoot,
            sourceRoot: sourceRoot,
            output: output,
            sourceURL: image,
            configuration: configuration
        )
    }

    private func scannedSourceImage(_ url: URL, relativePath: String) throws -> SourceImage {
        let scan = try ImageScanner().scan(inputPath: url.path, recursive: false, identityPolicy: .sha256)
        var source = try XCTUnwrap(scan.images.first)
        source.relativePath = relativePath
        return source
    }

    private func writeRawSidecar(source: SourceImage, named relativePath: String, in root: URL) throws -> URL {
        let destination = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sidecar = RawJSONSidecar(
            source: source,
            runConfiguration: .builtInDefaults,
            modelRuns: [
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
                    parsedResponseJSON: Self.response([
                        "main_subjects": .array([Self.candidate("bird", confidence: "high")])
                    ]),
                    jsonValid: true,
                    durationMs: 1,
                    error: nil
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try RawJSONSidecarDocument(sidecar: sidecar).encodedData().write(to: destination)
        return destination
    }

    private func writeVocabulary() throws -> String {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("vocabulary.json")
        try vocabularyData(entries: minimalVocabularyEntries()).write(to: file)
        return file.path
    }

    private func decodeProgress(at path: String) throws -> [NormalizationProgressRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let text = String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
        return
            try text
            .split(separator: "\n")
            .map { try decoder.decode(NormalizationProgressRecord.self, from: Data($0.utf8)) }
    }

    private static func response(_ fields: [String: JSONValue]) -> JSONValue {
        var object: [String: JSONValue] = [
            "summary": .string("fixture"),
            "uncertainty_notes": .string(""),
        ]
        for (field, value) in fields {
            object[field] = value
        }
        return .object(object)
    }

    private static func candidate(_ term: String, confidence: String) -> JSONValue {
        .object([
            "term": .string(term),
            "confidence": .string(confidence),
            "evidence": .string("visible evidence"),
        ])
    }
}

private struct NormalizeWriteFixture {
    var jsonRoot: URL
    var sourceRoot: URL
    var output: URL
    var sourceURL: URL
    var configuration: ResolvedNormalizationConfiguration
}

private let existingDevelopSettingsXMPForNormalizeWrite = """
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
        </rdf:Description>
      </rdf:RDF>
    </x:xmpmeta>
    """
