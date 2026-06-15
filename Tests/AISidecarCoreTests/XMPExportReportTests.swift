import Foundation
import XCTest
@testable import AISidecarCore

final class XMPExportReportTests: XCTestCase {
    func testReportSchemaAndMarkdownSummaryIncludeApplicationInstructions() throws {
        let report = XMPExportReport(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            inputPath: "/photos",
            reportDirectory: "/reports",
            dryRun: false,
            configuration: .builtInDefaults,
            engine: MetadataWriteEngineContext(
                engineName: OwnedXMPSidecarEngine.engineName,
                engineVersion: OwnedXMPSidecarEngine.engineVersion,
                writerRecipeVersion: OwnedXMPSidecarEngine.writerRecipeVersion
            ),
            targetReports: [
                XMPExportTargetReport(
                    plan: reportChangePlan(targetPath: "/photos/Bird.xmp", flat: ["wading bird"], hierarchical: []),
                    status: .created,
                    durationMs: 12
                )
            ],
            inputFailures: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let json = String(data: try encoder.encode(report), encoding: .utf8)
        let markdown = XMPExportSummaryWriter().markdown(for: report)

        XCTAssertTrue(json?.contains(#""schema_version":"ai-sidecar-xmp-export/1.0""#) == true)
        XCTAssertTrue(markdown.contains("Lightroom Classic"))
        XCTAssertTrue(markdown.contains("Metadata > Read Metadata from Files"))
        XCTAssertTrue(markdown.contains("Capture One"))
        XCTAssertTrue(markdown.contains("Auto Sync Sidecar XMP"))
    }

    private func reportChangePlan(targetPath: String, flat: [String], hierarchical: [String]) -> XMPChangePlan {
        XMPChangePlan(
            status: .planned,
            targetXMPPath: targetPath,
            targetRelativePath: URL(fileURLWithPath: targetPath).lastPathComponent,
            pairScope: .union,
            sourceMembers: [],
            flatKeywordsToAdd: flat.map(reportPlannedKeyword),
            hierarchicalKeywordsToAdd: hierarchical.map(reportPlannedKeyword),
            skippedCandidates: [],
            candidateExtractionIssues: [],
            sourceVerificationWarnings: [],
            groupWarnings: [],
            existingPolicy: .merge,
            backupPlan: BackupPlan(backupSidecars: false, backupRequiredBeforeMerge: false, conflictPolicy: .merge),
            validationPlan: .phase2Default,
            failures: []
        )
    }

    private func reportPlannedKeyword(_ term: String) -> PlannedKeyword {
        let normalized = KeywordTextNormalizer.normalize(term)
        return PlannedKeyword(
            term: normalized,
            normalizedKey: KeywordTextNormalizer.deduplicationKey(for: normalized),
            candidates: []
        )
    }
}
