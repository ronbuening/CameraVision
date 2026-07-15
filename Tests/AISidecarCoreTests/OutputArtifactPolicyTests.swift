import XCTest

@testable import AISidecarCore

final class OutputArtifactPolicyTests: XCTestCase {
    func testNormalizeDefaultArtifactPlacementUsesInputBasePath() {
        let plan = NormalizationArtifactPlanner.planNormalize(
            inputBasePath: "/photos/batch",
            outputDir: nil,
            writeReportPath: nil,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            filenameSuffix: "a3f2"
        )

        XCTAssertEqual(plan.sessionPath, "/photos/batch/normalization-session-2027-01-15T080000Z-a3f2.json")
        XCTAssertEqual(plan.reportPath, "/photos/batch/normalization-report-2027-01-15T080000Z-a3f2.json")
        XCTAssertEqual(plan.summaryPath, "/photos/batch/normalization-summary-2027-01-15T080000Z-a3f2.md")
        XCTAssertEqual(plan.progressPath, "/photos/batch/normalization-progress-2027-01-15T080000Z-a3f2.jsonl")
        XCTAssertNil(plan.xmpTargetRoot)
    }

    func testNormalizeOutputDirStagesArtifactsAndHonorsExplicitReportPath() {
        let plan = NormalizationArtifactPlanner.planNormalize(
            inputBasePath: "/photos/batch",
            outputDir: "/tmp/normalized",
            writeReportPath: "/tmp/reports/normalization-report.json",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            filenameSuffix: "a3f2"
        )

        XCTAssertEqual(plan.sessionPath, "/tmp/normalized/normalization-session-2027-01-15T080000Z-a3f2.json")
        XCTAssertEqual(plan.reportPath, "/tmp/reports/normalization-report.json")
        XCTAssertEqual(plan.summaryPath, "/tmp/normalized/normalization-summary-2027-01-15T080000Z-a3f2.md")
        XCTAssertEqual(plan.progressPath, "/tmp/normalized/normalization-progress-2027-01-15T080000Z-a3f2.jsonl")
        XCTAssertEqual(plan.xmpTargetRoot, "/tmp/normalized")
    }

    func testApplySessionReadsOriginalSessionAndWritesSeparateApplyArtifacts() {
        let plan = NormalizationArtifactPlanner.planApplySession(
            sessionPath: "/sessions/normalization-session.json",
            outputDir: "/tmp/applied",
            writeReportPath: "/tmp/report.json",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            filenameSuffix: "a3f2"
        )

        XCTAssertEqual(plan.sessionPath, "/sessions/normalization-session.json")
        XCTAssertEqual(plan.reportPath, "/tmp/report.json")
        XCTAssertEqual(plan.summaryPath, "/tmp/applied/normalization-apply-summary-2027-01-15T080000Z-a3f2.md")
        XCTAssertEqual(plan.progressPath, "/tmp/applied/normalization-apply-progress-2027-01-15T080000Z-a3f2.jsonl")
        XCTAssertEqual(plan.xmpTargetRoot, "/tmp/applied")
    }
}
