import Foundation

/// JSON-backed persistent defaults loaded before environment and CLI overrides.
public struct AppConfig: Codable, Sendable, Equatable {
    public var mode: AnalysisMode?
    public var existing: ExistingPolicy?
    public var recursive: Bool?
    public var outputDir: String?
    public var model: String?
    public var modelEndpoint: String?
    public var modelKeepAlive: String?
    public var profile: String?
    public var logLevel: LogLevel?
    public var logFormat: LogFormat?
    public var dryRun: Bool?
    public var debugDerivatives: Bool?
    public var sourceIdentityPolicy: SourceIdentityPolicy?
    public var derivativeCacheDir: String?
    public var derivativeCacheSizeBytes: Int64?
    public var clearDerivativeCacheOnStart: Bool?
    public var clearDerivativeCacheAfterSuccess: Bool?
    public var subjectCropMarginFraction: Double?
    public var subjectMergeDominanceThreshold: Double?
    /// Bounded render/isolation worker count; model calls remain serialized.
    public var stageConcurrency: Int?
    /// Bounded model-output repair attempts after invalid JSON or schema failure.
    public var modelResponseRepairAttempts: Int?
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode
        case existing
        case recursive
        case outputDir = "output_dir"
        case model
        case modelEndpoint = "model_endpoint"
        case modelKeepAlive = "model_keep_alive"
        case profile
        case logLevel = "log_level"
        case logFormat = "log_format"
        case dryRun = "dry_run"
        case debugDerivatives = "debug_derivatives"
        case sourceIdentityPolicy = "source_identity_policy"
        case derivativeCacheDir = "derivative_cache_dir"
        case derivativeCacheSizeBytes = "derivative_cache_size_bytes"
        case clearDerivativeCacheOnStart = "clear_derivative_cache_on_start"
        case clearDerivativeCacheAfterSuccess = "clear_derivative_cache_after_success"
        case subjectCropMarginFraction = "subject_crop_margin_fraction"
        case subjectMergeDominanceThreshold = "subject_merge_dominance_threshold"
        case stageConcurrency = "stage_concurrency"
        case modelResponseRepairAttempts = "model_response_repair_attempts"
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
    }

    public init(
        mode: AnalysisMode? = nil,
        existing: ExistingPolicy? = nil,
        recursive: Bool? = nil,
        outputDir: String? = nil,
        model: String? = nil,
        modelEndpoint: String? = nil,
        modelKeepAlive: String? = nil,
        profile: String? = nil,
        logLevel: LogLevel? = nil,
        logFormat: LogFormat? = nil,
        dryRun: Bool? = nil,
        debugDerivatives: Bool? = nil,
        sourceIdentityPolicy: SourceIdentityPolicy? = nil,
        derivativeCacheDir: String? = nil,
        derivativeCacheSizeBytes: Int64? = nil,
        clearDerivativeCacheOnStart: Bool? = nil,
        clearDerivativeCacheAfterSuccess: Bool? = nil,
        subjectCropMarginFraction: Double? = nil,
        subjectMergeDominanceThreshold: Double? = nil,
        stageConcurrency: Int? = nil,
        modelResponseRepairAttempts: Int? = nil,
        sourceRoot: String? = nil,
        sourceVerification: XMPSourceVerificationPolicy? = nil,
        writeFlatKeywords: Bool? = nil,
        writeHierarchicalKeywords: Bool? = nil,
        backupSidecars: Bool? = nil,
        xmpConflictPolicy: XMPConflictPolicy? = nil,
        minConfidence: XMPMinimumConfidence? = nil,
        allowSpecificTags: Bool? = nil,
        pairScope: XMPPairScope? = nil,
        writeAIJSON: Bool? = nil
    ) {
        self.mode = mode
        self.existing = existing
        self.recursive = recursive
        self.outputDir = outputDir
        self.model = model
        self.modelEndpoint = modelEndpoint
        self.modelKeepAlive = modelKeepAlive
        self.profile = profile
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.debugDerivatives = debugDerivatives
        self.sourceIdentityPolicy = sourceIdentityPolicy
        self.derivativeCacheDir = derivativeCacheDir
        self.derivativeCacheSizeBytes = derivativeCacheSizeBytes
        self.clearDerivativeCacheOnStart = clearDerivativeCacheOnStart
        self.clearDerivativeCacheAfterSuccess = clearDerivativeCacheAfterSuccess
        self.subjectCropMarginFraction = subjectCropMarginFraction
        self.subjectMergeDominanceThreshold = subjectMergeDominanceThreshold
        self.stageConcurrency = stageConcurrency
        self.modelResponseRepairAttempts = modelResponseRepairAttempts
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
    }

    public init(from decoder: Decoder) throws {
        let allKeys = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedKeys = Set(CodingKeys.allCases.map(\.stringValue))
        let unknownKeys = allKeys.allKeys
            .map(\.stringValue)
            .filter { !allowedKeys.contains($0) }
            .sorted()
        // Unknown keys are rejected so typos in persistent defaults cannot
        // silently change later batch behavior.
        guard unknownKeys.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown config keys: \(unknownKeys.joined(separator: ", "))"
                )
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decodeIfPresent(AnalysisMode.self, forKey: .mode)
        self.existing = try container.decodeIfPresent(ExistingPolicy.self, forKey: .existing)
        self.recursive = try container.decodeIfPresent(Bool.self, forKey: .recursive)
        self.outputDir = try container.decodeIfPresent(String.self, forKey: .outputDir)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.modelEndpoint = try container.decodeIfPresent(String.self, forKey: .modelEndpoint)
        self.modelKeepAlive = try container.decodeIfPresent(String.self, forKey: .modelKeepAlive)
        self.profile = try container.decodeIfPresent(String.self, forKey: .profile)
        self.logLevel = try container.decodeIfPresent(LogLevel.self, forKey: .logLevel)
        self.logFormat = try container.decodeIfPresent(LogFormat.self, forKey: .logFormat)
        self.dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun)
        self.debugDerivatives = try container.decodeIfPresent(Bool.self, forKey: .debugDerivatives)
        self.sourceIdentityPolicy = try container.decodeIfPresent(
            SourceIdentityPolicy.self,
            forKey: .sourceIdentityPolicy
        )
        self.derivativeCacheDir = try container.decodeIfPresent(String.self, forKey: .derivativeCacheDir)
        self.derivativeCacheSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .derivativeCacheSizeBytes)
        self.clearDerivativeCacheOnStart = try container.decodeIfPresent(Bool.self, forKey: .clearDerivativeCacheOnStart)
        self.clearDerivativeCacheAfterSuccess = try container.decodeIfPresent(
            Bool.self,
            forKey: .clearDerivativeCacheAfterSuccess
        )
        self.subjectCropMarginFraction = try container.decodeIfPresent(
            Double.self,
            forKey: .subjectCropMarginFraction
        )
        self.subjectMergeDominanceThreshold = try container.decodeIfPresent(
            Double.self,
            forKey: .subjectMergeDominanceThreshold
        )
        self.stageConcurrency = try container.decodeIfPresent(Int.self, forKey: .stageConcurrency)
        self.modelResponseRepairAttempts = try container.decodeIfPresent(Int.self, forKey: .modelResponseRepairAttempts)
        self.sourceRoot = try container.decodeIfPresent(String.self, forKey: .sourceRoot)
        self.sourceVerification = try container.decodeIfPresent(
            XMPSourceVerificationPolicy.self,
            forKey: .sourceVerification
        )
        self.writeFlatKeywords = try container.decodeIfPresent(Bool.self, forKey: .writeFlatKeywords)
        self.writeHierarchicalKeywords = try container.decodeIfPresent(Bool.self, forKey: .writeHierarchicalKeywords)
        self.backupSidecars = try container.decodeIfPresent(Bool.self, forKey: .backupSidecars)
        self.xmpConflictPolicy = try container.decodeIfPresent(XMPConflictPolicy.self, forKey: .xmpConflictPolicy)
        self.minConfidence = try container.decodeIfPresent(XMPMinimumConfidence.self, forKey: .minConfidence)
        self.allowSpecificTags = try container.decodeIfPresent(Bool.self, forKey: .allowSpecificTags)
        self.pairScope = try container.decodeIfPresent(XMPPairScope.self, forKey: .pairScope)
        self.writeAIJSON = try container.decodeIfPresent(Bool.self, forKey: .writeAIJSON)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(existing, forKey: .existing)
        try container.encodeIfPresent(recursive, forKey: .recursive)
        try container.encodeIfPresent(outputDir, forKey: .outputDir)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(modelEndpoint, forKey: .modelEndpoint)
        try container.encodeIfPresent(modelKeepAlive, forKey: .modelKeepAlive)
        try container.encodeIfPresent(profile, forKey: .profile)
        try container.encodeIfPresent(logLevel, forKey: .logLevel)
        try container.encodeIfPresent(logFormat, forKey: .logFormat)
        try container.encodeIfPresent(dryRun, forKey: .dryRun)
        try container.encodeIfPresent(debugDerivatives, forKey: .debugDerivatives)
        try container.encodeIfPresent(sourceIdentityPolicy, forKey: .sourceIdentityPolicy)
        try container.encodeIfPresent(derivativeCacheDir, forKey: .derivativeCacheDir)
        try container.encodeIfPresent(derivativeCacheSizeBytes, forKey: .derivativeCacheSizeBytes)
        try container.encodeIfPresent(clearDerivativeCacheOnStart, forKey: .clearDerivativeCacheOnStart)
        try container.encodeIfPresent(clearDerivativeCacheAfterSuccess, forKey: .clearDerivativeCacheAfterSuccess)
        try container.encodeIfPresent(subjectCropMarginFraction, forKey: .subjectCropMarginFraction)
        try container.encodeIfPresent(subjectMergeDominanceThreshold, forKey: .subjectMergeDominanceThreshold)
        try container.encodeIfPresent(stageConcurrency, forKey: .stageConcurrency)
        try container.encodeIfPresent(modelResponseRepairAttempts, forKey: .modelResponseRepairAttempts)
        try container.encodeIfPresent(sourceRoot, forKey: .sourceRoot)
        try container.encodeIfPresent(sourceVerification, forKey: .sourceVerification)
        try container.encodeIfPresent(writeFlatKeywords, forKey: .writeFlatKeywords)
        try container.encodeIfPresent(writeHierarchicalKeywords, forKey: .writeHierarchicalKeywords)
        try container.encodeIfPresent(backupSidecars, forKey: .backupSidecars)
        try container.encodeIfPresent(xmpConflictPolicy, forKey: .xmpConflictPolicy)
        try container.encodeIfPresent(minConfidence, forKey: .minConfidence)
        try container.encodeIfPresent(allowSpecificTags, forKey: .allowSpecificTags)
        try container.encodeIfPresent(pairScope, forKey: .pairScope)
        try container.encodeIfPresent(writeAIJSON, forKey: .writeAIJSON)
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
