import Foundation
import ArgumentParser
import AISidecarCore

struct NormalizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "normalize",
        abstract: "Build Phase 3 normalized metadata decisions for a batch."
    )

    @Argument(help: "Image file or folder to analyze before normalization.")
    var inputPath: String?

    @Option(name: .customLong("from-json"), help: "Phase 1 .ai.json sidecar file or folder to normalize.")
    var fromJSON: String?

    @Option(name: .customLong("file-list"), help: "UTF-8 newline-delimited source image list.")
    var fileList: String?

    @Option(help: "Map raw sidecar source.relative_path values back to this image root.")
    var sourceRoot: String?

    @Option(help: "Source identity policy for --from-json: fail, warn, or skip.")
    var sourceVerification: XMPSourceVerificationPolicy?

    @Option(help: "Analysis mode for analyze-and-normalize: whole, subject, or both.")
    var mode: AnalysisMode?

    @Option(help: "Policy for raw .ai.json outputs in analyze-and-normalize: skip, overwrite, or fail.")
    var existing: ExistingPolicy?

    @Flag(help: "Recurse into subfolders.")
    var recursive = false

    @Option(help: "Redirect outputs; mirrors the relative scan tree.")
    var outputDir: String?

    @Option(help: "Ollama model tag for analyze-and-normalize.")
    var model: String?

    @Option(help: "Ollama endpoint URL for analyze-and-normalize.")
    var modelEndpoint: String?

    @Option(help: "Model input profile name for analyze-and-normalize.")
    var profile: String?

    @Option(help: "Alternate JSON configuration file.")
    var config: String?

    @Option(help: "Log level: error, warn, info, or debug.")
    var logLevel: LogLevel?

    @Option(help: "Log format: text or json.")
    var logFormat: LogFormat?

    @Flag(help: "Build plans without writing XMP sidecars.")
    var dryRun = false

    @Flag(help: "Copy derivatives beside the source for inspection in analyze-and-normalize.")
    var debugDerivatives = false

    @Flag(help: "Clear the derivative cache before analyze-and-normalize uses it.")
    var clearDerivativeCacheOnStart = false

    @Flag(help: "Clear the derivative cache after successful analyze-and-normalize.")
    var clearDerivativeCacheAfterSuccess = false

    @Option(help: "Maximum concurrent render/isolation preparation workers for analyze-and-normalize.")
    var stageConcurrency: Int?

    @Option(help: "Schema-constrained repair attempts after invalid model JSON or schema failure.")
    var modelResponseRepairAttempts: Int?

    @Option(help: "EXIF GPS context for analyze-and-normalize model prompts: off, coarse, or exact.")
    var gpsContext: GPSContextMode?

    @Flag(name: .customLong("write-flat-keywords"), help: "Write accepted flat keywords to XMP-dc:Subject.")
    var writeFlatKeywords = false

    @Flag(name: .customLong("no-write-flat-keywords"), help: "Disable flat keyword export.")
    var noWriteFlatKeywords = false

    @Flag(
        name: .customLong("write-hierarchical-keywords"),
        help: "Write controlled hierarchical keywords to XMP-lr:HierarchicalSubject."
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

    @Option(help: "Minimum candidate confidence to normalize: low, medium, or high.")
    var minConfidence: XMPMinimumConfidence?

    @Flag(help: "Allow Phase 2 fallback specific tags when normalization policy permits fallback.")
    var allowSpecificTags = false

    @Option(help: "Same-base-name pair scope: union, raw-only, or jpeg-only.")
    var pairScope: XMPPairScope?

    @Flag(name: .customLong("write-ai-json"), help: "Preserve raw .ai.json sidecars in analyze-and-normalize mode.")
    var writeAIJSON = false

    @Flag(name: .customLong("no-write-ai-json"), help: "Do not write raw .ai.json sidecars in analyze-and-normalize mode.")
    var noWriteAIJSON = false

    @Option(help: "Controlled vocabulary JSON file.")
    var vocabulary: String?

    @Option(help: "Normalization mode: off, single-image, or batch-conservative.")
    var normalizationMode: NormalizationMode?

    @Option(help: "User-supplied subject context for the session.")
    var sessionSubject: String?

    @Option(help: "User-supplied habitat context for the session.")
    var sessionHabitat: String?

    @Option(help: "User-supplied event context for the session.")
    var sessionEvent: String?

    @Option(help: "Global consensus threshold in the range 0...1.")
    var consensusThreshold: Double?

    @Option(help: "Affinity mode: off or metadata-weighted.")
    var affinityMode: NormalizationAffinityMode?

    @Option(help: "Affinity profile: conservative, balanced, or aggressive.")
    var affinityProfile: NormalizationAffinityProfile?

    @Option(help: "Minimum affinity edge score used for local consensus eligibility.")
    var minAffinityForConsensus: Double?

    @Flag(help: "Write normalization artifacts but no XMP sidecars.")
    var sessionOnly = false

    @Option(help: "Unknown session context policy: reject or write-unnormalized.")
    var unknownSessionContextPolicy: UnknownSessionContextPolicy?

    @Flag(help: "Allow session subject context to propagate to non-conflicting assets.")
    var allowSessionSubjectPropagation = false

    @Flag(help: "Allow session habitat context to propagate to non-conflicting assets.")
    var allowSessionHabitatPropagation = false

    @Flag(help: "Allow session event context to propagate to non-conflicting assets.")
    var allowSessionEventPropagation = false

    @Option(help: "Write the JSON report to an explicit path.")
    var writeReport: String?

    mutating func validate() throws {
        _ = try NormalizationInvocationValidator.validate(invocationRequest)
    }

    mutating func run() async throws {
        let mode = try NormalizationInvocationValidator.validate(invocationRequest)
        let resolved = try ConfigurationResolver.resolveNormalization(cli: normalizationOverrides)
        let interruptionMonitor = InterruptionMonitor()
        interruptionMonitor.installSignalHandlers()
        if resolved.sessionOnly {
            let result = try NormalizePipeline().runSessionOnly(
                mode: mode,
                configuration: resolved,
                interruptionMonitor: interruptionMonitor
            )
            let sessionPath = result.session.artifacts.sessionPath ?? "unplanned"
            FileHandle.standardOutput.write(
                Data(
                    """
                    normalization session written: \(sessionPath)
                    normalization report written: \(result.session.artifacts.reportPath)
                    \n
                    """.utf8
                )
            )
            return
        }
        if resolved.dryRun {
            let result = try NormalizePipeline().runDryRun(
                mode: mode,
                configuration: resolved,
                interruptionMonitor: interruptionMonitor
            )
            if let changePlan = result.changePlan {
                try writeChangePlan(changePlan)
            }
            return
        }

        switch mode {
        case .analyze(let inputPath):
            let runConfiguration = try ConfigurationResolver.resolve(cli: runOverrides)
            let logger = Logger(minimumLevel: resolved.logLevel, format: resolved.logFormat)
            let result = try await AnalyzeAndNormalizePipeline(logger: logger).run(
                inputPath: inputPath,
                runConfiguration: runConfiguration,
                normalizationConfiguration: resolved,
                interruptionMonitor: interruptionMonitor
            )
            writeEssentialSummary(result.normalizeResult.report)
        case .fromJSON, .fileList:
            let logger = Logger(minimumLevel: resolved.logLevel, format: resolved.logFormat)
            let result = try NormalizeAndWritePipeline(logger: logger).run(
                mode: mode,
                configuration: resolved,
                interruptionMonitor: interruptionMonitor
            )
            writeEssentialSummary(result.normalizeResult.report)
        }
    }

    private var invocationRequest: NormalizationInvocationRequest {
        NormalizationInvocationRequest(
            inputPath: inputPath,
            fromJSONPath: fromJSON,
            fileListPath: fileList,
            sourceRoot: sourceRoot,
            sourceVerification: sourceVerification,
            mode: mode,
            existing: existing,
            model: model,
            modelEndpoint: modelEndpoint,
            profile: profile,
            debugDerivatives: debugDerivatives,
            clearDerivativeCacheOnStart: clearDerivativeCacheOnStart,
            clearDerivativeCacheAfterSuccess: clearDerivativeCacheAfterSuccess,
            stageConcurrency: stageConcurrency,
            modelResponseRepairAttempts: modelResponseRepairAttempts,
            gpsContext: gpsContext,
            writeFlatKeywords: writeFlatKeywords,
            noWriteFlatKeywords: noWriteFlatKeywords,
            writeHierarchicalKeywords: writeHierarchicalKeywords,
            noWriteHierarchicalKeywords: noWriteHierarchicalKeywords,
            backupSidecars: backupSidecars,
            noBackupSidecars: noBackupSidecars,
            writeAIJSON: writeAIJSON,
            noWriteAIJSON: noWriteAIJSON
        )
    }

    private var normalizationOverrides: NormalizationConfigurationOverrides {
        NormalizationConfigurationOverrides(
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
            vocabularyPath: vocabulary,
            normalizationMode: normalizationMode,
            sessionSubject: sessionSubject,
            sessionHabitat: sessionHabitat,
            sessionEvent: sessionEvent,
            consensusThreshold: consensusThreshold,
            affinityMode: affinityMode,
            affinityProfile: affinityProfile,
            minAffinityForConsensus: minAffinityForConsensus,
            sessionOnly: sessionOnly ? true : nil,
            unknownSessionContextPolicy: unknownSessionContextPolicy,
            allowSessionSubjectPropagation: allowSessionSubjectPropagation ? true : nil,
            allowSessionHabitatPropagation: allowSessionHabitatPropagation ? true : nil,
            allowSessionEventPropagation: allowSessionEventPropagation ? true : nil,
            writeReportPath: writeReport
        )
    }

    private var runOverrides: RunConfigurationOverrides {
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

    private func pairedFlag(positive: Bool, negative: Bool) -> Bool? {
        if positive {
            return true
        }
        if negative {
            return false
        }
        return nil
    }

    private func writeChangePlan(_ changePlan: XMPChangePlanDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(changePlan)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private func writeEssentialSummary(_ report: NormalizationReport) {
        let exportReport = report.xmpExportReport
        let written = exportReport?.writtenCount ?? 0
        let failed = exportReport?.failedCount ?? report.errors.count
        let line = "normalize complete: \(written) written, \(failed) failed."
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
