import XCTest

@testable import AISidecarCore

final class NormalizationReportTests: XCTestCase {
    func testReportAndSummaryIncludeAffinityDecisionsSkipsAndApplicationInstructions() throws {
        let fixture = try reportFixture()
        let report = fixture.report
        let markdown = NormalizationSummaryWriter().markdown(for: report)

        XCTAssertEqual(report.schemaVersion, NormalizationSchemaIdentifiers.report)
        XCTAssertEqual(report.vocabulary.sha256.count, 64)
        XCTAssertEqual(report.xmpWriter.engineName, OwnedXMPSidecarEngine.engineName)
        XCTAssertEqual(report.xmpWriter.writerRecipeVersion, OwnedXMPSidecarEngine.writerRecipeVersion)
        XCTAssertFalse(report.affinity.edges.isEmpty)
        XCTAssertFalse(report.localConsensus.isEmpty)
        XCTAssertTrue(report.applicationInstructions.contains { $0.contains("Lightroom Classic") })
        XCTAssertTrue(report.applicationInstructions.contains { $0.contains("Capture One") })

        XCTAssertTrue(markdown.contains("# Normalization Summary"))
        XCTAssertTrue(markdown.contains("XMP writer: \(OwnedXMPSidecarEngine.engineName)"))
        XCTAssertTrue(markdown.contains("basis filename_sequence"))
        XCTAssertTrue(markdown.contains("agreement 1"))
        XCTAssertTrue(markdown.contains("support 1.4/1.4, neighbors 2"))
        XCTAssertTrue(markdown.contains("weak_local_agreement: 1"))
        XCTAssertTrue(markdown.contains("Post-Export Application Instructions"))
    }

    func testReportWriterEmitsStableJSONWithoutRawSensitiveAffinityValues() throws {
        let fixture = try reportFixture()
        let root = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let reportPath = root.appendingPathComponent("normalization-report.json")

        try NormalizationReportWriter().write(fixture.report, to: reportPath.path)
        let data = try Data(contentsOf: reportPath)
        let text = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder.iso8601.decode(NormalizationReport.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, NormalizationSchemaIdentifiers.report)
        XCTAssertTrue(text.contains(#""schema_version" : "ai-sidecar-normalization-report/1.0""#))
        XCTAssertTrue(text.contains(#""camera_serial_hash""#))
        XCTAssertFalse(text.contains(fixture.rawSerial))
        XCTAssertFalse(text.contains("40.7128"))
        XCTAssertFalse(text.contains("-74.006"))
    }

    private func reportFixture() throws -> (report: NormalizationReport, rawSerial: String) {
        let rawSerial = "serial-do-not-persist"
        var assets = [
            phase3Asset(index: 1, relativePath: "seq/IMG_0001.JPG"),
            phase3Asset(index: 2, relativePath: "seq/IMG_0002.JPG"),
            phase3Asset(index: 3, relativePath: "seq/IMG_0003.JPG"),
        ]
        assets[0].affinityInputs.cameraSerialHash = AssetAffinityInputBuilder.stableSessionHash(rawSerial)
        let input = phase3InputBatch(assets: assets)
        let consensus = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(decisions: [
                phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Subject|Wildlife|Birds"),
                phase3DirectDecision(assetID: "asset-000002", canonicalPath: "Subject|Wildlife|Birds"),
            ]),
            input: input,
            configuration: phase3Configuration()
        )
        let writePlans = try NormalizedXMPChangePlanner().plan(
            input: input,
            decisions: consensus.perAssetDecisions,
            candidateSkips: [],
            configuration: phase3Configuration()
        ).writePlans
        let skip = NormalizationCandidateSkip(
            skipID: "skip-000001",
            reason: .weakLocalAgreement,
            assetID: "asset-000003",
            canonicalPath: "Subject|Mammals"
        )
        let artifacts = NormalizationArtifactPlan(
            sessionPath: "/tmp/normalization-session.json",
            reportPath: "/tmp/normalization-report.json",
            summaryPath: "/tmp/normalization-summary.md",
            progressPath: "/tmp/normalization-progress.jsonl",
            xmpTargetRoot: nil
        )
        let writer = MetadataWriteEngineContext(
            engineName: OwnedXMPSidecarEngine.engineName,
            engineVersion: OwnedXMPSidecarEngine.engineVersion,
            writerRecipeVersion: OwnedXMPSidecarEngine.writerRecipeVersion
        )
        let vocabulary = try phase3LoadedVocabulary().identity
        let report = NormalizationReport(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            sessionPath: artifacts.sessionPath,
            workflow: .fileList,
            inputPath: input.inputPath,
            configuration: phase3Configuration(),
            vocabulary: vocabulary,
            xmpWriter: writer,
            artifacts: artifacts,
            inputSummary: NormalizationInputSummary(
                sourceAssetCount: input.sourceAssets.count,
                sourceAISidecarCount: input.sourceAISidecars.count,
                sameBaseNameGroupCount: input.sameBaseNameGroups.count,
                candidateSkipCount: 1,
                batchCandidateCount: consensus.batchCandidates.count,
                perAssetDecisionCount: consensus.perAssetDecisions.count,
                xmpWritePlanCount: writePlans.count,
                warningCount: 0,
                failureCount: 0
            ),
            decisionSummary: NormalizationDecisionSummary(decisions: consensus.perAssetDecisions),
            sourceAssets: input.sourceAssets,
            sameBaseNameGroups: input.sameBaseNameGroups,
            affinity: consensus.affinity,
            candidateSkips: [skip],
            batchCandidates: consensus.batchCandidates,
            localConsensus: consensus.localConsensus,
            perAssetDecisions: consensus.perAssetDecisions,
            xmpWritePlans: writePlans,
            warnings: [],
            errors: []
        )
        return (report, rawSerial)
    }
}

extension JSONDecoder {
    fileprivate static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
