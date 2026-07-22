import Foundation

/// Result of a Phase 2 XMP export pipeline invocation.
public struct XMPExportPipelineResult: Sendable, Equatable {
    public var changePlan: XMPChangePlanDocument
    public var report: XMPExportReport?
    public var progressLogPath: String?
    public var reportPath: String?
    public var summaryPath: String?
    public var interrupted: Bool

    public init(
        changePlan: XMPChangePlanDocument,
        report: XMPExportReport?,
        progressLogPath: String?,
        reportPath: String?,
        summaryPath: String?,
        interrupted: Bool
    ) {
        self.changePlan = changePlan
        self.report = report
        self.progressLogPath = progressLogPath
        self.reportPath = reportPath
        self.summaryPath = summaryPath
        self.interrupted = interrupted
    }
}

struct ExportArtifactPaths {
    var directory: String
    var progressPath: String
    var reportPath: String
    var summaryPath: String

    static func resolve(
        inputPath: String,
        outputDir: String?,
        startedAt: Date,
        runSuffix: String,
        fileManager: FileManager
    ) -> ExportArtifactPaths {
        let directory: String
        if let outputDir {
            directory = absoluteURL(for: outputDir, fileManager: fileManager).path
        } else if isDirectory(URL(fileURLWithPath: inputPath)) {
            directory = inputPath
        } else {
            directory = URL(fileURLWithPath: inputPath).deletingLastPathComponent().standardizedFileURL.path
        }

        let timestamp = Timestamp.filenameToken(startedAt, suffix: runSuffix)
        return ExportArtifactPaths(
            directory: directory,
            progressPath: "\(directory)/\(ArtifactNames.xmpExportProgressPrefix)\(timestamp).jsonl",
            reportPath: "\(directory)/\(ArtifactNames.xmpExportReportPrefix)\(timestamp).json",
            summaryPath: "\(directory)/\(ArtifactNames.xmpExportSummaryPrefix)\(timestamp).md"
        )
    }
}
