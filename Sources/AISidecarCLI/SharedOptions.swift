import ArgumentParser
import AISidecarCore

enum BatchExitHelp {
    static let discussion = "Batch exit statuses: 0 for success, 1 when one or more items fail, and 130 when interrupted."
}

func enforceBatchExitPolicy(failureCount: Int, interrupted: Bool) throws {
    if let status = BatchExitPolicy.exitStatus(failureCount: failureCount, interrupted: interrupted) {
        throw ExitCode(status)
    }
}

func withBatchInterruptionExit<T>(_ operation: () throws -> T) throws -> T {
    do {
        return try operation()
    } catch let error as SidecarError where error.code == .interrupted {
        throw ExitCode(BatchExitPolicy.interruptedStatus)
    }
}

func withBatchInterruptionExit<T>(_ operation: () async throws -> T) async throws -> T {
    do {
        return try await operation()
    } catch let error as SidecarError where error.code == .interrupted {
        throw ExitCode(BatchExitPolicy.interruptedStatus)
    }
}

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

extension XMPSourceVerificationPolicy: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension XMPConflictPolicy: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension XMPMinimumConfidence: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension XMPPairScope: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension GPSContextMode: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension NormalizationMode: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension NormalizationVocabularyMode: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension NormalizationAffinityMode: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension NormalizationAffinityProfile: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension UnknownSessionContextPolicy: ExpressibleByArgument {
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

    @Option(help: "Maximum concurrent render/isolation preparation workers.")
    var stageConcurrency: Int?

    @Option(help: "Schema-constrained repair attempts after invalid model JSON or schema failure.")
    var modelResponseRepairAttempts: Int?

    @Option(help: "EXIF GPS context for model prompts: off, coarse, or exact.")
    var gpsContext: GPSContextMode?

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
            stageConcurrency: stageConcurrency,
            modelResponseRepairAttempts: modelResponseRepairAttempts,
            gpsContext: gpsContext
        )
    }
}
