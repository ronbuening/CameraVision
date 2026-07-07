import ArgumentParser
import AISidecarCore

@main
struct AISidecarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aisidecar",
        abstract: "Generate and process AI sidecar metadata.",
        version: AISidecarVersion.current,
        subcommands: [
            AnalyzeCommand.self,
            WriteXMPCommand.self,
            NormalizeCommand.self,
            ApplySessionCommand.self,
            ExplainSessionCommand.self,
            BenchmarkCommand.self,
            PurgeCommand.self,
            CleanupCommand.self
        ]
    )
}
