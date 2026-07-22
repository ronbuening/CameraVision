import AISidecarCore
import ArgumentParser
import Foundation

struct WriteXMPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "write-xmp",
        abstract: "Export accepted sidecar candidates to XMP sidecars.",
        discussion: BatchExitHelp.discussion
    )

    @Argument(help: "Image file or folder to analyze before writing XMP.")
    var inputPath: String?

    @Option(name: .customLong("from-json"), help: ".ai.json sidecar file or folder to export.")
    var fromJSON: String?

    @Option(help: "Map raw sidecar source.relative_path values back to this image root.")
    var sourceRoot: String?

    @Option(help: "Source identity policy for --from-json: fail, warn, or skip.")
    var sourceVerification: XMPSourceVerificationPolicy?

    @Option(help: "Analysis mode for analyze-and-write: whole, subject, or both.")
    var mode: AnalysisMode?

    @Option(help: "Policy for raw .ai.json outputs in analyze-and-write: skip, overwrite, or fail.")
    var existing: ExistingPolicy?

    @Flag(help: "Recurse into subfolders.")
    var recursive = false

    @Flag(help: "Also produce a perceptual quality assessment per image in analyze-and-write mode.")
    var assessQuality = false

    @Option(
        help:
            "With --assess-quality: 'combined' assesses in the tagging model call; 'sequential' runs a dedicated second pass that writes .quality.ai.json sidecars and keeps tagging output identical to a run without assessment."
    )
    var qualityScanMode: QualityScanMode?

    @Option(help: "Redirect outputs; mirrors the relative scan tree.")
    var outputDir: String?

    @Option(help: "Ollama model tag for analyze-and-write.")
    var model: String?

    @Option(help: "Vision model backend for analyze-and-write: ollama, apple, or auto.")
    var modelBackend: ModelBackend?

    @Option(help: "Ollama endpoint URL for analyze-and-write.")
    var modelEndpoint: String?

    @Option(help: "Model request timeout in seconds for analyze-and-write.")
    var modelTimeout: Double?

    @Option(help: "Model request retry limit for retryable analyze-and-write failures.")
    var modelRetryLimit: Int?

    @Option(help: "Model input profile name for analyze-and-write.")
    var profile: String?

    @Option(help: "Alternate JSON configuration file.")
    var config: String?

    @Option(help: "Log level: error, warn, info, or debug.")
    var logLevel: LogLevel?

    @Option(help: "Log format: text or json.")
    var logFormat: LogFormat?

    @Flag(help: "Report intended actions without writing outputs.")
    var dryRun = false

    @Flag(help: "Copy derivatives beside the source for inspection in analyze-and-write.")
    var debugDerivatives = false

    @Flag(help: "Clear the derivative cache before analyze-and-write uses it.")
    var clearDerivativeCacheOnStart = false

    @Flag(help: "Clear the derivative cache after successful analyze-and-write.")
    var clearDerivativeCacheAfterSuccess = false

    @Option(help: "Maximum concurrent render/isolation preparation workers for analyze-and-write.")
    var stageConcurrency: Int?

    @Option(help: "Schema-constrained repair attempts after invalid model JSON or schema failure.")
    var modelResponseRepairAttempts: Int?

    @Option(help: "EXIF GPS context for analyze-and-write model prompts: off, coarse, or exact.")
    var gpsContext: GPSContextMode?

    @Flag(name: .customLong("write-flat-keywords"), help: "Write accepted flat keywords to XMP-dc:Subject.")
    var writeFlatKeywords = false

    @Flag(name: .customLong("no-write-flat-keywords"), help: "Disable flat keyword export.")
    var noWriteFlatKeywords = false

    @Flag(
        name: .customLong("write-hierarchical-keywords"),
        help: "Write one-level hierarchical keywords to XMP-lr:HierarchicalSubject."
    )
    var writeHierarchicalKeywords = false

    @Flag(name: .customLong("no-write-hierarchical-keywords"), help: "Disable hierarchical keyword export.")
    var noWriteHierarchicalKeywords = false

    @Flag(name: .customLong("backup-sidecars"), help: "Back up existing XMP sidecars before modification.")
    var backupSidecars = false

    @Flag(name: .customLong("no-backup-sidecars"), help: "Do not back up existing XMP sidecars before modification.")
    var noBackupSidecars = false

    @Option(help: "Existing XMP policy: fail, merge, or backup-and-merge.")
    var xmpConflictPolicy: XMPConflictPolicy?

    @Option(help: "Minimum candidate confidence to export: low, medium, or high.")
    var minConfidence: XMPMinimumConfidence?

    @OptionGroup
    var quality: QualityGradingOptions

    @Flag(help: "Allow specific tags such as scientific names, named places, named events, or named people.")
    var allowSpecificTags = false

    @Option(help: "Same-base-name pair scope: union, raw-only, or jpeg-only.")
    var pairScope: XMPPairScope?

    @Flag(name: .customLong("write-ai-json"), help: "Preserve raw .ai.json sidecars in analyze-and-write mode.")
    var writeAIJSON = false

    @Flag(name: .customLong("no-write-ai-json"), help: "Do not write raw .ai.json sidecars in analyze-and-write mode.")
    var noWriteAIJSON = false

    mutating func validate() throws {
        _ = try XMPExportInvocationValidator.validate(invocationRequest)
    }

    mutating func run() async throws {
        let mode = try XMPExportInvocationValidator.validate(invocationRequest)
        let exportConfiguration = try ConfigurationResolver.resolveXMPExport(cli: xmpOverrides)
        let logger = Logger(minimumLevel: exportConfiguration.logLevel, format: exportConfiguration.logFormat)
        let interruptionMonitor = InterruptionMonitor()
        interruptionMonitor.installSignalHandlers()

        switch mode {
        case .fromJSON(let path):
            let result = try withBatchInterruptionExit {
                try XMPExportPipeline(
                    engine: OwnedXMPSidecarEngine(),
                    logger: logger
                ).runFromJSON(
                    fromJSONPath: path,
                    configuration: exportConfiguration,
                    interruptionMonitor: interruptionMonitor
                )
            }
            if exportConfiguration.dryRun {
                try CommandOutputHelpers.writeChangePlan(result.changePlan)
                try enforceBatchExitPolicy(
                    failureCount: failureCount(for: result),
                    interrupted: result.interrupted
                )
                return
            }
            if let report = result.report {
                CommandOutputHelpers.writeEssentialSummary(
                    prefix: "XMP export",
                    writtenCount: report.writtenCount,
                    failedCount: report.failedCount
                )
            }
            try enforceBatchExitPolicy(
                failureCount: failureCount(for: result),
                interrupted: result.interrupted
            )
        case .analyzeAndWrite(let inputPath):
            let runConfiguration = try ConfigurationResolver.resolve(cli: runOverrides)
            let runner = try await VisionModelRunnerFactory().make(for: runConfiguration)
            let result = try await withAsyncBatchInterruptionExit {
                try await AnalyzeAndXMPPipeline(logger: logger, runner: runner).run(
                    inputPath: inputPath,
                    runConfiguration: runConfiguration,
                    exportConfiguration: exportConfiguration,
                    interruptionMonitor: interruptionMonitor
                )
            }
            if exportConfiguration.dryRun {
                try CommandOutputHelpers.writeChangePlan(result.exportResult.changePlan)
                try enforceBatchExitPolicy(
                    failureCount: failureCount(for: result.exportResult),
                    interrupted: result.analyzeResult.interrupted || result.exportResult.interrupted
                )
                return
            }
            if let report = result.exportResult.report {
                CommandOutputHelpers.writeEssentialSummary(
                    prefix: "XMP export",
                    writtenCount: report.writtenCount,
                    failedCount: report.failedCount
                )
            }
            try enforceBatchExitPolicy(
                failureCount: failureCount(for: result.exportResult),
                interrupted: result.analyzeResult.interrupted || result.exportResult.interrupted
            )
        }
    }

    private var invocationRequest: XMPExportInvocationRequest {
        XMPExportInvocationRequest(
            inputPath: inputPath,
            fromJSONPath: fromJSON,
            sourceRoot: sourceRoot,
            sourceVerification: sourceVerification,
            mode: mode,
            existing: existing,
            assessQuality: assessQuality,
            model: model,
            modelBackend: modelBackend,
            modelEndpoint: modelEndpoint,
            modelTimeoutSeconds: modelTimeout,
            modelRetryLimit: modelRetryLimit,
            profile: profile,
            debugDerivatives: debugDerivatives,
            clearDerivativeCacheOnStart: clearDerivativeCacheOnStart,
            clearDerivativeCacheAfterSuccess: clearDerivativeCacheAfterSuccess,
            stageConcurrency: stageConcurrency,
            modelResponseRepairAttempts: modelResponseRepairAttempts,
            gpsContext: gpsContext,
            qualityGrading: quality.qualityGrading,
            qualityConflicts: quality.qualityConflicts,
            qualityMinConfidence: quality.qualityMinConfidence,
            writeFlatKeywords: writeFlatKeywords,
            noWriteFlatKeywords: noWriteFlatKeywords,
            writeHierarchicalKeywords: writeHierarchicalKeywords,
            noWriteHierarchicalKeywords: noWriteHierarchicalKeywords,
            writeRating: quality.writeRating,
            noWriteRating: quality.noWriteRating,
            writeLabel: quality.writeLabel,
            noWriteLabel: quality.noWriteLabel,
            writeUrgency: quality.writeUrgency,
            noWriteUrgency: quality.noWriteUrgency,
            writeFlag: quality.writeFlag,
            noWriteFlag: quality.noWriteFlag,
            writeQualityKeywords: quality.writeQualityKeywords,
            noWriteQualityKeywords: quality.noWriteQualityKeywords,
            backupSidecars: backupSidecars,
            noBackupSidecars: noBackupSidecars,
            writeAIJSON: writeAIJSON,
            noWriteAIJSON: noWriteAIJSON
        )
    }

    private var xmpOverrides: XMPExportConfigurationOverrides {
        XMPExportConfigurationOverrides(
            recursive: recursive ? true : nil,
            outputDir: outputDir,
            configPath: config,
            logLevel: logLevel,
            logFormat: logFormat,
            dryRun: dryRun ? true : nil,
            sourceRoot: sourceRoot,
            sourceVerification: sourceVerification,
            writeFlatKeywords: CommandOutputHelpers.pairedFlag(
                positive: writeFlatKeywords,
                negative: noWriteFlatKeywords
            ),
            writeHierarchicalKeywords: CommandOutputHelpers.pairedFlag(
                positive: writeHierarchicalKeywords,
                negative: noWriteHierarchicalKeywords
            ),
            backupSidecars: CommandOutputHelpers.pairedFlag(
                positive: backupSidecars,
                negative: noBackupSidecars
            ),
            xmpConflictPolicy: xmpConflictPolicy,
            minConfidence: minConfidence,
            allowSpecificTags: allowSpecificTags ? true : nil,
            pairScope: pairScope,
            writeAIJSON: CommandOutputHelpers.pairedFlag(positive: writeAIJSON, negative: noWriteAIJSON),
            qualityGrading: quality.overrides
        )
    }

    private var runOverrides: RunConfigurationOverrides {
        RunConfigurationOverrides(
            mode: mode,
            existing: existing,
            recursive: recursive ? true : nil,
            qualityAssessment: assessQuality ? true : nil,
            qualityScanMode: qualityScanMode,
            outputDir: outputDir,
            model: model,
            modelBackend: modelBackend,
            modelEndpoint: modelEndpoint,
            modelTimeoutSeconds: modelTimeout,
            modelRetryLimit: modelRetryLimit,
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

    private func failureCount(for result: XMPExportPipelineResult) -> Int {
        result.report?.failedCount ?? result.changePlan.failedCount
    }
}
