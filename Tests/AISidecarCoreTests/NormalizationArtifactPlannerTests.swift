import XCTest
@testable import AISidecarCore

final class NormalizationArtifactPlannerTests: XCTestCase {
    func testNormalizeArtifactPlannerUsesOutputDirAndExplicitReport() {
        let plan = NormalizationArtifactPlanner.planNormalize(
            inputBasePath: "/input/images",
            outputDir: "/tmp/normalized",
            writeReportPath: "/tmp/report.json",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(plan.sessionPath, "/tmp/normalized/normalization-session-2027-01-15T08:00:00Z.json")
        XCTAssertEqual(plan.reportPath, "/tmp/report.json")
        XCTAssertEqual(plan.summaryPath, "/tmp/normalized/normalization-summary-2027-01-15T08:00:00Z.md")
        XCTAssertEqual(plan.progressPath, "/tmp/normalized/normalization-progress-2027-01-15T08:00:00Z.jsonl")
        XCTAssertEqual(plan.xmpTargetRoot, "/tmp/normalized")
    }

    func testApplySessionArtifactPlannerKeepsSessionReadOnly() {
        let plan = NormalizationArtifactPlanner.planApplySession(
            sessionPath: "/tmp/session/normalization-session.json",
            outputDir: nil,
            writeReportPath: nil,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(plan.sessionPath, "/tmp/session/normalization-session.json")
        XCTAssertEqual(plan.reportPath, "/tmp/session/normalization-apply-report-2027-01-15T08:00:00Z.json")
        XCTAssertEqual(plan.summaryPath, "/tmp/session/normalization-apply-summary-2027-01-15T08:00:00Z.md")
        XCTAssertEqual(plan.progressPath, "/tmp/session/normalization-apply-progress-2027-01-15T08:00:00Z.jsonl")
        XCTAssertNil(plan.xmpTargetRoot)
    }
}
