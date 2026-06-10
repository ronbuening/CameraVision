import ArgumentParser
import AISidecarCore

struct AnalyzeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Analyze one image file or a folder of image files."
    )

    @Argument(help: "Image file or folder to analyze.")
    var inputPath: String

    @OptionGroup
    var shared: SharedOptions

    mutating func run() throws {
        let resolved = try ConfigurationResolver.resolve(cli: shared.overrides)
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
