import ArgumentParser
import AISidecarCore

@main
struct AISidecarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aisidecar",
        abstract: "Generate and process AI sidecar metadata.",
        version: "0.0.0",
        subcommands: [
            AnalyzeCommand.self,
            WriteXMPCommand.self,
            BenchmarkCommand.self,
            PurgeCommand.self
        ]
    )
}
