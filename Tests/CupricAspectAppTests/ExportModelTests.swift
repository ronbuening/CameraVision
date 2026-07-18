import AISidecarCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import CupricAspectApp

/// M7: the dry-run-first export surface (FR4-029) and the full AC4-028 loop —
/// after a real write the M1 queue derivation reports `exported`.
final class ExportModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

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

    private func makeRawSidecarSource(terms: [String] = ["bird"]) throws -> URL {
        let sourceRoot = root.appendingPathComponent("source")
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
                "proposed_keywords": .array(
                    terms.map { term in
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
        // Raw sidecar beside the source, exactly like a beside-source analyze.
        try RawJSONSidecarDocument(sidecar: sidecar).encodedData()
            .write(to: sourceRoot.appendingPathComponent("A.JPG.ai.json"))
        return sourceRoot
    }

    private func makeSession(terms: [String] = ["bird"]) throws -> (
        session: NormalizationSessionDocument, sourceRoot: URL
    ) {
        let sourceRoot = try makeRawSidecarSource(terms: terms)
        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.vocabularyMode = .observedTags
        configuration.normalizationMode = .singleImage
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot.path
        configuration.outputDir = root.appendingPathComponent("artifacts").path

        let result = try NormalizePipeline().runSessionOnly(
            mode: .fromJSON(path: sourceRoot.path),
            configuration: configuration
        )
        return (result.session, sourceRoot)
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

    @MainActor
    func testPlanThenWriteFlipsQueueDerivationToExported() async throws {
        let (session, sourceRoot) = try makeSession()
        let sourcePath = sourceRoot.appendingPathComponent("A.JPG").path

        // Before export: analyzed (sidecar present, no stamp, no XMP).
        XCTAssertEqual(
            AssetQueueDerivation.deriveState(sourcePath: sourcePath, relativePath: "A.JPG", outputDir: nil),
            .analyzed
        )

        let export = ExportModel(stateDirectory: root.appendingPathComponent("state"))
        export.plan(session: session, sourceRoot: sourceRoot.path, outputDir: nil)
        try await waitUntil("dry-run plan") { export.phase == .planReady }

        XCTAssertEqual(export.writableTargets.count, 1)
        XCTAssertTrue(export.failedTargets.isEmpty)
        // The dry run wrote nothing.
        XCTAssertEqual(
            AssetQueueDerivation.deriveState(sourcePath: sourcePath, relativePath: "A.JPG", outputDir: nil),
            .analyzed
        )

        export.confirmWrite()
        try await waitUntil("write") {
            if case .written = export.phase { return true }
            if case .failed = export.phase { return true }
            return false
        }
        guard export.phase == .written else {
            return XCTFail("write failed: \(export.phase)")
        }

        let report = try XCTUnwrap(export.exportReport)
        XCTAssertEqual(report.targetReports.count, 1)
        XCTAssertTrue(report.targetReports.allSatisfy { $0.status == .written || $0.status == .created })
        XCTAssertTrue(report.targetReports.allSatisfy { $0.validation?.valid == true })

        // AC4-028 full loop: stamp + XMP present → exported.
        XCTAssertEqual(
            AssetQueueDerivation.deriveState(sourcePath: sourcePath, relativePath: "A.JPG", outputDir: nil),
            .exported
        )

        // Deleting the exported XMP → "XMP missing (was exported)".
        let xmpPath = sourceRoot.appendingPathComponent("A.xmp").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: xmpPath))
        try FileManager.default.removeItem(atPath: xmpPath)
        XCTAssertEqual(
            AssetQueueDerivation.deriveState(sourcePath: sourcePath, relativePath: "A.JPG", outputDir: nil),
            .xmpMissingWasExported
        )
    }

    func testApplyConfigurationCarriesSelectedXMPConflictPolicy() throws {
        let configuration = try ExportModel.applyConfiguration(
            sourceRoot: "/source",
            outputDir: "/out",
            dryRun: true,
            xmpConflictPolicy: .fail,
            environment: [:],
            defaultConfigPath: root.appendingPathComponent("missing-config.json").path
        )

        XCTAssertEqual(configuration.sourceRoot, "/source")
        XCTAssertEqual(configuration.outputDir, "/out")
        XCTAssertTrue(configuration.dryRun)
        XCTAssertEqual(configuration.xmpConflictPolicy, .fail)
        XCTAssertTrue(configuration.backupSidecars)
    }

    func testApplyConfigurationQualityOverridesPreserveResolverOwnedChannels() throws {
        let configURL = root.appendingPathComponent("config.json")
        try Data(
            """
            {
              "xmp_quality_write_label": false,
              "xmp_quality_write_keywords": false,
              "xmp_quality_min_confidence": "high"
            }
            """.utf8
        ).write(to: configURL)
        let overrides = QualityGradingConfigurationOverrides(
            enabled: true,
            conflictPolicy: .refresh,
            writeRating: true
        )

        let configuration = try ExportModel.applyConfiguration(
            sourceRoot: "/source",
            outputDir: "/out",
            dryRun: true,
            xmpConflictPolicy: .merge,
            qualityGrading: overrides,
            environment: [:],
            defaultConfigPath: configURL.path
        )

        XCTAssertTrue(configuration.qualityGrading.enabled)
        XCTAssertEqual(configuration.qualityGrading.conflictPolicy, .refresh)
        XCTAssertTrue(configuration.qualityGrading.policy.writeRating)
        XCTAssertFalse(configuration.qualityGrading.policy.writeLabel)
        XCTAssertFalse(configuration.qualityGrading.policy.writeKeywords)
        XCTAssertEqual(configuration.qualityGrading.policy.minimumConfidence, .high)
    }

    @MainActor
    func testPlanFreezesQualityOverridesForMatchingWrite() async throws {
        let (session, sourceRoot) = try makeSession()
        let overrides = QualityGradingConfigurationOverrides(
            enabled: true,
            conflictPolicy: .overwrite,
            writeRating: true
        )
        let export = ExportModel(
            stateDirectory: root.appendingPathComponent("state"),
            environment: [:],
            defaultConfigPath: root.appendingPathComponent("missing-config.json").path
        )

        export.plan(
            session: session,
            sourceRoot: sourceRoot.path,
            outputDir: nil,
            qualityGrading: overrides
        )
        try await waitUntil("quality dry-run plan") { export.phase == .planReady }

        XCTAssertEqual(export.pendingQualityGrading, overrides)
        let plannedExplanation = try XCTUnwrap(export.plannedTargets.first?.qualityExplanation)

        export.confirmWrite()
        try await waitUntil("quality write") {
            if export.phase == .written { return true }
            if case .failed = export.phase { return true }
            return false
        }
        guard export.phase == .written else {
            return XCTFail("write failed: \(export.phase)")
        }

        let reportPlan = try XCTUnwrap(export.exportReport?.targetReports.first?.plan)
        XCTAssertEqual(reportPlan.qualityExplanation, plannedExplanation)
        XCTAssertEqual(reportPlan.ratingWrite, export.plannedTargets.first?.ratingWrite)
    }

    @MainActor
    func testCleanupAfterSuccessfulWriteRemovesOwnedArtifactsAndPreservesOutputs() async throws {
        let (session, sourceRoot) = try makeSession()
        let rawSidecar = sourceRoot.appendingPathComponent("A.JPG.ai.json")
        let nested = sourceRoot.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let nestedArtifact = nested.appendingPathComponent("\(ArtifactNames.batchSummaryPrefix)test.json")
        try Data("{}".utf8).write(to: nestedArtifact)
        let reusableSession = sourceRoot.appendingPathComponent("\(ArtifactNames.normalizationSessionPrefix)keep.json")
        try Data("{}".utf8).write(to: reusableSession)

        let export = ExportModel(stateDirectory: root.appendingPathComponent("state"))
        export.cleanupAfterWrite = true
        export.plan(session: session, sourceRoot: sourceRoot.path, outputDir: nil, recursive: true)
        XCTAssertFalse(export.cleanupAfterWrite, "fresh plans default cleanup to off")
        try await waitUntil("dry-run plan") { export.phase == .planReady }

        export.cleanupAfterWrite = true
        export.confirmWrite()
        try await waitUntil("write and cleanup") {
            export.phase == .written && export.cleanupRemovedCount != nil
        }

        XCTAssertGreaterThanOrEqual(export.cleanupRemovedCount ?? 0, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rawSidecar.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedArtifact.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("A.xmp").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reusableSession.path))
        XCTAssertNil(export.cleanupWarning)
    }

    @MainActor
    func testCleanupSkippedWhenFlagIsFalse() async throws {
        let (session, sourceRoot) = try makeSession()
        let rawSidecar = sourceRoot.appendingPathComponent("A.JPG.ai.json")

        let export = ExportModel(stateDirectory: root.appendingPathComponent("state"))
        export.plan(session: session, sourceRoot: sourceRoot.path, outputDir: nil, recursive: true)
        try await waitUntil("dry-run plan") { export.phase == .planReady }

        export.confirmWrite()
        try await waitUntil("write") { export.phase == .written }

        XCTAssertNil(export.cleanupRemovedCount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rawSidecar.path))
    }

    @MainActor
    func testCleanupSkippedWhenWriteHasFailedTargets() async throws {
        let (session, sourceRoot) = try makeSession()
        let rawSidecar = sourceRoot.appendingPathComponent("A.JPG.ai.json")
        let xmpURL = sourceRoot.appendingPathComponent("A.xmp")
        try Data(
            """
            <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                <rdf:Description rdf:about="" />
              </rdf:RDF>
            </x:xmpmeta>
            <?xpacket end="w"?>
            """.utf8
        ).write(to: xmpURL)

        let export = ExportModel(stateDirectory: root.appendingPathComponent("state"))
        export.plan(
            session: session,
            sourceRoot: sourceRoot.path,
            outputDir: nil,
            recursive: true,
            xmpConflictPolicy: .fail
        )
        try await waitUntil("dry-run plan") { export.phase == .planReady }
        XCTAssertFalse(export.failedTargets.isEmpty)

        export.cleanupAfterWrite = true
        export.confirmWrite()
        try await waitUntil("write with failures") {
            if export.phase == .written { return true }
            if case .failed = export.phase { return true }
            return false
        }

        XCTAssertNil(export.cleanupRemovedCount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rawSidecar.path))
    }

    /// The default write path merges into pre-existing XMP: the dry-run plan
    /// carries the merge preview the change-plan sheet reveals (existing
    /// keywords kept, not a new file), and the write preserves them on disk.
    @MainActor
    func testPlanRevealsMergeIntoExistingXMPAndWritePreservesKeywords() async throws {
        let (session, sourceRoot) = try makeSession()
        let xmpURL = sourceRoot.appendingPathComponent("A.xmp")
        try Data(
            """
            <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                <rdf:Description rdf:about=""
                    xmlns:dc="http://purl.org/dc/elements/1.1/"
                    xmlns:xmp="http://ns.adobe.com/xap/1.0/">
                  <xmp:Rating>4</xmp:Rating>
                  <dc:subject>
                    <rdf:Bag>
                      <rdf:li>Kyoto</rdf:li>
                      <rdf:li>Family Trip</rdf:li>
                    </rdf:Bag>
                  </dc:subject>
                </rdf:Description>
              </rdf:RDF>
            </x:xmpmeta>
            <?xpacket end="w"?>
            """.utf8
        ).write(to: xmpURL)

        let export = ExportModel(stateDirectory: root.appendingPathComponent("state"))
        export.plan(session: session, sourceRoot: sourceRoot.path, outputDir: nil)
        try await waitUntil("dry-run plan") { export.phase == .planReady }

        XCTAssertEqual(export.mergeTargets.count, 1)
        let preview = try XCTUnwrap(export.mergeTargets.first?.preview)
        XCTAssertFalse(preview.wouldCreate)
        XCTAssertEqual(preview.existingFlatKeywords, ["Kyoto", "Family Trip"])
        XCTAssertEqual(export.preservedKeywordCount, 2)
        XCTAssertTrue(preview.resultingFlatKeywords.contains("Kyoto"))
        XCTAssertTrue(preview.resultingFlatKeywords.contains("bird"))

        export.confirmWrite()
        try await waitUntil("write") {
            if case .written = export.phase { return true }
            if case .failed = export.phase { return true }
            return false
        }
        guard export.phase == .written else {
            return XCTFail("write failed: \(export.phase)")
        }

        let written = try String(contentsOf: xmpURL, encoding: .utf8)
        for preserved in ["Kyoto", "Family Trip", "<xmp:Rating>4</xmp:Rating>", "bird"] {
            XCTAssertTrue(written.contains(preserved), "merged XMP should contain \(preserved)")
        }
        // Backup-and-merge default: the pre-write file survives as a backup.
        let backups = try FileManager.default.contentsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasPrefix("A.xmp.bak-") }
        XCTAssertEqual(backups.count, 1)
    }

    @MainActor
    func testCancelPlanWritesNothing() async throws {
        let (session, sourceRoot) = try makeSession()
        let export = ExportModel(stateDirectory: root.appendingPathComponent("state"))
        export.plan(session: session, sourceRoot: sourceRoot.path, outputDir: nil)
        try await waitUntil("dry-run plan") { export.phase == .planReady }

        export.cancelPlan()
        XCTAssertEqual(export.phase, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("A.xmp").path))
    }

    @MainActor
    func testNormalizationSessionExportsThroughDryRunGateWithAcceptedSet() async throws {
        let sourceRoot = try makeRawSidecarSource(terms: ["bird", "tree"])
        let normalization = NormalizationModel(stateDirectory: root.appendingPathComponent("normalize-state"))

        normalization.run(jsonRoot: sourceRoot.path, sourceRoot: sourceRoot.path)
        try await waitUntil("normalization run") {
            switch normalization.phase {
            case .ready, .failed:
                return true
            default:
                return false
            }
        }
        guard normalization.phase == .ready, let session = normalization.session else {
            return XCTFail("normalization failed: \(normalization.phase)")
        }
        XCTAssertEqual(normalization.acceptedTotal, 2)

        let outputDir = root.appendingPathComponent("xmp-out")
        let xmpURL = outputDir.appendingPathComponent("A.xmp")
        let export = ExportModel(stateDirectory: root.appendingPathComponent("export-state"))
        export.plan(session: session, sourceRoot: sourceRoot.path, outputDir: outputDir.path)
        try await waitUntil("dry-run plan") {
            switch export.phase {
            case .planReady, .failed:
                return true
            default:
                return false
            }
        }

        guard export.phase == .planReady else {
            return XCTFail("dry-run plan failed: \(export.phase)")
        }
        XCTAssertEqual(export.writableTargets.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: xmpURL.path), "dry run must not write XMP")

        export.confirmWrite()
        try await waitUntil("write") {
            if export.phase == .written { return true }
            if case .failed = export.phase { return true }
            return false
        }
        guard export.phase == .written else {
            return XCTFail("write failed: \(export.phase)")
        }

        let xmpFiles = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
            .filter { $0.hasSuffix(".xmp") }
        XCTAssertEqual(xmpFiles.count, 1)
        let written = try String(contentsOf: xmpURL, encoding: .utf8)
        XCTAssertTrue(written.contains("bird"))
        XCTAssertTrue(written.contains("tree"))
    }
}
