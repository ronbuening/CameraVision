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
        timestamp: Date,
        filenameSuffix: String = Timestamp.randomFilenameSuffix()
    ) -> NormalizationArtifactPlan {
        let root = URL(fileURLWithPath: outputDir ?? inputBasePath).standardizedFileURL
        let stamp = Timestamp.filenameToken(timestamp, suffix: filenameSuffix)
        let sessionPath = root.appendingPathComponent("\(ArtifactNames.normalizationSessionPrefix)\(stamp).json").path
        let reportPath = writeReportPath
            ?? root.appendingPathComponent("\(ArtifactNames.normalizationReportPrefix)\(stamp).json").path
        return NormalizationArtifactPlan(
            sessionPath: sessionPath,
            reportPath: reportPath,
            summaryPath: root.appendingPathComponent("\(ArtifactNames.normalizationSummaryPrefix)\(stamp).md").path,
            progressPath: root.appendingPathComponent("\(ArtifactNames.normalizationProgressPrefix)\(stamp).jsonl").path,
            xmpTargetRoot: outputDir
        )
    }

    public static func planApplySession(
        sessionPath: String,
        outputDir: String?,
        writeReportPath: String?,
        timestamp: Date,
        filenameSuffix: String = Timestamp.randomFilenameSuffix()
    ) -> NormalizationArtifactPlan {
        let sessionURL = URL(fileURLWithPath: sessionPath).standardizedFileURL
        let root = URL(fileURLWithPath: outputDir ?? sessionURL.deletingLastPathComponent().path).standardizedFileURL
        let stamp = Timestamp.filenameToken(timestamp, suffix: filenameSuffix)
        let reportPath = writeReportPath
            ?? root.appendingPathComponent("\(ArtifactNames.normalizationApplyReportPrefix)\(stamp).json").path
        return NormalizationArtifactPlan(
            sessionPath: sessionURL.path,
            reportPath: reportPath,
            summaryPath: root.appendingPathComponent("\(ArtifactNames.normalizationApplySummaryPrefix)\(stamp).md").path,
            progressPath: root.appendingPathComponent("\(ArtifactNames.normalizationApplyProgressPrefix)\(stamp).jsonl").path,
            xmpTargetRoot: outputDir
        )
    }
}
