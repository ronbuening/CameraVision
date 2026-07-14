import XCTest

@testable import AISidecarCore

/// CORE-6: every normalization enum case has explainer text, and the
/// per-keyword rollup agrees with a session produced by the real pipeline.
final class NormalizationExplainerTests: XCTestCase {
    // MARK: - Exhaustive, distinct enum text

    func testEveryStageHasDistinctText() {
        let texts = NormalizationDecisionStage.allCases.map(NormalizationDecisionExplainer.text(for:))
        XCTAssertEqual(texts.count, 5)
        XCTAssertEqual(Set(texts).count, texts.count)
        XCTAssertTrue(texts.allSatisfy { !$0.isEmpty })
    }

    func testEveryStatusHasDistinctText() {
        let texts = NormalizationDecisionStatus.allCases.map(NormalizationDecisionExplainer.text(for:))
        XCTAssertEqual(texts.count, 3)
        XCTAssertEqual(Set(texts).count, texts.count)
    }

    func testEveryCandidateKindHasDistinctText() {
        let texts = NormalizedCandidateKind.allCases.map(NormalizationDecisionExplainer.text(for:))
        XCTAssertEqual(Set(texts).count, texts.count)
        XCTAssertTrue(texts.allSatisfy { !$0.isEmpty })
    }

    func testEverySkipReasonHasDistinctText() {
        let texts = NormalizationCandidateSkipReason.allCases.map(NormalizationDecisionExplainer.text(for:))
        XCTAssertEqual(Set(texts).count, texts.count)
        XCTAssertTrue(texts.allSatisfy { !$0.isEmpty })
    }

    // MARK: - Rollup against a real pipeline session

    private func makeSession() throws -> NormalizationSessionDocument {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let jsonRoot = root.appendingPathComponent("json")
        let sourceRoot = root.appendingPathComponent("source")

        for (name, terms) in [("A.JPG", ["bird", "tree"]), ("B.JPG", ["bird"])] {
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
            let destination = jsonRoot.appendingPathComponent("\(name).ai.json")
            try FileManager.default.createDirectory(at: jsonRoot, withIntermediateDirectories: true)
            try RawJSONSidecarDocument(sidecar: sidecar).encodedData().write(to: destination)
        }

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .observedTags
        configuration.normalizationMode = .off
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = root.appendingPathComponent("out").path

        let result = try NormalizePipeline().runSessionOnly(
            mode: .fromJSON(path: jsonRoot.path),
            configuration: configuration,
            timestamp: Date(timeIntervalSince1970: 1_800_000_400),
            sessionID: "explainer-fixture"
        )
        return try XCTUnwrap(result.session)
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
                        "evidence": .string("visible in frame"),
                    ])
                ])
            ]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    func testRollupGroupsAcrossAssetsAndFindsKeyword() throws {
        let session = try makeSession()
        let summaries = NormalizationDecisionExplainer.summaries(for: session)
        XCTAssertFalse(summaries.isEmpty)

        let bird = try XCTUnwrap(NormalizationDecisionExplainer.summary(for: "bird", in: session))
        XCTAssertEqual(bird.assetDetails.count, 2, "'bird' appears on both assets")
        XCTAssertEqual(bird.acceptedCount + bird.withheldCount + bird.skippedCount, 2)
        // normalization-mode `off` records decisions via the Phase 2 fallback stage
        XCTAssertEqual(bird.stages, [.phase2Fallback])

        let tree = try XCTUnwrap(NormalizationDecisionExplainer.summary(for: "TREE", in: session), "folded lookup")
        XCTAssertEqual(tree.assetDetails.count, 1)

        let lines = NormalizationDecisionExplainer.renderLines(bird, verbose: true)
        XCTAssertTrue(lines.first?.contains("bird") == true)
        XCTAssertTrue(lines.contains { $0.contains("outcome:") })
        XCTAssertTrue(lines.contains { $0.contains("carried over as an unreviewed fallback tag") })
    }

    func testRollupCountsDistinctAssetsWhenOneAssetHasMachineAndUserContextDecisions() throws {
        var session = try makeSession()
        let index = try XCTUnwrap(session.perAssetDecisions.firstIndex { $0.flatKeyword == "bird" })
        session.perAssetDecisions[index].status = .withheld
        var userContext = session.perAssetDecisions[index]
        userContext.decisionID = "decision-999999"
        userContext.stage = .userSessionContext
        userContext.status = .accepted
        session.perAssetDecisions.append(userContext)

        let bird = try XCTUnwrap(NormalizationDecisionExplainer.summary(for: "bird", in: session))

        XCTAssertEqual(bird.assetDetails.count, 3)
        XCTAssertEqual(bird.assetCount, 2)
        XCTAssertEqual(Set(bird.assetDetails.map(\.decisionID)).count, 3)
        XCTAssertEqual(bird.acceptedCount, 2)
        XCTAssertEqual(bird.withheldCount, 1)
        let repeatedAssetIDs = bird.assetDetails
            .filter { $0.assetID == session.perAssetDecisions[index].assetID }
            .map(\.decisionID)
        XCTAssertEqual(repeatedAssetIDs, repeatedAssetIDs.sorted())
    }

    func testNeedsAttentionFilterMatchesSummaryFlags() throws {
        let session = try makeSession()
        let flagged = NormalizationDecisionExplainer.needsAttention(in: session)
        let all = NormalizationDecisionExplainer.summaries(for: session)
        XCTAssertEqual(flagged.map(\.keyword), all.filter(\.needsAttention).map(\.keyword))
    }
}
