import Foundation
import ArgumentParser
import AISidecarCore

struct AnalyzeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Analyze one image file or a folder of image files."
    )

    @Argument(help: "Image file or folder to analyze.")
    var inputPath: String

    @Flag(help: "Print the scan result with identities and relative paths, then exit.")
    var dryScan = false

    @OptionGroup
    var shared: SharedOptions

    mutating func run() throws {
        let resolved = try ConfigurationResolver.resolve(cli: shared.overrides)

        if dryScan {
            let scanner = ImageScanner()
            let result = try scanner.scan(
                inputPath: inputPath,
                recursive: resolved.recursive,
                identityPolicy: resolved.sourceIdentityPolicy
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(result)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        let logger = Logger(minimumLevel: resolved.logLevel, format: resolved.logFormat)
        try logger.log(
            LogRecord(
                level: .info,
                event: "analyze.scaffold",
                message: "Analyze pipeline is not implemented until Milestone 1.",
                sourcePath: inputPath,
                status: "not_implemented"
            )
        )
    }
}
