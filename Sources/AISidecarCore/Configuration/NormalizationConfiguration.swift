import Foundation

/// Phase 3 normalization policy selected for a run.
public enum NormalizationMode: String, Codable, CaseIterable, Sendable {
    case off
    case singleImage = "single-image"
    case batchConservative = "batch-conservative"
}

/// Batch-affinity strategy used before cross-image propagation.
public enum NormalizationAffinityMode: String, Codable, CaseIterable, Sendable {
    case off
    case metadataWeighted = "metadata-weighted"
}

/// Named metadata-affinity preset exposed by the CLI.
public enum NormalizationAffinityProfile: String, Codable, CaseIterable, Sendable {
    case conservative
    case balanced
    case aggressive
}

/// Policy for user-supplied session context that does not match the vocabulary.
public enum UnknownSessionContextPolicy: String, Codable, CaseIterable, Sendable {
    case reject
    case writeUnnormalized = "write-unnormalized"
}

/// Persistence policy for sensitive affinity inputs such as exact GPS and serials.
public enum AffinityPrivacyMode: String, Codable, CaseIterable, Sendable {
    case standard
    case debugExact = "debug-exact"
}

/// Optional Phase 3 normalization values supplied before precedence is resolved.
public struct NormalizationConfigurationOverrides: Sendable, Equatable {
    public var recursive: Bool?
    public var outputDir: String?
    public var configPath: String?
    public var logLevel: LogLevel?
    public var logFormat: LogFormat?
    public var dryRun: Bool?
    public var sourceRoot: String?
    public var sourceVerification: XMPSourceVerificationPolicy?
    public var writeFlatKeywords: Bool?
    public var writeHierarchicalKeywords: Bool?
    public var backupSidecars: Bool?
    public var xmpConflictPolicy: XMPConflictPolicy?
    public var minConfidence: XMPMinimumConfidence?
    public var allowSpecificTags: Bool?
    public var pairScope: XMPPairScope?
    public var writeAIJSON: Bool?
    public var vocabularyPath: String?
    public var normalizationMode: NormalizationMode?
    public var sessionSubject: String?
    public var sessionHabitat: String?
    public var sessionEvent: String?
    public var consensusThreshold: Double?
    public var affinityMode: NormalizationAffinityMode?
    public var affinityProfile: NormalizationAffinityProfile?
    public var minAffinityForConsensus: Double?
    public var sessionOnly: Bool?
    public var unknownSessionContextPolicy: UnknownSessionContextPolicy?
    public var allowSessionSubjectPropagation: Bool?
    public var allowSessionHabitatPropagation: Bool?
    public var allowSessionEventPropagation: Bool?
    public var affinityPrivacyMode: AffinityPrivacyMode?
    public var writeReportPath: String?

    public init(
        recursive: Bool? = nil,
        outputDir: String? = nil,
        configPath: String? = nil,
        logLevel: LogLevel? = nil,
        logFormat: LogFormat? = nil,
        dryRun: Bool? = nil,
        sourceRoot: String? = nil,
        sourceVerification: XMPSourceVerificationPolicy? = nil,
        writeFlatKeywords: Bool? = nil,
        writeHierarchicalKeywords: Bool? = nil,
        backupSidecars: Bool? = nil,
        xmpConflictPolicy: XMPConflictPolicy? = nil,
        minConfidence: XMPMinimumConfidence? = nil,
        allowSpecificTags: Bool? = nil,
        pairScope: XMPPairScope? = nil,
        writeAIJSON: Bool? = nil,
        vocabularyPath: String? = nil,
        normalizationMode: NormalizationMode? = nil,
        sessionSubject: String? = nil,
        sessionHabitat: String? = nil,
        sessionEvent: String? = nil,
        consensusThreshold: Double? = nil,
        affinityMode: NormalizationAffinityMode? = nil,
        affinityProfile: NormalizationAffinityProfile? = nil,
        minAffinityForConsensus: Double? = nil,
        sessionOnly: Bool? = nil,
        unknownSessionContextPolicy: UnknownSessionContextPolicy? = nil,
        allowSessionSubjectPropagation: Bool? = nil,
        allowSessionHabitatPropagation: Bool? = nil,
        allowSessionEventPropagation: Bool? = nil,
        affinityPrivacyMode: AffinityPrivacyMode? = nil,
        writeReportPath: String? = nil
    ) {
        self.recursive = recursive
        self.outputDir = outputDir
        self.configPath = configPath
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.sourceRoot = sourceRoot
        self.sourceVerification = sourceVerification
        self.writeFlatKeywords = writeFlatKeywords
        self.writeHierarchicalKeywords = writeHierarchicalKeywords
        self.backupSidecars = backupSidecars
        self.xmpConflictPolicy = xmpConflictPolicy
        self.minConfidence = minConfidence
        self.allowSpecificTags = allowSpecificTags
        self.pairScope = pairScope
        self.writeAIJSON = writeAIJSON
        self.vocabularyPath = vocabularyPath
        self.normalizationMode = normalizationMode
        self.sessionSubject = sessionSubject
        self.sessionHabitat = sessionHabitat
        self.sessionEvent = sessionEvent
        self.consensusThreshold = consensusThreshold
        self.affinityMode = affinityMode
        self.affinityProfile = affinityProfile
        self.minAffinityForConsensus = minAffinityForConsensus
        self.sessionOnly = sessionOnly
        self.unknownSessionContextPolicy = unknownSessionContextPolicy
        self.allowSessionSubjectPropagation = allowSessionSubjectPropagation
        self.allowSessionHabitatPropagation = allowSessionHabitatPropagation
        self.allowSessionEventPropagation = allowSessionEventPropagation
        self.affinityPrivacyMode = affinityPrivacyMode
        self.writeReportPath = writeReportPath
    }
}

/// Fully resolved Phase 3 normalization configuration.
public struct ResolvedNormalizationConfiguration: Codable, Sendable, Equatable {
    public var recursive: Bool
    public var outputDir: String?
    public var logLevel: LogLevel
    public var logFormat: LogFormat
    public var dryRun: Bool
    public var sourceRoot: String?
    public var sourceVerification: XMPSourceVerificationPolicy
    public var writeFlatKeywords: Bool
    public var writeHierarchicalKeywords: Bool
    public var backupSidecars: Bool
    public var xmpConflictPolicy: XMPConflictPolicy
    public var minConfidence: XMPMinimumConfidence
    public var allowSpecificTags: Bool
    public var pairScope: XMPPairScope
    public var writeAIJSON: Bool
    public var vocabularyPath: String?
    public var normalizationMode: NormalizationMode
    public var sessionSubject: String?
    public var sessionHabitat: String?
    public var sessionEvent: String?
    public var consensusThreshold: Double
    public var affinityMode: NormalizationAffinityMode
    public var affinityProfile: NormalizationAffinityProfile
    public var minAffinityForConsensus: Double
    public var sessionOnly: Bool
    public var unknownSessionContextPolicy: UnknownSessionContextPolicy
    public var allowSessionSubjectPropagation: Bool
    public var allowSessionHabitatPropagation: Bool
    public var allowSessionEventPropagation: Bool
    public var affinityPrivacyMode: AffinityPrivacyMode
    public var writeReportPath: String?

    enum CodingKeys: String, CodingKey {
        case recursive
        case outputDir = "output_dir"
        case logLevel = "log_level"
        case logFormat = "log_format"
        case dryRun = "dry_run"
        case sourceRoot = "source_root"
        case sourceVerification = "source_verification"
        case writeFlatKeywords = "write_flat_keywords"
        case writeHierarchicalKeywords = "write_hierarchical_keywords"
        case backupSidecars = "backup_sidecars"
        case xmpConflictPolicy = "xmp_conflict_policy"
        case minConfidence = "min_confidence"
        case allowSpecificTags = "allow_specific_tags"
        case pairScope = "pair_scope"
        case writeAIJSON = "write_ai_json"
        case vocabularyPath = "vocabulary_path"
        case normalizationMode = "normalization_mode"
        case sessionSubject = "session_subject"
        case sessionHabitat = "session_habitat"
        case sessionEvent = "session_event"
        case consensusThreshold = "consensus_threshold"
        case affinityMode = "affinity_mode"
        case affinityProfile = "affinity_profile"
        case minAffinityForConsensus = "min_affinity_for_consensus"
        case sessionOnly = "session_only"
        case unknownSessionContextPolicy = "unknown_session_context_policy"
        case allowSessionSubjectPropagation = "allow_session_subject_propagation"
        case allowSessionHabitatPropagation = "allow_session_habitat_propagation"
        case allowSessionEventPropagation = "allow_session_event_propagation"
        case affinityPrivacyMode = "affinity_privacy_mode"
        case writeReportPath = "write_report_path"
    }

    public init(
        recursive: Bool,
        outputDir: String?,
        logLevel: LogLevel,
        logFormat: LogFormat,
        dryRun: Bool,
        sourceRoot: String?,
        sourceVerification: XMPSourceVerificationPolicy,
        writeFlatKeywords: Bool,
        writeHierarchicalKeywords: Bool,
        backupSidecars: Bool,
        xmpConflictPolicy: XMPConflictPolicy,
        minConfidence: XMPMinimumConfidence,
        allowSpecificTags: Bool,
        pairScope: XMPPairScope,
        writeAIJSON: Bool,
        vocabularyPath: String?,
        normalizationMode: NormalizationMode,
        sessionSubject: String?,
        sessionHabitat: String?,
        sessionEvent: String?,
        consensusThreshold: Double,
        affinityMode: NormalizationAffinityMode,
        affinityProfile: NormalizationAffinityProfile,
        minAffinityForConsensus: Double,
        sessionOnly: Bool,
        unknownSessionContextPolicy: UnknownSessionContextPolicy,
        allowSessionSubjectPropagation: Bool,
        allowSessionHabitatPropagation: Bool,
        allowSessionEventPropagation: Bool,
        affinityPrivacyMode: AffinityPrivacyMode,
        writeReportPath: String?
    ) {
        self.recursive = recursive
        self.outputDir = outputDir
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.sourceRoot = sourceRoot
        self.sourceVerification = sourceVerification
        self.writeFlatKeywords = writeFlatKeywords
        self.writeHierarchicalKeywords = writeHierarchicalKeywords
        self.backupSidecars = backupSidecars
        self.xmpConflictPolicy = xmpConflictPolicy
        self.minConfidence = minConfidence
        self.allowSpecificTags = allowSpecificTags
        self.pairScope = pairScope
        self.writeAIJSON = writeAIJSON
        self.vocabularyPath = vocabularyPath
        self.normalizationMode = normalizationMode
        self.sessionSubject = sessionSubject
        self.sessionHabitat = sessionHabitat
        self.sessionEvent = sessionEvent
        self.consensusThreshold = consensusThreshold
        self.affinityMode = affinityMode
        self.affinityProfile = affinityProfile
        self.minAffinityForConsensus = minAffinityForConsensus
        self.sessionOnly = sessionOnly
        self.unknownSessionContextPolicy = unknownSessionContextPolicy
        self.allowSessionSubjectPropagation = allowSessionSubjectPropagation
        self.allowSessionHabitatPropagation = allowSessionHabitatPropagation
        self.allowSessionEventPropagation = allowSessionEventPropagation
        self.affinityPrivacyMode = affinityPrivacyMode
        self.writeReportPath = writeReportPath
    }

    public static let builtInDefaults = ResolvedNormalizationConfiguration(
        recursive: false,
        outputDir: nil,
        logLevel: .info,
        logFormat: .text,
        dryRun: false,
        sourceRoot: nil,
        sourceVerification: .fail,
        writeFlatKeywords: true,
        writeHierarchicalKeywords: true,
        backupSidecars: true,
        xmpConflictPolicy: .backupAndMerge,
        minConfidence: .medium,
        allowSpecificTags: false,
        pairScope: .union,
        writeAIJSON: true,
        vocabularyPath: nil,
        normalizationMode: .batchConservative,
        sessionSubject: nil,
        sessionHabitat: nil,
        sessionEvent: nil,
        consensusThreshold: 0.6,
        affinityMode: .metadataWeighted,
        affinityProfile: .conservative,
        minAffinityForConsensus: 0.35,
        sessionOnly: false,
        unknownSessionContextPolicy: .reject,
        allowSessionSubjectPropagation: false,
        allowSessionHabitatPropagation: false,
        allowSessionEventPropagation: false,
        affinityPrivacyMode: .standard,
        writeReportPath: nil
    )
}

/// Optional `apply-session` values supplied before precedence is resolved.
public struct ApplySessionConfigurationOverrides: Sendable, Equatable {
    public var outputDir: String?
    public var configPath: String?
    public var logLevel: LogLevel?
    public var logFormat: LogFormat?
    public var dryRun: Bool?
    public var sourceRoot: String?
    public var sourceVerification: XMPSourceVerificationPolicy?
    public var backupSidecars: Bool?
    public var xmpConflictPolicy: XMPConflictPolicy?
    public var allowStale: Bool?

    public init(
        outputDir: String? = nil,
        configPath: String? = nil,
        logLevel: LogLevel? = nil,
        logFormat: LogFormat? = nil,
        dryRun: Bool? = nil,
        sourceRoot: String? = nil,
        sourceVerification: XMPSourceVerificationPolicy? = nil,
        backupSidecars: Bool? = nil,
        xmpConflictPolicy: XMPConflictPolicy? = nil,
        allowStale: Bool? = nil
    ) {
        self.outputDir = outputDir
        self.configPath = configPath
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.sourceRoot = sourceRoot
        self.sourceVerification = sourceVerification
        self.backupSidecars = backupSidecars
        self.xmpConflictPolicy = xmpConflictPolicy
        self.allowStale = allowStale
    }
}

/// Resolved write-safety settings for model-free `apply-session` runs.
public struct ResolvedApplySessionConfiguration: Codable, Sendable, Equatable {
    public var outputDir: String?
    public var logLevel: LogLevel
    public var logFormat: LogFormat
    public var dryRun: Bool
    public var sourceRoot: String?
    public var sourceVerification: XMPSourceVerificationPolicy
    public var backupSidecars: Bool
    public var xmpConflictPolicy: XMPConflictPolicy
    public var allowStale: Bool

    enum CodingKeys: String, CodingKey {
        case outputDir = "output_dir"
        case logLevel = "log_level"
        case logFormat = "log_format"
        case dryRun = "dry_run"
        case sourceRoot = "source_root"
        case sourceVerification = "source_verification"
        case backupSidecars = "backup_sidecars"
        case xmpConflictPolicy = "xmp_conflict_policy"
        case allowStale = "allow_stale"
    }

    public init(
        outputDir: String?,
        logLevel: LogLevel,
        logFormat: LogFormat,
        dryRun: Bool,
        sourceRoot: String?,
        sourceVerification: XMPSourceVerificationPolicy,
        backupSidecars: Bool,
        xmpConflictPolicy: XMPConflictPolicy,
        allowStale: Bool
    ) {
        self.outputDir = outputDir
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.sourceRoot = sourceRoot
        self.sourceVerification = sourceVerification
        self.backupSidecars = backupSidecars
        self.xmpConflictPolicy = xmpConflictPolicy
        self.allowStale = allowStale
    }

    public static let builtInDefaults = ResolvedApplySessionConfiguration(
        outputDir: nil,
        logLevel: .info,
        logFormat: .text,
        dryRun: false,
        sourceRoot: nil,
        sourceVerification: .fail,
        backupSidecars: true,
        xmpConflictPolicy: .backupAndMerge,
        allowStale: false
    )
}
