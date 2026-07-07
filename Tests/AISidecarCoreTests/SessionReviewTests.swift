import XCTest
@testable import AISidecarCore

/// CORE-7 (M4): review verdicts stored in the session document, and the
/// apply-session guarantee that only the approved set is written (AC4-013).
final class SessionReviewTests: XCTestCase {
    private func makeSession(terms: [String], assets: [String] = ["A.JPG"]) throws -> (session: NormalizationSessionDocument, root: URL, sourceRoot: URL) {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let jsonRoot = root.appendingPathComponent("json")
        let sourceRoot = root.appendingPathComponent("source")

        for name in assets {
            let source = try writeTestImage(name, in: sourceRoot)
            let scan = try ImageScanner().scan(inputPath: source.path, recursive: false, identityPolicy: .sha256)
            var sourceImage = try XCTUnwrap(scan.images.first)
            sourceImage.relativePath = name
            let sidecar = RawJSONSidecar(
                source: sourceImage,
                runConfiguration: .builtInDefaults,
                modelRuns: terms.map(modelRun(term:)),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            try FileManager.default.createDirectory(at: jsonRoot, withIntermediateDirectories: true)
            try RawJSONSidecarDocument(sidecar: sidecar).encodedData()
                .write(to: jsonRoot.appendingPathComponent("\(name).ai.json"))
        }

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .observedTags
        configuration.normalizationMode = .singleImage
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = root.appendingPathComponent("out").path

        let result = try NormalizePipeline().runSessionOnly(
            mode: .fromJSON(path: jsonRoot.path),
            configuration: configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_400),
            sessionID: "review-fixture"
        )
        return (try XCTUnwrap(result.session), root, sourceRoot)
    }

    private func modelRun(term: String) -> ModelRunRecord {
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
                "proposed_keywords": .array([
                    .object([
                        "term": .string(term),
                        "confidence": .string("high"),
                        "evidence": .string("visible")
                    ])
                ])
            ]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private func acceptedDecision(for term: String, in session: NormalizationSessionDocument) throws -> PerAssetNormalizationDecision {
        try XCTUnwrap(session.perAssetDecisions.first {
            ($0.flatKeyword ?? "").lowercased() == term && $0.status == .accepted
        })
    }

    func testVerdictsApplyAndRoundTripThroughTheDocument() throws {
        let (session, root, _) = try makeSession(terms: ["bird", "tree", "water"])
        _ = root
        let bird = try acceptedDecision(for: "bird", in: session)
        let tree = try acceptedDecision(for: "tree", in: session)

        let reviewed = SessionReview.applying(
            verdicts: [bird.decisionID: .rejected, tree.decisionID: .deferred],
            to: session
        )

        let rejected = try XCTUnwrap(reviewed.perAssetDecisions.first { $0.decisionID == bird.decisionID })
        XCTAssertEqual(rejected.status, .withheld)
        XCTAssertTrue(rejected.skipReasons.contains(.userReviewRejected))

        let deferred = try XCTUnwrap(reviewed.perAssetDecisions.first { $0.decisionID == tree.decisionID })
        XCTAssertEqual(deferred.status, .withheld)
        XCTAssertTrue(deferred.skipReasons.contains(.userReviewDeferred))

        let verdicts = SessionReview.verdicts(in: reviewed)
        XCTAssertEqual(verdicts[bird.decisionID], .rejected)
        XCTAssertEqual(verdicts[tree.decisionID], .deferred)

        // Re-approving clears the review reasons.
        let reApproved = SessionReview.applying(verdicts: [bird.decisionID: .approved], to: reviewed)
        let restored = try XCTUnwrap(reApproved.perAssetDecisions.first { $0.decisionID == bird.decisionID })
        XCTAssertEqual(restored.status, .accepted)
        XCTAssertFalse(restored.skipReasons.contains(.userReviewRejected))
    }

    func testEditReplacesKeywordAndPreservesOriginal() throws {
        let (session, _, _) = try makeSession(terms: ["bird"])
        let bird = try acceptedDecision(for: "bird", in: session)

        let reviewed = SessionReview.applying(
            verdicts: [bird.decisionID: .approved],
            edits: [bird.decisionID: "Great Horned Owl"],
            to: session
        )

        let edited = try XCTUnwrap(reviewed.perAssetDecisions.first { $0.decisionID == bird.decisionID })
        XCTAssertEqual(edited.flatKeyword, "Great Horned Owl")
        XCTAssertEqual(edited.candidateKind, .userEdited)
        XCTAssertEqual(edited.sourceText, "bird")
        XCTAssertNil(edited.hierarchicalKeyword)
        XCTAssertEqual(SessionReview.edits(in: reviewed)[bird.decisionID], "Great Horned Owl")
    }

    func testReviewedSessionSurvivesWriterReaderRoundTrip() throws {
        let (session, root, _) = try makeSession(terms: ["bird", "tree"])
        let bird = try acceptedDecision(for: "bird", in: session)
        let reviewed = SessionReview.applying(verdicts: [bird.decisionID: .rejected], to: session)

        let path = root.appendingPathComponent("reviewed-session.json").path
        try NormalizationSessionWriter().write(reviewed, to: path)
        let reloaded = try NormalizationSessionReader().read(from: path)

        XCTAssertEqual(SessionReview.verdicts(in: reloaded)[bird.decisionID], .rejected)
        XCTAssertEqual(reloaded.perAssetDecisions, reviewed.perAssetDecisions)
    }

    func testApplySessionWritesOnlyApprovedKeywords() throws {
        let (session, root, sourceRoot) = try makeSession(terms: ["bird", "tree"])
        let bird = try acceptedDecision(for: "bird", in: session)
        let reviewed = SessionReview.applying(verdicts: [bird.decisionID: .rejected], to: session)

        let sessionPath = root.appendingPathComponent("reviewed-session.json").path
        try NormalizationSessionWriter().write(reviewed, to: sessionPath)

        var applyConfiguration = ResolvedApplySessionConfiguration.builtInDefaults
        applyConfiguration.sourceRoot = sourceRoot.path
        applyConfiguration.outputDir = root.appendingPathComponent("xmp-out").path
        applyConfiguration.dryRun = false

        let result = try ApplySessionPipeline(
            xmpPipeline: XMPExportPipeline(logger: Logger(sink: { _ in }))
        ).run(
            sessionPath: sessionPath,
            configuration: applyConfiguration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_900)
        )
        XCTAssertTrue(result.report.errors.isEmpty)

        let xmpFiles = try FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent("xmp-out").path
        ).filter { $0.hasSuffix(".xmp") }
        XCTAssertEqual(xmpFiles.count, 1)
        let xmpText = try String(
            contentsOf: root.appendingPathComponent("xmp-out").appendingPathComponent(xmpFiles[0]),
            encoding: .utf8
        )
        XCTAssertTrue(xmpText.contains("tree"), "approved keyword is written")
        XCTAssertFalse(xmpText.contains("bird"), "review-rejected keyword is never written (AC4-013)")
    }

    // MARK: - CORE-4: xmp_export stamp (FR4-049, AC4-028)

    func testSuccessfulExportStampsContributingRawSidecars() throws {
        let (session, root, sourceRoot) = try makeSession(terms: ["bird"])
        let sessionPath = root.appendingPathComponent("session.json").path
        try NormalizationSessionWriter().write(session, to: sessionPath)
        let rawSidecarPath = root.appendingPathComponent("json").appendingPathComponent("A.JPG.ai.json").path

        var applyConfiguration = ResolvedApplySessionConfiguration.builtInDefaults
        applyConfiguration.sourceRoot = sourceRoot.path
        applyConfiguration.outputDir = root.appendingPathComponent("xmp-out").path

        // Dry run first: no stamp may appear.
        applyConfiguration.dryRun = true
        _ = try ApplySessionPipeline(
            xmpPipeline: XMPExportPipeline(logger: Logger(sink: { _ in }))
        ).run(sessionPath: sessionPath, configuration: applyConfiguration)
        XCTAssertFalse(RawSidecarExportStamp.isStamped(sidecarPath: rawSidecarPath), "dry run never stamps")

        // Real write: the contributing raw sidecar gains the block.
        applyConfiguration.dryRun = false
        _ = try ApplySessionPipeline(
            xmpPipeline: XMPExportPipeline(logger: Logger(sink: { _ in }))
        ).run(sessionPath: sessionPath, configuration: applyConfiguration)
        XCTAssertTrue(RawSidecarExportStamp.isStamped(sidecarPath: rawSidecarPath))

        let data = try Data(contentsOf: URL(fileURLWithPath: rawSidecarPath))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let block = try XCTUnwrap(object["xmp_export"] as? [String: Any])
        let targetPath = try XCTUnwrap(block["target_xmp_path"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetPath))
        XCTAssertEqual(block["writer_recipe_version"] as? String, OwnedXMPSidecarEngine.writerRecipeVersion)
        XCTAssertNotNil(block["xmp_sha256"] as? String)
        XCTAssertNotNil(block["exported_at"] as? String)

        // The stamped sidecar still decodes as a raw sidecar (additive, PW-011).
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertNoThrow(try decoder.decode(RawJSONSidecar.self, from: data))
    }
}
