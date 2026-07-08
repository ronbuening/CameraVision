import AISidecarCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CupricAspectApp

/// M6: session-context → configuration mapping, the model-free run feeding
/// the Inspector, filters, stale-vocabulary detection, and the accepted-only
/// write path (FR4-052–054, AC4-029/030 groundwork).
final class NormalizationModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("normalization-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixture (same recipe as ReviewModelTests)

    private func writeJPEG(_ name: String, in dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let context = CGContext(
            data: nil, width: 48, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 30))
        let destination = CGImageDestinationCreateWithURL(
            dir.appendingPathComponent(name) as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
    }

    private func writeFixture(terms: [String]) throws -> (jsonRoot: String, sourceRoot: String) {
        let sourceRoot = root.appendingPathComponent("source")
        let jsonRoot = root.appendingPathComponent("json")
        try writeJPEG("A.JPG", in: sourceRoot)
        let scan = try ImageScanner().scan(
            inputPath: sourceRoot.appendingPathComponent("A.JPG").path,
            recursive: false,
            identityPolicy: .sha256
        )
        var sourceImage = try XCTUnwrap(scan.images.first)
        sourceImage.relativePath = "A.JPG"
        let run = ModelRunRecord(
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
                "proposed_keywords": .array(terms.map { term in
                    .object(["term": .string(term), "confidence": .string("high"), "evidence": .string("visible")])
                })
            ]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
        let sidecar = RawJSONSidecar(
            source: sourceImage,
            runConfiguration: .builtInDefaults,
            modelRuns: [run],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try FileManager.default.createDirectory(at: jsonRoot, withIntermediateDirectories: true)
        try RawJSONSidecarDocument(sidecar: sidecar).encodedData()
            .write(to: jsonRoot.appendingPathComponent("A.JPG.ai.json"))
        return (jsonRoot.path, sourceRoot.path)
    }

    @MainActor
    private func waitUntil(_ label: String, timeout: TimeInterval = 20, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                return XCTFail("timed out waiting for \(label)")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Tests

    @MainActor
    func testContextFieldsLandInConfiguration() {
        let model = NormalizationModel(stateDirectory: root)
        model.subject = "Leopard"
        model.habitat = "Savanna"
        model.allowSubjectPropagation = true
        model.unknownPolicy = .writeUnnormalized
        model.vocabularyPath = "/tmp/vocab.json"

        let configuration = model.buildConfiguration(sourceRoot: "/src", outputDir: "/out")
        XCTAssertEqual(configuration.sessionSubject, "Leopard")
        XCTAssertEqual(configuration.sessionHabitat, "Savanna")
        XCTAssertNil(configuration.sessionEvent, "empty fields map to nil, not empty strings")
        XCTAssertTrue(configuration.allowSessionSubjectPropagation)
        XCTAssertFalse(configuration.allowSessionHabitatPropagation)
        XCTAssertEqual(configuration.unknownSessionContextPolicy, .writeUnnormalized)
        XCTAssertEqual(configuration.vocabularyPath, "/tmp/vocab.json")
        XCTAssertEqual(configuration.sourceRoot, "/src")
    }

    @MainActor
    func testRunProducesSummariesAndFiltersWork() async throws {
        let (jsonRoot, sourceRoot) = try writeFixture(terms: ["bird", "tree"])
        let model = NormalizationModel(stateDirectory: root.appendingPathComponent("state"))

        model.run(jsonRoot: jsonRoot, sourceRoot: sourceRoot)
        try await waitUntil("normalization run") { model.phase == .ready }

        XCTAssertFalse(model.summaries.isEmpty)
        XCTAssertEqual(model.filteredSummaries.count, model.summaries.count)

        model.outcomeFilter = .accepted
        XCTAssertTrue(model.filteredSummaries.allSatisfy { $0.acceptedCount > 0 })

        model.outcomeFilter = .needsAttention
        XCTAssertEqual(
            model.filteredSummaries.map(\.keyword),
            model.summaries.filter(\.needsAttention).map(\.keyword)
        )

        model.outcomeFilter = .all
        model.stageFilter = .userSessionContext
        XCTAssertTrue(model.filteredSummaries.isEmpty, "no user context was supplied")
    }

    @MainActor
    func testRunFailureCarriesThrownErrorMessageInPhase() async throws {
        let (_, sourceRoot) = try writeFixture(terms: ["bird"])
        let missingJSONRoot = root.appendingPathComponent("missing-json").path
        let model = NormalizationModel(stateDirectory: root.appendingPathComponent("state"))

        model.run(jsonRoot: missingJSONRoot, sourceRoot: sourceRoot)
        try await waitUntil("normalization failure") {
            if case .failed = model.phase { return true }
            return false
        }

        guard case .failed(let message) = model.phase else {
            return XCTFail("expected failed phase, got \(model.phase)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(
            message.contains("missing-json") || message.localizedCaseInsensitiveContains("does not exist"),
            "message should name the failing input: \(message)"
        )
    }

    @MainActor
    func testStaleVocabularyDetection() async throws {
        let (jsonRoot, sourceRoot) = try writeFixture(terms: ["bird"])
        let model = NormalizationModel(stateDirectory: root.appendingPathComponent("state"))

        model.run(jsonRoot: jsonRoot, sourceRoot: sourceRoot)
        try await waitUntil("normalization run") { model.phase == .ready }
        XCTAssertFalse(model.vocabularyIsStale, "no explicit vocabulary file — never stale")

        // Point at a file whose bytes cannot match the session's vocabulary
        // hash: the indicator must flag the mismatch (FR4-054).
        let vocabFile = root.appendingPathComponent("changed-vocab.json")
        try Data("{}".utf8).write(to: vocabFile)
        model.vocabularyPath = vocabFile.path
        XCTAssertTrue(model.vocabularyIsStale)
    }

    @MainActor
    func testSaveWithNoSessionThrowsInsteadOfSilentlySucceeding() async throws {
        let model = NormalizationModel(stateDirectory: root.appendingPathComponent("state"))
        XCTAssertFalse(model.canSaveSession)
        let url = root.appendingPathComponent("never-written-normalization.json")

        XCTAssertThrowsError(try model.saveSession(to: url)) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .validationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let (jsonRoot, sourceRoot) = try writeFixture(terms: ["bird"])
        model.run(jsonRoot: jsonRoot, sourceRoot: sourceRoot)
        try await waitUntil("normalization run") { model.phase == .ready }
        XCTAssertTrue(model.canSaveSession)

        model.reset()
        XCTAssertFalse(model.canSaveSession)
    }

    @MainActor
    func testWriteNormalizedXMPProducesSidecarsFromAcceptedSet() async throws {
        let (jsonRoot, sourceRoot) = try writeFixture(terms: ["bird", "tree"])
        let model = NormalizationModel(stateDirectory: root.appendingPathComponent("state"))

        model.run(jsonRoot: jsonRoot, sourceRoot: sourceRoot)
        try await waitUntil("normalization run") { model.phase == .ready }

        let xmpOut = root.appendingPathComponent("xmp-out").path
        model.writeNormalizedXMP(sourceRoot: sourceRoot, outputDir: xmpOut)
        try await waitUntil("XMP write") {
            if case .written = model.phase { return true }
            if case .failed = model.phase { return true }
            return false
        }

        guard case .written(let targets, _) = model.phase else {
            return XCTFail("write failed: \(model.phase)")
        }
        XCTAssertEqual(targets, 1)
        let xmpFiles = try FileManager.default.contentsOfDirectory(atPath: xmpOut)
            .filter { $0.hasSuffix(".xmp") }
        XCTAssertEqual(xmpFiles.count, 1)
    }
}
