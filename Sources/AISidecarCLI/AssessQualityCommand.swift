import AISidecarCore
import ArgumentParser

struct AssessQualityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assess-quality",
        abstract: "Assess image quality and write quality-only raw sidecars.",
        discussion: "Writes .quality.ai.json sidecars without creating or modifying XMP.\n\n\(BatchExitHelp.discussion)"
    )

    @Argument(help: "Image file or folder to assess for perceptual quality.")
    var inputPath: String

    @OptionGroup
    var shared: SharedOptions

    mutating func run() async throws {
        let resolved = try ConfigurationResolver.resolve(cli: shared.overrides)
        let logger = Logger(minimumLevel: resolved.logLevel, format: resolved.logFormat)
        let interruptionMonitor = InterruptionMonitor()
        interruptionMonitor.installSignalHandlers()
        let runner = try await VisionModelRunnerFactory().make(for: resolved)
        let pipeline = QualityAssessPipeline(logger: logger, runner: runner)
        let result = try await withAsyncBatchInterruptionExit {
            try await pipeline.run(
                inputPath: inputPath,
                configuration: resolved,
                interruptionMonitor: interruptionMonitor
            )
        }
        try enforceBatchExitPolicy(
            failureCount: result.records.filter { $0.status == .failed }.count,
            interrupted: result.interrupted
        )
    }
}
