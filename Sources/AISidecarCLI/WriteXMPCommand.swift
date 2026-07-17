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

    @Option(help: "Redirect outputs; mirrors the relative scan tree.")
    var outputDir: String?

    @Option(help: "Ollama model tag for analyze-and-write.")
    var model: String?

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

    @Flag(help: "Grade stored quality assessments into configured XMP fields.")
    var qualityGrading = false

    @Flag(name: .customLong("write-rating"), help: "Write derived quality ratings to xmp:Rating.")
    var writeRating = false

    @Flag(name: .customLong("no-write-rating"), help: "Disable quality rating export.")
    var noWriteRating = false

    @Flag(name: .customLong("write-label"), help: "Write derived quality labels to xmp:Label.")
    var writeLabel = false

    @Flag(name: .customLong("no-write-label"), help: "Disable quality label export.")
    var noWriteLabel = false

    @Flag(
        name: .customLong("write-urgency"),
        help: "Write Capture One color companions to photoshop:Urgency."
    )
    var writeUrgency = false

    @Flag(name: .customLong("no-write-urgency"), help: "Disable Capture One urgency export.")
    var noWriteUrgency = false

    @Flag(name: .customLong("write-quality-keywords"), help: "Write deterministic quality-tier keywords.")
    var writeQualityKeywords = false

    @Flag(name: .customLong("no-write-quality-keywords"), help: "Disable quality-tier keyword export.")
    var noWriteQualityKeywords = false

    @Option(help: "Managed-scalar conflict policy: preserve, refresh, or overwrite.")
    var qualityConflicts: ScalarConflictPolicy?

    @Option(help: "Minimum confidence for quality grading: low, medium, or high.")
    var qualityMinConfidence: XMPMinimumConfidence?

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
                try writeChangePlan(result.changePlan)
                try enforceBatchExitPolicy(
                    failureCount: failureCount(for: result),
                    interrupted: result.interrupted
                )
                return
            }
            writeEssentialSummary(result.report)
            try enforceBatchExitPolicy(
                failureCount: failureCount(for: result),
                interrupted: result.interrupted
            )
        case .analyzeAndWrite(let inputPath):
            let runConfiguration = try ConfigurationResolver.resolve(cli: runOverrides)
            let result = try await withAsyncBatchInterruptionExit {
                try await AnalyzeAndXMPPipeline(logger: logger).run(
                    inputPath: inputPath,
                    runConfiguration: runConfiguration,
                    exportConfiguration: exportConfiguration,
                    interruptionMonitor: interruptionMonitor
                )
            }
            if exportConfiguration.dryRun {
                try writeChangePlan(result.exportResult.changePlan)
                try enforceBatchExitPolicy(
                    failureCount: failureCount(for: result.exportResult),
                    interrupted: result.analyzeResult.interrupted || result.exportResult.interrupted
                )
                return
            }
            writeEssentialSummary(result.exportResult.report)
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
            qualityGrading: qualityGrading,
            qualityConflicts: qualityConflicts,
            qualityMinConfidence: qualityMinConfidence,
            writeFlatKeywords: writeFlatKeywords,
            noWriteFlatKeywords: noWriteFlatKeywords,
            writeHierarchicalKeywords: writeHierarchicalKeywords,
            noWriteHierarchicalKeywords: noWriteHierarchicalKeywords,
            writeRating: writeRating,
            noWriteRating: noWriteRating,
            writeLabel: writeLabel,
            noWriteLabel: noWriteLabel,
            writeUrgency: writeUrgency,
            noWriteUrgency: noWriteUrgency,
            writeQualityKeywords: writeQualityKeywords,
            noWriteQualityKeywords: noWriteQualityKeywords,
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
            writeFlatKeywords: pairedFlag(positive: writeFlatKeywords, negative: noWriteFlatKeywords),
            writeHierarchicalKeywords: pairedFlag(
                positive: writeHierarchicalKeywords,
                negative: noWriteHierarchicalKeywords
            ),
            backupSidecars: pairedFlag(positive: backupSidecars, negative: noBackupSidecars),
            xmpConflictPolicy: xmpConflictPolicy,
            minConfidence: minConfidence,
            allowSpecificTags: allowSpecificTags ? true : nil,
            pairScope: pairScope,
            writeAIJSON: pairedFlag(positive: writeAIJSON, negative: noWriteAIJSON),
            qualityGrading: QualityGradingConfigurationOverrides(
                enabled: qualityGrading ? true : nil,
                conflictPolicy: qualityConflicts,
                minimumConfidence: qualityConfidence(from: qualityMinConfidence),
                writeRating: pairedFlag(positive: writeRating, negative: noWriteRating),
                writeLabel: pairedFlag(positive: writeLabel, negative: noWriteLabel),
                writeUrgency: pairedFlag(positive: writeUrgency, negative: noWriteUrgency),
                writeKeywords: pairedFlag(
                    positive: writeQualityKeywords,
                    negative: noWriteQualityKeywords
                )
            )
        )
    }

    private var runOverrides: RunConfigurationOverrides {
        RunConfigurationOverrides(
            mode: mode,
            existing: existing,
            recursive: recursive ? true : nil,
            qualityAssessment: assessQuality ? true : nil,
            outputDir: outputDir,
            model: model,
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

    private func pairedFlag(positive: Bool, negative: Bool) -> Bool? {
        if positive {
            return true
        }
        if negative {
            return false
        }
        return nil
    }

    private func qualityConfidence(
        from value: XMPMinimumConfidence?
    ) -> QualityAssessmentRecord.Confidence? {
        value.flatMap { QualityAssessmentRecord.Confidence(rawValue: $0.rawValue) }
    }

    private func writeChangePlan(_ changePlan: XMPChangePlanDocument) throws {
        let encoder = JSONCoding.documentEncoder(iso8601Dates: false)
        let data = try encoder.encode(changePlan)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private func writeEssentialSummary(_ report: XMPExportReport?) {
        guard let report else {
            return
        }
        let line = "XMP export complete: \(report.writtenCount) written, \(report.failedCount) failed."
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private func failureCount(for result: XMPExportPipelineResult) -> Int {
        result.report?.failedCount ?? result.changePlan.failedCount
    }
}
