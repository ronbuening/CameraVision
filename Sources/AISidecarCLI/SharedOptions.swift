import ArgumentParser
import AISidecarCore

extension AnalysisMode: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension ExistingPolicy: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension LogLevel: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension LogFormat: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

struct SharedOptions: ParsableArguments {
    @Option(help: "Analysis mode: whole, subject, or both.")
    var mode: AnalysisMode?

    @Option(help: "Policy for pre-existing output files: skip, overwrite, or fail.")
    var existing: ExistingPolicy?

    @Flag(help: "Recurse into subfolders.")
    var recursive = false

    @Option(help: "Redirect outputs; mirrors the relative scan tree.")
    var outputDir: String?

    @Option(help: "Ollama model tag.")
    var model: String?

    @Option(help: "Ollama endpoint URL.")
    var modelEndpoint: String?

    @Option(help: "Model input profile name.")
    var profile: String?

    @Option(help: "Alternate JSON configuration file.")
    var config: String?

    @Option(help: "Log level: error, warn, info, or debug.")
    var logLevel: LogLevel?

    @Option(help: "Log format: text or json.")
    var logFormat: LogFormat?

    @Flag(help: "Report intended actions without writing outputs.")
    var dryRun = false

    @Flag(help: "Copy derivatives beside the source for inspection.")
    var debugDerivatives = false

    @Flag(help: "Clear the derivative cache before this analyze invocation uses it.")
    var clearDerivativeCacheOnStart = false

    @Flag(help: "Clear the derivative cache after a successful analyze invocation.")
    var clearDerivativeCacheAfterSuccess = false

    @Option(help: "Schema-constrained repair attempts after invalid model JSON or schema failure.")
    var modelResponseRepairAttempts: Int?

    var overrides: RunConfigurationOverrides {
        RunConfigurationOverrides(
            mode: mode,
            existing: existing,
            recursive: recursive ? true : nil,
            outputDir: outputDir,
            model: model,
            modelEndpoint: modelEndpoint,
            profile: profile,
            configPath: config,
            logLevel: logLevel,
            logFormat: logFormat,
            dryRun: dryRun ? true : nil,
            debugDerivatives: debugDerivatives ? true : nil,
            clearDerivativeCacheOnStart: clearDerivativeCacheOnStart ? true : nil,
            clearDerivativeCacheAfterSuccess: clearDerivativeCacheAfterSuccess ? true : nil,
            modelResponseRepairAttempts: modelResponseRepairAttempts
        )
    }
}
