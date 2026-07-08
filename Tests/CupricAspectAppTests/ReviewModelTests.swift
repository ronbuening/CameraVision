import AISidecarCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CupricAspectApp

/// M4: review verdicts, FR4-046a autosave thresholds, and recovery round
/// trips — against a session built by the real pipeline over a temp fixture.
final class ReviewModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("review-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixture

    private func writeJPEG(_ name: String, in dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let context = CGContext(
            data: nil, width: 48, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 30))
        let url = dir.appendingPathComponent(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    private func modelRun(terms: [String]) -> ModelRunRecord {
        ModelRunRecord(
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
                    .object([
                        "term": .string(term),
                        "confidence": .string("high"),
                        "evidence": .string("visible")
                    ])
                })
            ]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func makeBaseSession(terms: [String]) throws -> NormalizationSessionDocument {
        let sourceRoot = root.appendingPathComponent("source")
        let jsonRoot = root.appendingPathComponent("json")
        let source = try writeJPEG("A.JPG", in: sourceRoot)
        let scan = try ImageScanner().scan(inputPath: source.path, recursive: false, identityPolicy: .sha256)
        var sourceImage = try XCTUnwrap(scan.images.first)
        sourceImage.relativePath = "A.JPG"
        let sidecar = RawJSONSidecar(
            source: sourceImage,
            runConfiguration: .builtInDefaults,
            modelRuns: [modelRun(terms: terms)],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try FileManager.default.createDirectory(at: jsonRoot, withIntermediateDirectories: true)
        try RawJSONSidecarDocument(sidecar: sidecar).encodedData()
            .write(to: jsonRoot.appendingPathComponent("A.JPG.ai.json"))

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .observedTags
        configuration.normalizationMode = .singleImage
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = root.appendingPathComponent("artifacts").path

        return try NormalizePipeline().runSessionOnly(
            mode: .fromJSON(path: jsonRoot.path),
            configuration: configuration
        ).session
    }

    @MainActor
    private func makeModel(clock: @escaping () -> Date = Date.init, decisionLimit: Int = 25) -> ReviewModel {
        ReviewModel(
            stateDirectory: root.appendingPathComponent("state"),
            autosaveDecisionLimit: decisionLimit,
            autosaveInterval: 300,
            now: clock
        )
    }

    // MARK: - Tests

    @MainActor
    func testRowsChipsAndVerdictCounters() throws {
        let model = makeModel()
        model.adopt(session: try makeBaseSession(terms: ["bird", "tree", "water"]))

        XCTAssertEqual(model.assetRows.count, 1)
        let chips = try XCTUnwrap(model.assetRows.first?.chips)
        XCTAssertEqual(chips.count, 3)
        XCTAssertEqual(model.approvedCount, 3, "engine-accepted decisions start approved")

        model.toggle(chips[0].decisionID)
        XCTAssertEqual(model.approvedCount, 2)
        XCTAssertEqual(model.rejectedCount, 1)

        model.setVerdict(.deferred, for: chips[1].decisionID)
        XCTAssertEqual(model.deferredCount, 1)

        model.acceptAll(assetID: model.assetRows[0].assetID)
        XCTAssertEqual(model.approvedCount, 3)
    }

    @MainActor
    func testAutosaveTriggersOnDecisionLimitAndRecoveryRestores() throws {
        let model = makeModel(decisionLimit: 3)
        model.adopt(session: try makeBaseSession(terms: ["bird", "tree", "water", "rock"]))
        let chips = try XCTUnwrap(model.assetRows.first?.chips)

        model.setVerdict(.rejected, for: chips[0].decisionID)
        model.setVerdict(.rejected, for: chips[1].decisionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.recoveryURL.path), "below the limit")

        model.setVerdict(.deferred, for: chips[2].decisionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.recoveryURL.path), "third change autosaves")

        // A fresh model (relaunch) sees and restores the recovery file.
        let relaunched = makeModel()
        XCTAssertTrue(relaunched.recoveryAvailable)
        try relaunched.restoreFromRecovery()
        XCTAssertEqual(relaunched.rejectedCount, 2)
        XCTAssertEqual(relaunched.deferredCount, 1)

        relaunched.completeCleanly()
        XCTAssertFalse(FileManager.default.fileExists(atPath: relaunched.recoveryURL.path))
    }

    @MainActor
    func testRecoveryRoundTripPreservesSourceRootAndTracksUnsavedRestoredReview() throws {
        let model = makeModel(decisionLimit: 1)
        model.adopt(session: try makeBaseSession(terms: ["bird", "tree"]))
        let chips = try XCTUnwrap(model.assetRows.first?.chips)

        model.setVerdict(.rejected, for: chips[0].decisionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.recoveryURL.path))

        let relaunched = makeModel()
        try relaunched.restoreFromRecovery()
        XCTAssertEqual(
            relaunched.session?.session.sourceRoot,
            root.appendingPathComponent("source").path,
            "restored review must carry the source folder so the shell can re-enable export"
        )
        XCTAssertTrue(relaunched.restoredFromRecovery)
        XCTAssertTrue(relaunched.restoredRecoveryDirty)

        let saved = root.appendingPathComponent("saved-restored-session.json")
        try relaunched.saveSession(to: saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertFalse(relaunched.restoredRecoveryDirty)

        relaunched.setVerdict(.rejected, for: chips[1].decisionID)
        XCTAssertTrue(relaunched.restoredRecoveryDirty)
    }

    @MainActor
    func testAutosaveTriggersOnElapsedTime() throws {
        var fakeNow = Date(timeIntervalSince1970: 1_800_000_000)
        let model = makeModel(clock: { fakeNow }, decisionLimit: 100)
        model.adopt(session: try makeBaseSession(terms: ["bird", "tree"]))
        let chips = try XCTUnwrap(model.assetRows.first?.chips)

        model.setVerdict(.rejected, for: chips[0].decisionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.recoveryURL.path))

        fakeNow = fakeNow.addingTimeInterval(301)
        model.setVerdict(.rejected, for: chips[1].decisionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.recoveryURL.path), "5-minute window elapsed")
    }

    @MainActor
    func testSaveAndImportRoundTripPreservesVerdictsAndEdits() throws {
        let model = makeModel()
        model.adopt(session: try makeBaseSession(terms: ["bird", "tree"]))
        let chips = try XCTUnwrap(model.assetRows.first?.chips)
        let birdChip = try XCTUnwrap(chips.first { $0.keyword == "bird" })
        let treeChip = try XCTUnwrap(chips.first { $0.keyword == "tree" })

        model.setVerdict(.rejected, for: treeChip.decisionID)
        model.editKeyword(birdChip.decisionID, to: "Great Horned Owl")

        let saved = root.appendingPathComponent("exported-session.json")
        try model.saveSession(to: saved)

        let imported = makeModel()
        try imported.importSession(from: saved)
        XCTAssertEqual(imported.rejectedCount, 1)
        let importedChips = try XCTUnwrap(imported.assetRows.first?.chips)
        XCTAssertTrue(importedChips.contains { $0.keyword == "Great Horned Owl" })
        XCTAssertFalse(importedChips.contains { $0.keyword == "bird" })
    }

    @MainActor
    func testSaveWithNoSessionThrowsInsteadOfSilentlySucceeding() throws {
        let model = makeModel()
        XCTAssertFalse(model.canSaveSession)
        let url = root.appendingPathComponent("never-written.json")

        XCTAssertThrowsError(try model.saveSession(to: url)) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .validationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        model.adopt(session: try makeBaseSession(terms: ["bird"]))
        XCTAssertTrue(model.canSaveSession)
        model.completeCleanly()
        XCTAssertFalse(model.canSaveSession)
    }

    @MainActor
    func testEditEverywhereAppliesToMatchingKeywordsOnly() throws {
        let model = makeModel()
        model.adopt(session: try makeBaseSession(terms: ["bird", "tree"]))
        let applied = model.editEverywhere(keyword: "BIRD", to: "Owl")
        XCTAssertEqual(applied, 1)
        let chips = try XCTUnwrap(model.assetRows.first?.chips)
        XCTAssertTrue(chips.contains { $0.keyword == "Owl" })
        XCTAssertTrue(chips.contains { $0.keyword == "tree" })
    }
}
