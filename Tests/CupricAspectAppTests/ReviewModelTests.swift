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
                "proposed_keywords": .array(
                    terms.map { term in
                        .object([
                            "term": .string(term),
                            "confidence": .string("high"),
                            "evidence": .string("visible"),
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
    private func makeModel(
        clock: @escaping () -> Date = Date.init,
        decisionLimit: Int = 25,
        onAssetRowBuilt: @escaping (String) -> Void = { _ in }
    ) -> ReviewModel {
        ReviewModel(
            stateDirectory: root.appendingPathComponent("state"),
            autosaveDecisionLimit: decisionLimit,
            autosaveInterval: 300,
            now: clock,
            onAssetRowBuilt: onAssetRowBuilt
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
    func testVerdictChangeUpdatesOnlyTouchedCachedRowWithoutRebuildingRows() throws {
        var rowBuildCounts: [String: Int] = [:]
        let model = makeModel(onAssetRowBuilt: { assetID in
            rowBuildCounts[assetID, default: 0] += 1
        })
        var session = try makeBaseSession(terms: ["bird"])
        let firstAsset = try XCTUnwrap(session.sourceAssets.first)
        var secondAsset = firstAsset
        secondAsset.assetID = "asset-second"
        secondAsset.sourcePath = root.appendingPathComponent("source/B.JPG").path
        secondAsset.sourceRelativePath = "B.JPG"
        secondAsset.fileName = "B.JPG"
        session.sourceAssets.append(secondAsset)
        var secondDecision = try XCTUnwrap(session.perAssetDecisions.first)
        secondDecision.decisionID = "decision-second"
        secondDecision.assetID = secondAsset.assetID
        secondDecision.flatKeyword = "tree"
        session.perAssetDecisions.append(secondDecision)

        model.adopt(session: session)
        let initialRows = model.assetRows
        XCTAssertEqual(rowBuildCounts, [firstAsset.assetID: 1, secondAsset.assetID: 1])
        _ = model.assetRows
        _ = model.assetRows
        XCTAssertEqual(rowBuildCounts, [firstAsset.assetID: 1, secondAsset.assetID: 1])

        let firstRow = try XCTUnwrap(initialRows.first { $0.assetID == firstAsset.assetID })
        let secondRow = try XCTUnwrap(initialRows.first { $0.assetID == secondAsset.assetID })
        let decisionID = try XCTUnwrap(firstRow.chips.first?.decisionID)
        model.toggle(decisionID)

        XCTAssertEqual(rowBuildCounts, [firstAsset.assetID: 1, secondAsset.assetID: 1])
        XCTAssertEqual(model.assetRows.first { $0.assetID == secondAsset.assetID }, secondRow)
        XCTAssertEqual(
            model.assetRows.first { $0.assetID == firstAsset.assetID }?.chips.first?.verdict,
            .rejected
        )
    }

    @MainActor
    func testFirstVerdictOnWithheldDecisionAppendsChipOrCreatesRowInDecisionOrder() throws {
        var rowBuildCounts: [String: Int] = [:]
        let model = makeModel(onAssetRowBuilt: { assetID in
            rowBuildCounts[assetID, default: 0] += 1
        })
        var session = try makeBaseSession(terms: ["bird", "tree"])
        let firstAsset = try XCTUnwrap(session.sourceAssets.first)
        var withheldOnFirstAsset = try XCTUnwrap(session.perAssetDecisions.first)
        withheldOnFirstAsset.decisionID = "decision-withheld-first"
        withheldOnFirstAsset.flatKeyword = "water"
        withheldOnFirstAsset.status = .withheld
        session.perAssetDecisions.append(withheldOnFirstAsset)
        var secondAsset = firstAsset
        secondAsset.assetID = "asset-second"
        secondAsset.sourcePath = root.appendingPathComponent("source/B.JPG").path
        secondAsset.sourceRelativePath = "B.JPG"
        secondAsset.fileName = "B.JPG"
        session.sourceAssets.append(secondAsset)
        var withheldOnSecondAsset = withheldOnFirstAsset
        withheldOnSecondAsset.decisionID = "decision-withheld-second"
        withheldOnSecondAsset.assetID = secondAsset.assetID
        withheldOnSecondAsset.flatKeyword = "sky"
        session.perAssetDecisions.append(withheldOnSecondAsset)

        model.adopt(session: session)
        XCTAssertEqual(model.assetRows.map(\.assetID), [firstAsset.assetID])
        XCTAssertEqual(model.assetRows.first?.chips.count, 2)

        model.setVerdict(.rejected, for: withheldOnFirstAsset.decisionID)
        XCTAssertEqual(
            model.assetRows.first?.chips.map(\.keyword),
            ["bird", "tree", "water"],
            "a newly visible chip joins its existing row in decision order"
        )
        XCTAssertEqual(rowBuildCounts[firstAsset.assetID], 1, "appending a chip does not rebuild the row")

        model.setVerdict(.approved, for: withheldOnSecondAsset.decisionID)
        XCTAssertEqual(
            model.assetRows.map(\.assetID),
            [firstAsset.assetID, secondAsset.assetID],
            "a newly visible asset gains a sorted-in row"
        )
        XCTAssertEqual(rowBuildCounts[secondAsset.assetID], 1)
        XCTAssertEqual(model.assetRows.last?.chips.map(\.keyword), ["sky"])
        XCTAssertEqual(model.assetRows.last?.chips.first?.verdict, .approved)
    }

    @MainActor
    func testReviewBuilderUsesResolverAndMapsOnlyGUIQualityFields() throws {
        let configURL = root.appendingPathComponent("review-config.json")
        try Data(
            """
            {
              "xmp_quality_write_label": false,
              "xmp_quality_write_keywords": false,
              "xmp_quality_min_confidence": "high"
            }
            """.utf8
        ).write(to: configURL)
        let model = ReviewModel(
            stateDirectory: root.appendingPathComponent("state"),
            environment: [:],
            defaultConfigPath: configURL.path
        )
        let overrides = QualityGradingConfigurationOverrides(
            enabled: true,
            conflictPolicy: .refresh,
            writeRating: true
        )

        let configuration = try model.buildConfiguration(
            sourceRoot: "/src",
            outputDir: "/out",
            qualityGrading: overrides
        )

        XCTAssertEqual(configuration.vocabularyMode, .observedTags)
        XCTAssertEqual(configuration.normalizationMode, .singleImage)
        XCTAssertTrue(configuration.qualityGrading.enabled)
        XCTAssertEqual(configuration.qualityGrading.conflictPolicy, .refresh)
        XCTAssertTrue(configuration.qualityGrading.policy.writeRating)
        XCTAssertFalse(configuration.qualityGrading.policy.writeLabel)
        XCTAssertFalse(configuration.qualityGrading.policy.writeKeywords)
        XCTAssertEqual(configuration.qualityGrading.policy.minimumConfidence, .high)
    }

    @MainActor
    func testAbsentQualityConfigurationMatchesPinnedReviewBuilderIdentity() throws {
        let model = ReviewModel(
            stateDirectory: root.appendingPathComponent("state"),
            environment: [:],
            defaultConfigPath: root.appendingPathComponent("missing/config.json").path
        )

        let configuration = try model.buildConfiguration(
            sourceRoot: "/src",
            outputDir: "/out",
            qualityGrading: QualityGradingConfigurationOverrides()
        )
        var expected = ResolvedNormalizationConfiguration.builtInDefaults
        expected.recursive = true
        expected.outputDir = "/out"
        expected.sourceRoot = "/src"
        expected.vocabularyMode = .observedTags
        expected.normalizationMode = .singleImage

        XCTAssertEqual(configuration, expected)
    }

    func testLoadQualityExtractionReadsCurrentSidecarPairWithoutIdentityGate() throws {
        let session = try makeBaseSession(terms: ["bird"])
        let assetID = try XCTUnwrap(session.sourceAssets.first?.assetID)
        XCTAssertFalse(session.sourceAISidecars.isEmpty)
        let jsonRoot = root.appendingPathComponent("json")

        // QN6 alignment: a quality sibling added after the session was created
        // and a source image modified since analysis must both be reflected,
        // because apply-time grading consumes exactly this current-pair state.
        let tagging = try RawJSONSidecarReader().read(from: jsonRoot.appendingPathComponent("A.JPG.ai.json"))
        let quality = RawJSONSidecar(
            source: tagging.sidecar.source,
            runConfiguration: ResolvedRunConfiguration.builtInDefaults.with(taskProfile: .qualityOnly),
            modelRuns: [
                ModelRunRecord(
                    inputRole: .wholeImage,
                    model: "test:model",
                    modelDigest: "sha256:test",
                    runtime: "test",
                    runtimeVersion: "1.0",
                    promptVersion: "prompt/quality",
                    promptSHA256: String(repeating: "a", count: 64),
                    responseSchemaVersion: "schema/quality",
                    requestOptions: .default,
                    inputDerivativeSHA256: String(repeating: "b", count: 64),
                    rawResponseText: "{}",
                    parsedResponseJSON: .object([
                        "quality_assessment": .object([
                            "focus": .string("problem"),
                            "overall_effectiveness": .string("problem"),
                            "strengths": .array([]),
                            "concerns": .array([.string("focus misses the subject")]),
                            "confidence": .string("high"),
                        ])
                    ]),
                    jsonValid: true,
                    durationMs: 1,
                    error: nil
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        try RawJSONSidecarDocument(sidecar: quality).encodedData()
            .write(to: jsonRoot.appendingPathComponent("A.JPG.quality.ai.json"))
        try Data("modified after analysis".utf8).write(to: root.appendingPathComponent("source/A.JPG"))

        let loaded = ReviewModel.loadQualityExtraction(for: session)

        XCTAssertEqual(loaded.diagnostics, [])
        XCTAssertEqual(loaded.resultsByAssetID[assetID]?.records.map(\.role), [.wholeImage])
        XCTAssertEqual(loaded.resultsByAssetID[assetID]?.records.first?.overall, .problem)
        XCTAssertEqual(
            loaded.resultsByAssetID[assetID]?.records.first?.concerns,
            ["focus misses the subject"]
        )
    }

    func testLoadQualityExtractionSurfacesUnreadableSidecarAsDiagnostic() throws {
        var session = try makeBaseSession(terms: ["bird"])
        let missing = root.appendingPathComponent("json/Gone.JPG.ai.json").path
        session.sourceAISidecars[0].sidecarPath = missing

        let loaded = ReviewModel.loadQualityExtraction(for: session)

        XCTAssertTrue(loaded.resultsByAssetID.isEmpty)
        XCTAssertEqual(loaded.diagnostics.count, 1)
        XCTAssertTrue(loaded.diagnostics[0].hasPrefix(SidecarErrorCode.validationFailed.rawValue))
    }

    @MainActor
    func testAssetRowsDoesNotTrapOnDuplicateAssetIDInInMemorySession() throws {
        let model = makeModel()
        var session = try makeBaseSession(terms: ["bird"])
        session.sourceAssets.append(try XCTUnwrap(session.sourceAssets.first))

        model.adopt(session: session)

        XCTAssertEqual(model.assetRows.count, 1)
        XCTAssertEqual(model.assetRows.first?.assetID, session.sourceAssets.first?.assetID)
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
    func testAutosaveNowFlushesPendingVerdictsBelowCadenceThreshold() throws {
        let model = makeModel(decisionLimit: 25)
        model.adopt(session: try makeBaseSession(terms: ["bird", "tree"]))
        let chips = try XCTUnwrap(model.assetRows.first?.chips)

        model.setVerdict(.rejected, for: chips[0].decisionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.recoveryURL.path), "below the cadence threshold")

        model.autosaveNow()

        XCTAssertTrue(FileManager.default.fileExists(atPath: model.recoveryURL.path))
        let restored = makeModel()
        try restored.restoreFromRecovery()
        XCTAssertEqual(restored.verdicts[chips[0].decisionID], .rejected)
    }

    @MainActor
    func testTerminationFlushRunsRegisteredActions() {
        TerminationFlush._resetForTesting()
        defer { TerminationFlush._resetForTesting() }
        var flushed = false

        TerminationFlush.register(id: "test") {
            flushed = true
        }
        TerminationFlush.runAll()

        XCTAssertTrue(flushed)
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
        var session = try makeBaseSession(terms: ["bird", "tree"])
        let birdDecision = try XCTUnwrap(session.perAssetDecisions.first { $0.flatKeyword == "bird" })
        var withheldBird = birdDecision
        withheldBird.decisionID = "decision-withheld-bird"
        withheldBird.status = .withheld
        session.perAssetDecisions.append(withheldBird)

        model.adopt(session: session)
        let applied = model.editEverywhere(keyword: "BIRD", to: " Owl ")
        XCTAssertEqual(applied, 1)
        let chips = try XCTUnwrap(model.assetRows.first?.chips)
        XCTAssertTrue(chips.contains { $0.keyword == "Owl" })
        XCTAssertTrue(chips.contains { $0.keyword == "tree" })

        let reviewed = try XCTUnwrap(model.reviewedSession)
        let withheld = try XCTUnwrap(reviewed.perAssetDecisions.first { $0.decisionID == "decision-withheld-bird" })
        XCTAssertEqual(withheld.status, .withheld)
        XCTAssertEqual(withheld.flatKeyword, "bird")
    }

    @MainActor
    func testEditEverywhereMatchesCanonicalAndSourceTextFallbacks() throws {
        let model = makeModel()
        var session = try makeBaseSession(terms: ["canonical", "source"])
        session.perAssetDecisions[0].flatKeyword = nil
        session.perAssetDecisions[0].canonicalPath = "Subject|Wildlife|Birds"
        session.perAssetDecisions[0].sourceText = nil
        session.perAssetDecisions[1].flatKeyword = nil
        session.perAssetDecisions[1].canonicalPath = nil
        session.perAssetDecisions[1].sourceText = "visible sign"

        model.adopt(session: session)
        var chips = try XCTUnwrap(model.assetRows.first?.chips)
        XCTAssertTrue(chips.contains { $0.keyword == "Subject|Wildlife|Birds" })
        XCTAssertTrue(chips.contains { $0.keyword == "visible sign" })

        XCTAssertEqual(model.editEverywhere(keyword: "Subject|Wildlife|Birds", to: "Birds"), 1)
        XCTAssertEqual(model.editEverywhere(keyword: "visible sign", to: "Signage"), 1)

        chips = try XCTUnwrap(model.assetRows.first?.chips)
        XCTAssertTrue(chips.contains { $0.keyword == "Birds" && $0.originalKeyword == "Subject|Wildlife|Birds" })
        XCTAssertTrue(chips.contains { $0.keyword == "Signage" && $0.originalKeyword == "visible sign" })
    }

    @MainActor
    func testPipeBearingEditsAreRejectedAndSurfaced() throws {
        let model = makeModel()
        model.adopt(session: try makeBaseSession(terms: ["bird"]))
        let chip = try XCTUnwrap(model.assetRows.first?.chips.first)

        XCTAssertFalse(model.editKeyword(chip.decisionID, to: "Great|Egret"))
        XCTAssertEqual(
            model.editError,
            "Keyword edits must be non-empty and cannot contain '|', GPS/location metadata, or coordinate syntax."
        )
        XCTAssertTrue(model.edits.isEmpty)
        XCTAssertEqual(model.editEverywhere(keyword: "bird", to: "Birds|Herons"), 0)
        XCTAssertTrue(model.edits.isEmpty)
        XCTAssertEqual(model.assetRows.first?.chips.first?.keyword, "bird")
    }

    @MainActor
    func testCoordinateAndGPSMetadataEditsAreRejectedAndSurfaced() throws {
        let model = makeModel()
        model.adopt(session: try makeBaseSession(terms: ["bird"]))
        let chip = try XCTUnwrap(model.assetRows.first?.chips.first)

        XCTAssertFalse(model.editKeyword(chip.decisionID, to: "40, -79"))
        XCTAssertEqual(
            model.editError,
            "Keyword edits must be non-empty and cannot contain '|', GPS/location metadata, or coordinate syntax."
        )
        XCTAssertFalse(model.editKeyword(chip.decisionID, to: "GPS fix"))
        XCTAssertEqual(
            model.editError,
            "Keyword edits must be non-empty and cannot contain '|', GPS/location metadata, or coordinate syntax."
        )
        XCTAssertTrue(model.edits.isEmpty)
    }
}
