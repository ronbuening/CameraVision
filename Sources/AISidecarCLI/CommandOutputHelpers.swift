import AISidecarCore
import Foundation

enum CommandOutputHelpers {
    static func pairedFlag(positive: Bool, negative: Bool) -> Bool? {
        if positive {
            return true
        }
        if negative {
            return false
        }
        return nil
    }

    static func writeChangePlan(
        _ changePlan: XMPChangePlanDocument,
        to output: FileHandle = .standardOutput
    ) throws {
        let encoder = JSONCoding.documentEncoder(iso8601Dates: false)
        let data = try encoder.encode(changePlan)
        output.write(data)
        output.write(Data("\n".utf8))
    }

    static func writeEssentialSummary(
        prefix: String,
        writtenCount: Int,
        failedCount: Int,
        to output: FileHandle = .standardOutput
    ) {
        let line = "\(prefix) complete: \(writtenCount) written, \(failedCount) failed."
        output.write(Data((line + "\n").utf8))
    }

    /// Essential summary for normalization-report commands: counts come from the embedded XMP
    /// export report, falling back to the report's error count when no export ran.
    static func writeEssentialSummary(
        prefix: String,
        report: NormalizationReport,
        to output: FileHandle = .standardOutput
    ) {
        writeEssentialSummary(
            prefix: prefix,
            writtenCount: report.xmpExportReport?.writtenCount ?? 0,
            failedCount: report.xmpExportReport?.failedCount ?? report.errors.count,
            to: output
        )
    }
}
