import Foundation
import ArgumentParser
import AISidecarCore

struct WriteXMPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "write-xmp",
        abstract: "Export accepted Phase 1 sidecar candidates to XMP sidecars."
    )

    @Argument(help: "Image file or folder to analyze before writing XMP.")
    var inputPath: String?

    @Option(name: .customLong("from-json"), help: "Phase 1 .ai.json sidecar file or folder to export.")
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

    @Option(help: "Redirect outputs; mirrors the relative scan tree.")
    var outputDir: String?

    @Option(help: "Ollama model tag for analyze-and-write.")
    var model: String?

    @Option(help: "Ollama endpoint URL for analyze-and-write.")
    var modelEndpoint: String?

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

    @Option(help: "Schema-constrained repair attempts after invalid model JSON or schema failure.")
    var modelResponseRepairAttempts: Int?

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

    @Flag(help: "Allow specific tags such as species, named places, named events, or named people.")
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
        _ = try ConfigurationResolver.resolveXMPExport(cli: xmpOverrides)

        if case .analyzeAndWrite = mode {
            _ = try ConfigurationResolver.resolve(cli: runOverrides)
        }

        throw SidecarError.configInvalid(
            "aisidecar write-xmp is scaffolded for Phase 2 Milestone 0; export execution is not implemented until a later milestone."
        )
    }

    private var invocationRequest: XMPExportInvocationRequest {
        XMPExportInvocationRequest(
            inputPath: inputPath,
            fromJSONPath: fromJSON,
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
            modelResponseRepairAttempts: modelResponseRepairAttempts,
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
            writeAIJSON: pairedFlag(positive: writeAIJSON, negative: noWriteAIJSON)
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
            modelResponseRepairAttempts: modelResponseRepairAttempts
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
}
