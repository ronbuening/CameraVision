import Foundation
import ArgumentParser
import AISidecarCore

struct ApplySessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply-session",
        abstract: "Apply a frozen Phase 3 normalization session without model runs."
    )

    @Argument(help: "Normalization session JSON file.")
    var sessionPath: String?

    @Option(help: "Redirect XMP outputs; mirrors the resolved source tree.")
    var outputDir: String?

    @Option(help: "Alternate JSON configuration file.")
    var config: String?

    @Option(help: "Log level: error, warn, info, or debug.")
    var logLevel: LogLevel?

    @Option(help: "Log format: text or json.")
    var logFormat: LogFormat?

    @Flag(help: "Preview current session writes without modifying XMP sidecars.")
    var dryRun = false

    @Option(help: "Map session source-relative paths back to this image root.")
    var sourceRoot: String?

    @Option(help: "Source identity policy: fail, warn, or skip.")
    var sourceVerification: XMPSourceVerificationPolicy?

    @Flag(name: .customLong("backup-sidecars"), help: "Back up existing XMP sidecars before modification.")
    var backupSidecars = false

    @Flag(name: .customLong("no-backup-sidecars"), help: "Do not back up existing XMP sidecars before modification.")
    var noBackupSidecars = false

    @Option(help: "Existing XMP policy: fail, merge, or backup-and-merge.")
    var xmpConflictPolicy: XMPConflictPolicy?

    @Flag(help: "Allow writes for assets whose source identity has changed.")
    var allowStale = false

    @Option(name: .customLong("from-json"), help: .hidden)
    var invalidFromJSON: String?
    @Option(name: .customLong("file-list"), help: .hidden)
    var invalidFileList: String?
    @Option(name: .customLong("mode"), help: .hidden)
    var invalidMode: AnalysisMode?
    @Option(name: .customLong("model"), help: .hidden)
    var invalidModel: String?
    @Option(name: .customLong("model-endpoint"), help: .hidden)
    var invalidModelEndpoint: String?
    @Option(name: .customLong("profile"), help: .hidden)
    var invalidProfile: String?
    @Option(name: .customLong("min-confidence"), help: .hidden)
    var invalidMinConfidence: XMPMinimumConfidence?
    @Option(name: .customLong("pair-scope"), help: .hidden)
    var invalidPairScope: XMPPairScope?
    @Option(name: .customLong("normalization-mode"), help: .hidden)
    var invalidNormalizationMode: NormalizationMode?
    @Option(name: .customLong("affinity-mode"), help: .hidden)
    var invalidAffinityMode: NormalizationAffinityMode?
    @Option(name: .customLong("affinity-profile"), help: .hidden)
    var invalidAffinityProfile: NormalizationAffinityProfile?
    @Option(name: .customLong("min-affinity-for-consensus"), help: .hidden)
    var invalidMinAffinityForConsensus: Double?
    @Option(name: .customLong("consensus-threshold"), help: .hidden)
    var invalidConsensusThreshold: Double?
    @Option(name: .customLong("session-subject"), help: .hidden)
    var invalidSessionSubject: String?
    @Option(name: .customLong("session-habitat"), help: .hidden)
    var invalidSessionHabitat: String?
    @Option(name: .customLong("session-event"), help: .hidden)
    var invalidSessionEvent: String?
    @Option(name: .customLong("unknown-session-context-policy"), help: .hidden)
    var invalidUnknownPolicy: UnknownSessionContextPolicy?

    @Flag(name: .customLong("allow-specific-tags"), help: .hidden)
    var invalidAllowSpecificTags = false
    @Flag(name: .customLong("session-only"), help: .hidden)
    var invalidSessionOnly = false
    @Flag(name: .customLong("allow-session-subject-propagation"), help: .hidden)
    var invalidAllowSessionSubjectPropagation = false
    @Flag(name: .customLong("allow-session-habitat-propagation"), help: .hidden)
    var invalidAllowSessionHabitatPropagation = false
    @Flag(name: .customLong("allow-session-event-propagation"), help: .hidden)
    var invalidAllowSessionEventPropagation = false
    @Flag(name: .customLong("write-ai-json"), help: .hidden)
    var invalidWriteAIJSON = false
    @Flag(name: .customLong("no-write-ai-json"), help: .hidden)
    var invalidNoWriteAIJSON = false

    mutating func validate() throws {
        _ = try ApplySessionInvocationValidator.validate(invocationRequest)
    }

    mutating func run() async throws {
        let sessionPath = try ApplySessionInvocationValidator.validate(invocationRequest)
        let resolved = try ConfigurationResolver.resolveApplySession(cli: applyOverrides)
        let logger = Logger(minimumLevel: resolved.logLevel, format: resolved.logFormat)
        let interruptionMonitor = InterruptionMonitor()
        interruptionMonitor.installSignalHandlers()
        let result = try ApplySessionPipeline(
            xmpPipeline: XMPExportPipeline(
                engine: OwnedXMPSidecarEngine(),
                logger: logger
            )
        ).run(
            sessionPath: sessionPath,
            configuration: resolved,
            interruptionMonitor: interruptionMonitor
        )
        if resolved.dryRun {
            try writeChangePlan(result.changePlan)
            return
        }
        writeEssentialSummary(result.report)
    }

    private var invocationRequest: ApplySessionInvocationRequest {
        ApplySessionInvocationRequest(
            sessionPath: sessionPath,
            backupSidecars: backupSidecars,
            noBackupSidecars: noBackupSidecars,
            invalidNormalizationFlags: invalidFlags
        )
    }

    private var applyOverrides: ApplySessionConfigurationOverrides {
        ApplySessionConfigurationOverrides(
            outputDir: outputDir,
            configPath: config,
            logLevel: logLevel,
            logFormat: logFormat,
            dryRun: dryRun ? true : nil,
            sourceRoot: sourceRoot,
            sourceVerification: sourceVerification,
            backupSidecars: pairedFlag(positive: backupSidecars, negative: noBackupSidecars),
            xmpConflictPolicy: xmpConflictPolicy,
            allowStale: allowStale ? true : nil
        )
    }

    private var invalidFlags: [String] {
        var flags: [String] = []
        if invalidFromJSON != nil { flags.append("--from-json") }
        if invalidFileList != nil { flags.append("--file-list") }
        if invalidMode != nil { flags.append("--mode") }
        if invalidModel != nil { flags.append("--model") }
        if invalidModelEndpoint != nil { flags.append("--model-endpoint") }
        if invalidProfile != nil { flags.append("--profile") }
        if invalidMinConfidence != nil { flags.append("--min-confidence") }
        if invalidPairScope != nil { flags.append("--pair-scope") }
        if invalidNormalizationMode != nil { flags.append("--normalization-mode") }
        if invalidAffinityMode != nil { flags.append("--affinity-mode") }
        if invalidAffinityProfile != nil { flags.append("--affinity-profile") }
        if invalidMinAffinityForConsensus != nil { flags.append("--min-affinity-for-consensus") }
        if invalidConsensusThreshold != nil { flags.append("--consensus-threshold") }
        if invalidSessionSubject != nil { flags.append("--session-subject") }
        if invalidSessionHabitat != nil { flags.append("--session-habitat") }
        if invalidSessionEvent != nil { flags.append("--session-event") }
        if invalidUnknownPolicy != nil { flags.append("--unknown-session-context-policy") }
        if invalidAllowSpecificTags { flags.append("--allow-specific-tags") }
        if invalidSessionOnly { flags.append("--session-only") }
        if invalidAllowSessionSubjectPropagation { flags.append("--allow-session-subject-propagation") }
        if invalidAllowSessionHabitatPropagation { flags.append("--allow-session-habitat-propagation") }
        if invalidAllowSessionEventPropagation { flags.append("--allow-session-event-propagation") }
        if invalidWriteAIJSON { flags.append("--write-ai-json") }
        if invalidNoWriteAIJSON { flags.append("--no-write-ai-json") }
        return flags
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
        let line = "apply-session complete: \(written) written, \(failed) failed."
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
