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
}
