import ArgumentParser
import AISidecarCore

struct AISidecarCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aisidecar",
        abstract: "Generate and process AI sidecar metadata.",
        version: "0.0.0",
        subcommands: [
            AnalyzeCommand.self
        ]
    )
}

AISidecarCommand.main()
