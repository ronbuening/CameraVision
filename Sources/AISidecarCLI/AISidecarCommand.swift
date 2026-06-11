import ArgumentParser
import AISidecarCore

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
@main
struct AISidecarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aisidecar",
        abstract: "Generate and process AI sidecar metadata.",
        version: "0.0.0",
        subcommands: [
            AnalyzeCommand.self,
            BenchmarkCommand.self,
            PurgeCommand.self
        ]
    )
}
