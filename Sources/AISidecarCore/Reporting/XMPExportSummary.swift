import Foundation

/// Markdown summary writer for human-readable XMP export results.
public struct XMPExportSummaryWriter {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
        do {
            let data = Data(markdown(for: report).utf8)
            try AtomicFileWriter.write(data, to: URL(fileURLWithPath: path), fileManager: fileManager)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to write XMP export summary \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}
