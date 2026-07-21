import AISidecarCore
import Foundation
import XCTest

@testable import AISidecarCLI

final class CommandOutputHelpersTests: XCTestCase {
    func testPairedFlagPreservesPositiveNegativeAndUnspecifiedStates() {
        XCTAssertEqual(CommandOutputHelpers.pairedFlag(positive: true, negative: false), true)
        XCTAssertEqual(CommandOutputHelpers.pairedFlag(positive: false, negative: true), false)
        XCTAssertNil(CommandOutputHelpers.pairedFlag(positive: false, negative: false))
        XCTAssertEqual(CommandOutputHelpers.pairedFlag(positive: true, negative: true), true)
    }

    func testChangePlanOutputPreservesDocumentBytesAndTrailingNewline() throws {
        let plan = XMPChangePlanDocument(dryRun: true, targetPlans: [], inputFailures: [])
        let output = try captureOutput { handle in
            try CommandOutputHelpers.writeChangePlan(plan, to: handle)
        }
        var expected = try JSONCoding.documentEncoder(iso8601Dates: false).encode(plan)
        expected.append(contentsOf: Data("\n".utf8))

        XCTAssertEqual(output, expected)
    }

    func testEssentialSummaryOutputPreservesEveryCommandPrefix() throws {
        for prefix in ["XMP export", "normalize", "apply-session"] {
            let output = try captureOutput { handle in
                CommandOutputHelpers.writeEssentialSummary(
                    prefix: prefix,
                    writtenCount: 3,
                    failedCount: 1,
                    to: handle
                )
            }

            XCTAssertEqual(String(decoding: output, as: UTF8.self), "\(prefix) complete: 3 written, 1 failed.\n")
        }
    }

    func testEssentialSummaryFromReportUsesExportCountsWithErrorCountFallback() throws {
        var report = makeNormalizationReport(errors: [makeError("first"), makeError("second")])

        let fallbackOutput = try captureOutput { handle in
            CommandOutputHelpers.writeEssentialSummary(prefix: "normalize", report: report, to: handle)
        }
        XCTAssertEqual(
            String(decoding: fallbackOutput, as: UTF8.self),
            "normalize complete: 0 written, 2 failed.\n",
            "Without an XMP export report, failures fall back to the report's error count."
        )

        report.xmpExportReport = XMPExportReport(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            inputPath: "/photos/images.txt",
            reportDirectory: nil,
            dryRun: false,
            configuration: .builtInDefaults,
            engine: makeEngineContext(),
            targetReports: [],
            inputFailures: [
                XMPChangePlanInputFailure(
                    sidecarPath: "/sidecars/a.ai.json",
                    relativePath: "a.ai.json",
                    error: makeError("target")
                )
            ]
        )
        let exportOutput = try captureOutput { handle in
            CommandOutputHelpers.writeEssentialSummary(prefix: "normalize", report: report, to: handle)
        }
        XCTAssertEqual(
            String(decoding: exportOutput, as: UTF8.self),
            "normalize complete: 0 written, 1 failed.\n",
            "With an XMP export report, its counts win over the report error count."
        )
    }

    private func makeNormalizationReport(errors: [SidecarError]) -> NormalizationReport {
        NormalizationReport(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            sessionPath: nil,
            workflow: .fileList,
            inputPath: "/photos/images.txt",
            configuration: .builtInDefaults,
            vocabulary: VocabularyIdentity(
                path: "/vocab.json",
                sha256: String(repeating: "a", count: 64),
                schemaVersion: "ai-sidecar-vocabulary/1.0"
            ),
            xmpWriter: makeEngineContext(),
            artifacts: NormalizationArtifactPlan(
                sessionPath: "/reports/normalization-session.json",
                reportPath: "/reports/normalization-report.json",
                summaryPath: "/reports/normalization-summary.md",
                progressPath: "/reports/normalization-progress.jsonl",
                xmpTargetRoot: nil
            ),
            inputSummary: NormalizationInputSummary(
                sourceAssetCount: 0,
                sourceAISidecarCount: 0,
                sameBaseNameGroupCount: 0,
                warningCount: 0,
                failureCount: errors.count
            ),
            warnings: [],
            errors: errors
        )
    }

    private func makeEngineContext() -> MetadataWriteEngineContext {
        MetadataWriteEngineContext(
            engineName: OwnedXMPSidecarEngine.engineName,
            engineVersion: OwnedXMPSidecarEngine.engineVersion,
            writerRecipeVersion: OwnedXMPSidecarEngine.writerRecipeVersion
        )
    }

    private func makeError(_ message: String) -> SidecarError {
        SidecarError(code: .writeFailed, stage: .write, message: message, recoverable: true)
    }

    private func captureOutput(_ body: (FileHandle) throws -> Void) throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("stdout.txt")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        try body(handle)
        try handle.close()
        return try Data(contentsOf: outputURL)
    }
}
