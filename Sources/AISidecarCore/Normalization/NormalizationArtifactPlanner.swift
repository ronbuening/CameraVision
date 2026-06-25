import Foundation

/// Deterministic artifact locations for Phase 3 session, report, summary, and progress files.
public struct NormalizationArtifactPlan: Codable, Sendable, Equatable {
    public var sessionPath: String?
    public var reportPath: String
    public var summaryPath: String
    public var progressPath: String
    public var xmpTargetRoot: String?

    enum CodingKeys: String, CodingKey {
        case sessionPath = "session_path"
        case reportPath = "report_path"
        case summaryPath = "summary_path"
        case progressPath = "progress_path"
        case xmpTargetRoot = "xmp_target_root"
    }

    public init(
        sessionPath: String?,
        reportPath: String,
        summaryPath: String,
        progressPath: String,
        xmpTargetRoot: String?
    ) {
        self.sessionPath = sessionPath
        self.reportPath = reportPath
        self.summaryPath = summaryPath
        self.progressPath = progressPath
        self.xmpTargetRoot = xmpTargetRoot
    }
}

/// Resolves Phase 3 artifact paths without creating files.
public enum NormalizationArtifactPlanner {
    public static func planNormalize(
        inputBasePath: String,
        outputDir: String?,
        writeReportPath: String?,
        timestamp: Date
    ) -> NormalizationArtifactPlan {
        let root = URL(fileURLWithPath: outputDir ?? inputBasePath).standardizedFileURL
        let stamp = timestampString(timestamp)
        let sessionPath = root.appendingPathComponent("normalization-session-\(stamp).json").path
        let reportPath = writeReportPath
            ?? root.appendingPathComponent("normalization-report-\(stamp).json").path
        return NormalizationArtifactPlan(
            sessionPath: sessionPath,
            reportPath: reportPath,
            summaryPath: root.appendingPathComponent("normalization-summary-\(stamp).md").path,
            progressPath: root.appendingPathComponent("normalization-progress-\(stamp).jsonl").path,
            xmpTargetRoot: outputDir
        )
    }

    public static func planApplySession(
        sessionPath: String,
        outputDir: String?,
        writeReportPath: String?,
        timestamp: Date
    ) -> NormalizationArtifactPlan {
        let sessionURL = URL(fileURLWithPath: sessionPath).standardizedFileURL
        let root = URL(fileURLWithPath: outputDir ?? sessionURL.deletingLastPathComponent().path).standardizedFileURL
        let stamp = timestampString(timestamp)
        let reportPath = writeReportPath
            ?? root.appendingPathComponent("normalization-apply-report-\(stamp).json").path
        return NormalizationArtifactPlan(
            sessionPath: sessionURL.path,
            reportPath: reportPath,
            summaryPath: root.appendingPathComponent("normalization-apply-summary-\(stamp).md").path,
            progressPath: root.appendingPathComponent("normalization-apply-progress-\(stamp).jsonl").path,
            xmpTargetRoot: outputDir
        )
    }

    private static func timestampString(_ timestamp: Date) -> String {
        ISO8601DateFormatter().string(from: timestamp)
    }
}
