import Foundation

/// Phase 3 normalization policy selected for a run.
public enum NormalizationMode: String, Codable, CaseIterable, Sendable {
    case off
    case singleImage = "single-image"
    case batchConservative = "batch-conservative"
}

/// Source of terms used by Phase 3 normalization.
public enum NormalizationVocabularyMode: String, Codable, CaseIterable, Sendable {
    case observedTags = "observed-tags"
    case controlledVocabulary = "controlled-vocabulary"
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
    public var vocabularyMode: NormalizationVocabularyMode?
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
    public var qualityGrading: QualityGradingConfigurationOverrides

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
        vocabularyMode: NormalizationVocabularyMode? = nil,
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
        writeReportPath: String? = nil,
        qualityGrading: QualityGradingConfigurationOverrides = QualityGradingConfigurationOverrides()
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
        self.vocabularyMode = vocabularyMode
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
        self.qualityGrading = qualityGrading
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
    public var vocabularyMode: NormalizationVocabularyMode
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
    public var qualityGrading: ResolvedQualityGradingConfiguration

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
        case vocabularyMode = "vocabulary_mode"
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
        case qualityGrading = "quality_grading"
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
        vocabularyMode: NormalizationVocabularyMode,
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
        writeReportPath: String?,
        qualityGrading: ResolvedQualityGradingConfiguration = .builtInDefaults
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
        self.vocabularyMode = vocabularyMode
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
        self.qualityGrading = qualityGrading
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recursive = try container.decode(Bool.self, forKey: .recursive)
        outputDir = try container.decodeIfPresent(String.self, forKey: .outputDir)
        logLevel = try container.decode(LogLevel.self, forKey: .logLevel)
        logFormat = try container.decode(LogFormat.self, forKey: .logFormat)
        dryRun = try container.decode(Bool.self, forKey: .dryRun)
        sourceRoot = try container.decodeIfPresent(String.self, forKey: .sourceRoot)
        sourceVerification = try container.decode(XMPSourceVerificationPolicy.self, forKey: .sourceVerification)
        writeFlatKeywords = try container.decode(Bool.self, forKey: .writeFlatKeywords)
        writeHierarchicalKeywords = try container.decode(Bool.self, forKey: .writeHierarchicalKeywords)
        backupSidecars = try container.decode(Bool.self, forKey: .backupSidecars)
        xmpConflictPolicy = try container.decode(XMPConflictPolicy.self, forKey: .xmpConflictPolicy)
        minConfidence = try container.decode(XMPMinimumConfidence.self, forKey: .minConfidence)
        allowSpecificTags = try container.decode(Bool.self, forKey: .allowSpecificTags)
        pairScope = try container.decode(XMPPairScope.self, forKey: .pairScope)
        writeAIJSON = try container.decode(Bool.self, forKey: .writeAIJSON)
        vocabularyPath = try container.decodeIfPresent(String.self, forKey: .vocabularyPath)
        vocabularyMode = try container.decode(NormalizationVocabularyMode.self, forKey: .vocabularyMode)
        normalizationMode = try container.decode(NormalizationMode.self, forKey: .normalizationMode)
        sessionSubject = try container.decodeIfPresent(String.self, forKey: .sessionSubject)
        sessionHabitat = try container.decodeIfPresent(String.self, forKey: .sessionHabitat)
        sessionEvent = try container.decodeIfPresent(String.self, forKey: .sessionEvent)
        consensusThreshold = try container.decode(Double.self, forKey: .consensusThreshold)
        affinityMode = try container.decode(NormalizationAffinityMode.self, forKey: .affinityMode)
        affinityProfile = try container.decode(NormalizationAffinityProfile.self, forKey: .affinityProfile)
        minAffinityForConsensus = try container.decode(Double.self, forKey: .minAffinityForConsensus)
        sessionOnly = try container.decode(Bool.self, forKey: .sessionOnly)
        unknownSessionContextPolicy = try container.decode(
            UnknownSessionContextPolicy.self,
            forKey: .unknownSessionContextPolicy
        )
        allowSessionSubjectPropagation = try container.decode(Bool.self, forKey: .allowSessionSubjectPropagation)
        allowSessionHabitatPropagation = try container.decode(Bool.self, forKey: .allowSessionHabitatPropagation)
        allowSessionEventPropagation = try container.decode(Bool.self, forKey: .allowSessionEventPropagation)
        affinityPrivacyMode = try container.decode(AffinityPrivacyMode.self, forKey: .affinityPrivacyMode)
        writeReportPath = try container.decodeIfPresent(String.self, forKey: .writeReportPath)
        qualityGrading =
            try container.decodeIfPresent(ResolvedQualityGradingConfiguration.self, forKey: .qualityGrading)
            ?? .builtInDefaults
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recursive, forKey: .recursive)
        try container.encodeIfPresent(outputDir, forKey: .outputDir)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(logFormat, forKey: .logFormat)
        try container.encode(dryRun, forKey: .dryRun)
        try container.encodeIfPresent(sourceRoot, forKey: .sourceRoot)
        try container.encode(sourceVerification, forKey: .sourceVerification)
        try container.encode(writeFlatKeywords, forKey: .writeFlatKeywords)
        try container.encode(writeHierarchicalKeywords, forKey: .writeHierarchicalKeywords)
        try container.encode(backupSidecars, forKey: .backupSidecars)
        try container.encode(xmpConflictPolicy, forKey: .xmpConflictPolicy)
        try container.encode(minConfidence, forKey: .minConfidence)
        try container.encode(allowSpecificTags, forKey: .allowSpecificTags)
        try container.encode(pairScope, forKey: .pairScope)
        try container.encode(writeAIJSON, forKey: .writeAIJSON)
        try container.encodeIfPresent(vocabularyPath, forKey: .vocabularyPath)
        try container.encode(vocabularyMode, forKey: .vocabularyMode)
        try container.encode(normalizationMode, forKey: .normalizationMode)
        try container.encodeIfPresent(sessionSubject, forKey: .sessionSubject)
        try container.encodeIfPresent(sessionHabitat, forKey: .sessionHabitat)
        try container.encodeIfPresent(sessionEvent, forKey: .sessionEvent)
        try container.encode(consensusThreshold, forKey: .consensusThreshold)
        try container.encode(affinityMode, forKey: .affinityMode)
        try container.encode(affinityProfile, forKey: .affinityProfile)
        try container.encode(minAffinityForConsensus, forKey: .minAffinityForConsensus)
        try container.encode(sessionOnly, forKey: .sessionOnly)
        try container.encode(unknownSessionContextPolicy, forKey: .unknownSessionContextPolicy)
        try container.encode(allowSessionSubjectPropagation, forKey: .allowSessionSubjectPropagation)
        try container.encode(allowSessionHabitatPropagation, forKey: .allowSessionHabitatPropagation)
        try container.encode(allowSessionEventPropagation, forKey: .allowSessionEventPropagation)
        try container.encode(affinityPrivacyMode, forKey: .affinityPrivacyMode)
        try container.encodeIfPresent(writeReportPath, forKey: .writeReportPath)
        if qualityGrading != .builtInDefaults {
            try container.encode(qualityGrading, forKey: .qualityGrading)
        }
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
        vocabularyMode: .observedTags,
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
        writeReportPath: nil,
        qualityGrading: .builtInDefaults
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
