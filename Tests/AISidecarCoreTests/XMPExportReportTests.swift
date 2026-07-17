import Foundation
import XCTest

@testable import AISidecarCore

final class XMPExportReportTests: XCTestCase {
    func testReportSchemaAndMarkdownSummaryIncludeApplicationInstructions() throws {
        var plan = reportChangePlan(targetPath: "/photos/Bird.xmp", flat: ["wading bird"], hierarchical: [])
        plan.ratingWrite = PlannedScalarWrite(
            field: "xmp:Rating",
            plannedValue: "4",
            existingValue: "3",
            action: .overwrite
        )
        plan.labelWrite = PlannedScalarWrite(
            field: "xmp:Label",
            plannedValue: "Green",
            existingValue: "Blue",
            action: .skipExisting
        )
        plan.urgencyWrite = PlannedScalarWrite(
            field: "photoshop:Urgency",
            plannedValue: "2",
            existingValue: nil,
            action: .write
        )
        plan.qualityExplanation = ["tier=good"]
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
                    plan: plan,
                    status: .created,
                    durationMs: 12
                )
            ],
            inputFailures: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let reportData = try encoder.encode(report)
        let json = String(data: reportData, encoding: .utf8)
        let markdown = XMPExportSummaryWriter().markdown(for: report)

        XCTAssertEqual(try JSONCoding.decoder().decode(XMPExportReport.self, from: reportData), report)
        XCTAssertTrue(json?.contains(#""schema_version":"ai-sidecar-xmp-export/1.1""#) == true)
        XCTAssertTrue(json?.contains(#""rating_write""#) == true)
        XCTAssertTrue(json?.contains(#""skip_existing""#) == true)
        XCTAssertTrue(json?.contains(#""urgency_write""#) == true)
        XCTAssertTrue(json?.contains(#""quality_explanation""#) == true)
        let targetReport = try XCTUnwrap(report.targetReports.first)
        XCTAssertEqual(targetReport.ratingWrite, plan.ratingWrite)
        XCTAssertEqual(targetReport.labelWrite, plan.labelWrite)
        XCTAssertEqual(targetReport.urgencyWrite, plan.urgencyWrite)
        XCTAssertEqual(targetReport.qualityExplanation, plan.qualityExplanation)
        XCTAssertTrue(markdown.contains("Lightroom Classic"))
        XCTAssertTrue(markdown.contains("Metadata > Read Metadata from Files"))
        XCTAssertTrue(markdown.contains("Capture One"))
        XCTAssertTrue(markdown.contains("Auto Sync Sidecar XMP"))
    }

    func testProgressRecordRoundTripsAllScalarWriteIndicators() throws {
        let record = XMPExportProgressRecord(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            targetXMPPath: "/photos/Bird.xmp",
            targetRelativePath: "Bird.xmp",
            status: .written,
            sourceMembers: [],
            addedFlatKeywords: [],
            addedHierarchicalKeywords: [],
            durationMs: 12,
            wroteRating: true,
            wroteLabel: false,
            wroteUrgency: true
        )

        let encoder = JSONCoding.documentEncoder()
        let data = try encoder.encode(record)
        XCTAssertEqual(try JSONCoding.decoder().decode(XMPExportProgressRecord.self, from: data), record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["wrote_rating"] as? Bool, true)
        XCTAssertEqual(object["wrote_label"] as? Bool, false)
        XCTAssertEqual(object["wrote_urgency"] as? Bool, true)
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
