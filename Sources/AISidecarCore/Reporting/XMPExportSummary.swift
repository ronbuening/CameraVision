import Foundation

/// Markdown summary writer for human-readable XMP export results.
public struct XMPExportSummaryWriter {
    private let fileManager: FileManager
    private let dataWriter: WriterSupport.DataWriter

    public init(fileManager: FileManager = .default) {
        self.init(fileManager: fileManager, dataWriter: WriterSupport.atomicWrite)
    }

    init(fileManager: FileManager = .default, dataWriter: @escaping WriterSupport.DataWriter) {
        self.fileManager = fileManager
        self.dataWriter = dataWriter
    }

    public func markdown(for report: XMPExportReport) -> String {
        var lines: [String] = []
        lines.append("# XMP Export Summary")
        lines.append("")
        lines.append("- Schema: \(report.schemaVersion)")
        lines.append("- Input: \(report.inputPath)")
        lines.append("- Engine: \(report.engine.engineName) \(report.engine.engineVersion)")
        lines.append("- Writer recipe: \(report.engine.writerRecipeVersion)")
        lines.append("- Targets: \(report.targetReports.count)")
        lines.append("- Written: \(report.writtenCount)")
        lines.append("- Failed: \(report.failedCount)")
        lines.append("")
        lines.append("## Targets")
        for target in report.targetReports {
            lines.append("- \(target.status.rawValue): \(target.plan.targetRelativePath)")
        }
        if !report.inputFailures.isEmpty {
            lines.append("")
            lines.append("## Input Failures")
            for failure in report.inputFailures {
                lines.append("- \(failure.error.code.rawValue): \(failure.sidecarPath)")
            }
        }
        lines.append("")
        lines.append("## Post-Export Application Instructions")
        for instruction in report.applicationInstructions {
            lines.append("- \(instruction)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public func write(_ report: XMPExportReport, to path: String) throws {
        try WriterSupport.writeAndWrap(
            Data(markdown(for: report).utf8), to: path, typeName: "write XMP export summary",
            fileManager: fileManager, dataWriter: dataWriter)
    }
}
