import Foundation

/// Source identity handling for Phase 2 `write-xmp --from-json` inputs.
public enum XMPSourceVerificationPolicy: String, Codable, CaseIterable, Sendable {
    case fail
    case warn
    case skip
}

/// Existing-XMP handling for Phase 2 sidecar export.
public enum XMPConflictPolicy: String, Codable, CaseIterable, Sendable {
    case fail
    case merge
    case backupAndMerge = "backup-and-merge"
}

/// Existing-value handling for quality grading's managed XMP scalars.
public enum ScalarConflictPolicy: String, Codable, CaseIterable, Sendable {
    case preserve
    case refresh
    case overwrite
}

/// Ordinal minimum confidence threshold for candidate keyword export.
public enum XMPMinimumConfidence: String, Codable, CaseIterable, Comparable, Sendable {
    case low
    case medium
    case high

    private var sortOrder: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    public static func < (lhs: XMPMinimumConfidence, rhs: XMPMinimumConfidence) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Same-base-name source selection policy for shared XMP sidecars.
public enum XMPPairScope: String, Codable, CaseIterable, Sendable {
    case union
    case rawOnly = "raw-only"
    case jpegOnly = "jpeg-only"
}

/// Optional quality-grading values supplied at one configuration precedence layer.
///
/// Each field remains optional so an environment or CLI override for one knob does not
/// reset config-file maps or other independently resolved policy values.
public struct QualityGradingConfigurationOverrides: Sendable, Equatable {
    public var enabled: Bool?
    public var conflictPolicy: ScalarConflictPolicy?
    public var minimumConfidence: QualityAssessmentRecord.Confidence?
    public var writeRating: Bool?
    public var writeLabel: Bool?
    public var writeUrgency: Bool?
    public var writeKeywords: Bool?
    public var rejectAsMinusOne: Bool?
    public var perCriterionProblemKeywords: Bool?
    public var keywordRoot: String?
    public var ratingMap: [QualityTier: Int]?
    public var labelMap: [QualityTier: String]?
    public var urgencyMap: [QualityTier: Int]?

    public init(
        enabled: Bool? = nil,
        conflictPolicy: ScalarConflictPolicy? = nil,
        minimumConfidence: QualityAssessmentRecord.Confidence? = nil,
        writeRating: Bool? = nil,
        writeLabel: Bool? = nil,
        writeUrgency: Bool? = nil,
        writeKeywords: Bool? = nil,
        rejectAsMinusOne: Bool? = nil,
        perCriterionProblemKeywords: Bool? = nil,
        keywordRoot: String? = nil,
        ratingMap: [QualityTier: Int]? = nil,
        labelMap: [QualityTier: String]? = nil,
        urgencyMap: [QualityTier: Int]? = nil
    ) {
        self.enabled = enabled
        self.conflictPolicy = conflictPolicy
        self.minimumConfidence = minimumConfidence
        self.writeRating = writeRating
        self.writeLabel = writeLabel
        self.writeUrgency = writeUrgency
        self.writeKeywords = writeKeywords
        self.rejectAsMinusOne = rejectAsMinusOne
        self.perCriterionProblemKeywords = perCriterionProblemKeywords
        self.keywordRoot = keywordRoot
        self.ratingMap = ratingMap
        self.labelMap = labelMap
        self.urgencyMap = urgencyMap
    }
}

/// Fully resolved model-free grading settings used by the Phase 2 planner.
public struct ResolvedQualityGradingConfiguration: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var conflictPolicy: ScalarConflictPolicy
    public var policy: QualityGradingPolicy

    enum CodingKeys: String, CodingKey {
        case enabled
        case conflictPolicy = "conflict_policy"
        case policy
    }

    public init(
        enabled: Bool,
        conflictPolicy: ScalarConflictPolicy,
        policy: QualityGradingPolicy
    ) {
        self.enabled = enabled
        self.conflictPolicy = conflictPolicy
        self.policy = policy
    }

    public static let builtInDefaults = ResolvedQualityGradingConfiguration(
        enabled: false,
        conflictPolicy: .preserve,
        policy: .builtInDefaults
    )
}

/// Optional Phase 2 export values supplied before precedence is resolved.
///
/// This is intentionally separate from `RunConfigurationOverrides` so Phase 2
/// metadata-write defaults do not become Phase 1 raw-sidecar provenance.
public struct XMPExportConfigurationOverrides: Sendable, Equatable {
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
        self.qualityGrading = qualityGrading
    }
}

/// Fully resolved Phase 2 export configuration.
///
/// Values here follow PW-007 but are not recorded in Phase 1 raw sidecars.
public struct ResolvedXMPExportConfiguration: Codable, Sendable, Equatable {
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
        try container.encode(qualityGrading, forKey: .qualityGrading)
    }

    public static let builtInDefaults = ResolvedXMPExportConfiguration(
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
        qualityGrading: .builtInDefaults
    )
}

/// Input mode selected after Phase 2 CLI shape validation.
public enum XMPExportInvocationMode: Sendable, Equatable {
    case fromJSON(path: String)
    case analyzeAndWrite(inputPath: String)
}

/// Explicit `write-xmp` invocation shape before config-file defaults are applied.
///
/// Boolean pairs are kept as separate explicit flags so validation can reject
/// contradictory CLI input before converting them into optional overrides.
public struct XMPExportInvocationRequest: Sendable, Equatable {
    public var inputPath: String?
    public var fromJSONPath: String?
    public var sourceRoot: String?
    public var sourceVerification: XMPSourceVerificationPolicy?
    public var mode: AnalysisMode?
    public var existing: ExistingPolicy?
    public var assessQuality: Bool
    public var model: String?
    public var modelEndpoint: String?
    public var modelTimeoutSeconds: Double?
    public var modelRetryLimit: Int?
    public var profile: String?
    public var debugDerivatives: Bool
    public var clearDerivativeCacheOnStart: Bool
    public var clearDerivativeCacheAfterSuccess: Bool
    public var stageConcurrency: Int?
    public var modelResponseRepairAttempts: Int?
    public var gpsContext: GPSContextMode?
    public var qualityGrading: Bool
    public var qualityConflicts: ScalarConflictPolicy?
    public var qualityMinConfidence: XMPMinimumConfidence?
    public var writeFlatKeywords: Bool
    public var noWriteFlatKeywords: Bool
    public var writeHierarchicalKeywords: Bool
    public var noWriteHierarchicalKeywords: Bool
    public var writeRating: Bool
    public var noWriteRating: Bool
    public var writeLabel: Bool
    public var noWriteLabel: Bool
    public var writeUrgency: Bool
    public var noWriteUrgency: Bool
    public var writeQualityKeywords: Bool
    public var noWriteQualityKeywords: Bool
    public var backupSidecars: Bool
    public var noBackupSidecars: Bool
    public var writeAIJSON: Bool
    public var noWriteAIJSON: Bool

    public init(
        inputPath: String? = nil,
        fromJSONPath: String? = nil,
        sourceRoot: String? = nil,
        sourceVerification: XMPSourceVerificationPolicy? = nil,
        mode: AnalysisMode? = nil,
        existing: ExistingPolicy? = nil,
        assessQuality: Bool = false,
        model: String? = nil,
        modelEndpoint: String? = nil,
        modelTimeoutSeconds: Double? = nil,
        modelRetryLimit: Int? = nil,
        profile: String? = nil,
        debugDerivatives: Bool = false,
        clearDerivativeCacheOnStart: Bool = false,
        clearDerivativeCacheAfterSuccess: Bool = false,
        stageConcurrency: Int? = nil,
        modelResponseRepairAttempts: Int? = nil,
        gpsContext: GPSContextMode? = nil,
        qualityGrading: Bool = false,
        qualityConflicts: ScalarConflictPolicy? = nil,
        qualityMinConfidence: XMPMinimumConfidence? = nil,
        writeFlatKeywords: Bool = false,
        noWriteFlatKeywords: Bool = false,
        writeHierarchicalKeywords: Bool = false,
        noWriteHierarchicalKeywords: Bool = false,
        writeRating: Bool = false,
        noWriteRating: Bool = false,
        writeLabel: Bool = false,
        noWriteLabel: Bool = false,
        writeUrgency: Bool = false,
        noWriteUrgency: Bool = false,
        writeQualityKeywords: Bool = false,
        noWriteQualityKeywords: Bool = false,
        backupSidecars: Bool = false,
        noBackupSidecars: Bool = false,
        writeAIJSON: Bool = false,
        noWriteAIJSON: Bool = false
    ) {
        self.inputPath = inputPath
        self.fromJSONPath = fromJSONPath
        self.sourceRoot = sourceRoot
        self.sourceVerification = sourceVerification
        self.mode = mode
        self.existing = existing
        self.assessQuality = assessQuality
        self.model = model
        self.modelEndpoint = modelEndpoint
        self.modelTimeoutSeconds = modelTimeoutSeconds
        self.modelRetryLimit = modelRetryLimit
        self.profile = profile
        self.debugDerivatives = debugDerivatives
        self.clearDerivativeCacheOnStart = clearDerivativeCacheOnStart
        self.clearDerivativeCacheAfterSuccess = clearDerivativeCacheAfterSuccess
        self.stageConcurrency = stageConcurrency
        self.modelResponseRepairAttempts = modelResponseRepairAttempts
        self.gpsContext = gpsContext
        self.qualityGrading = qualityGrading
        self.qualityConflicts = qualityConflicts
        self.qualityMinConfidence = qualityMinConfidence
        self.writeFlatKeywords = writeFlatKeywords
        self.noWriteFlatKeywords = noWriteFlatKeywords
        self.writeHierarchicalKeywords = writeHierarchicalKeywords
        self.noWriteHierarchicalKeywords = noWriteHierarchicalKeywords
        self.writeRating = writeRating
        self.noWriteRating = noWriteRating
        self.writeLabel = writeLabel
        self.noWriteLabel = noWriteLabel
        self.writeUrgency = writeUrgency
        self.noWriteUrgency = noWriteUrgency
        self.writeQualityKeywords = writeQualityKeywords
        self.noWriteQualityKeywords = noWriteQualityKeywords
        self.backupSidecars = backupSidecars
        self.noBackupSidecars = noBackupSidecars
        self.writeAIJSON = writeAIJSON
        self.noWriteAIJSON = noWriteAIJSON
    }
}

/// Requirement-level validation for the Phase 2 CLI scaffold.
public enum XMPExportInvocationValidator {
    public static func validate(_ request: XMPExportInvocationRequest) throws -> XMPExportInvocationMode {
        try rejectConflictingBooleanPairs(request)

        let inputPath = InvocationRules.normalizedPath(request.inputPath)
        let fromJSONPath = InvocationRules.normalizedPath(request.fromJSONPath)
        switch (inputPath, fromJSONPath) {
        case (.some(let inputPath), .none):
            try validateAnalyzeAndWriteOnlyOptions(request)
            return .analyzeAndWrite(inputPath: inputPath)
        case (.none, .some(let fromJSONPath)):
            try validateFromJSONOnlyOptions(request)
            return .fromJSON(path: fromJSONPath)
        case (.some, .some):
            throw SidecarError.configInvalid("--from-json and positional image input are mutually exclusive.")
        case (.none, .none):
            throw SidecarError.configInvalid("write-xmp requires either an image input path or --from-json.")
        }
    }

    private static func rejectConflictingBooleanPairs(_ request: XMPExportInvocationRequest) throws {
        try InvocationRules.rejectConflictingFlag(
            "write-flat-keywords", enabled: request.writeFlatKeywords, disabled: request.noWriteFlatKeywords
        )
        try InvocationRules.rejectConflictingFlag(
            "write-hierarchical-keywords",
            enabled: request.writeHierarchicalKeywords,
            disabled: request.noWriteHierarchicalKeywords
        )
        try InvocationRules.rejectConflictingFlag(
            "write-rating", enabled: request.writeRating, disabled: request.noWriteRating
        )
        try InvocationRules.rejectConflictingFlag(
            "write-label", enabled: request.writeLabel, disabled: request.noWriteLabel
        )
        try InvocationRules.rejectConflictingFlag(
            "write-urgency", enabled: request.writeUrgency, disabled: request.noWriteUrgency
        )
        try InvocationRules.rejectConflictingFlag(
            "write-quality-keywords",
            enabled: request.writeQualityKeywords,
            disabled: request.noWriteQualityKeywords
        )
        try InvocationRules.rejectConflictingFlag(
            "backup-sidecars", enabled: request.backupSidecars, disabled: request.noBackupSidecars
        )
        try InvocationRules.rejectConflictingFlag(
            "write-ai-json", enabled: request.writeAIJSON, disabled: request.noWriteAIJSON
        )
    }

    private static func validateAnalyzeAndWriteOnlyOptions(_ request: XMPExportInvocationRequest) throws {
        if request.sourceRoot != nil {
            throw SidecarError.configInvalid("--source-root is valid only with --from-json.")
        }
        if request.sourceVerification != nil {
            throw SidecarError.configInvalid("--source-verification is valid only with --from-json.")
        }
    }

    private static func validateFromJSONOnlyOptions(_ request: XMPExportInvocationRequest) throws {
        try InvocationRules.rejectFromJSONIncompatible([
            ("mode", request.mode != nil),
            ("existing", request.existing != nil),
            ("assess-quality", request.assessQuality),
            ("model", request.model != nil),
            ("model-endpoint", request.modelEndpoint != nil),
            ("model-timeout", request.modelTimeoutSeconds != nil),
            ("model-retry-limit", request.modelRetryLimit != nil),
            ("profile", request.profile != nil),
            ("debug-derivatives", request.debugDerivatives),
            ("clear-derivative-cache-on-start", request.clearDerivativeCacheOnStart),
            ("clear-derivative-cache-after-success", request.clearDerivativeCacheAfterSuccess),
            ("stage-concurrency", request.stageConcurrency != nil),
            ("model-response-repair-attempts", request.modelResponseRepairAttempts != nil),
            ("gps-context", request.gpsContext != nil),
        ])
        if request.writeAIJSON || request.noWriteAIJSON {
            throw SidecarError.configInvalid("--write-ai-json is valid only with analyze-and-write mode.")
        }
    }
}
