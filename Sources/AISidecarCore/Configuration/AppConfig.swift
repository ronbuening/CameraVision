import Foundation

/// JSON-backed persistent defaults loaded before environment and CLI overrides.
public struct AppConfig: Codable, Sendable, Equatable {
    public var mode: AnalysisMode?
    public var existing: ExistingPolicy?
    public var recursive: Bool?
    public var qualityAssessment: Bool?
    public var qualityScanMode: QualityScanMode?
    public var outputDir: String?
    public var model: String?
    public var modelEndpoint: String?
    public var modelKeepAlive: String?
    public var modelTimeoutSeconds: Double?
    public var modelRetryLimit: Int?
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
    /// Optional EXIF GPS context policy for model prompts.
    public var gpsContext: GPSContextMode?
    /// Optional Ollama `num_ctx` token window for model calls.
    public var modelContextWindow: Int?
    /// Optional Ollama `num_predict` output-token cap for model calls.
    public var modelMaxResponseTokens: Int?
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
    public var xmpQualityGrading: Bool?
    public var xmpQualityConflicts: ScalarConflictPolicy?
    public var xmpQualityMinConfidence: QualityAssessmentRecord.Confidence?
    public var xmpQualityWriteRating: Bool?
    public var xmpQualityWriteLabel: Bool?
    public var xmpQualityWriteUrgency: Bool?
    public var xmpQualityWriteFlag: Bool?
    public var xmpQualityWriteKeywords: Bool?
    public var xmpQualityRejectAsMinusOne: Bool?
    public var xmpQualityPerCriterionProblemKeywords: Bool?
    public var xmpQualityKeywordRoot: String?
    public var xmpQualityRatingMap: [QualityTier: Int]?
    public var xmpQualityLabelMap: [QualityTier: String]?
    public var xmpQualityUrgencyMap: [QualityTier: Int]?
    public var xmpQualityFlagMap: [QualityTier: QualityPickFlag]?
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode
        case existing
        case recursive
        case qualityAssessment = "quality_assessment"
        case qualityScanMode = "quality_scan_mode"
        case outputDir = "output_dir"
        case model
        case modelEndpoint = "model_endpoint"
        case modelKeepAlive = "model_keep_alive"
        case modelTimeoutSeconds = "model_timeout_seconds"
        case modelRetryLimit = "model_retry_limit"
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
        case gpsContext = "gps_context"
        case modelContextWindow = "model_context_window"
        case modelMaxResponseTokens = "model_max_response_tokens"
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
        case xmpQualityGrading = "xmp_quality_grading"
        case xmpQualityConflicts = "xmp_quality_conflicts"
        case xmpQualityMinConfidence = "xmp_quality_min_confidence"
        case xmpQualityWriteRating = "xmp_quality_write_rating"
        case xmpQualityWriteLabel = "xmp_quality_write_label"
        case xmpQualityWriteUrgency = "xmp_quality_write_urgency"
        case xmpQualityWriteFlag = "xmp_quality_write_flag"
        case xmpQualityWriteKeywords = "xmp_quality_write_keywords"
        case xmpQualityRejectAsMinusOne = "xmp_quality_reject_as_minus_one"
        case xmpQualityPerCriterionProblemKeywords = "xmp_quality_per_criterion_problem_keywords"
        case xmpQualityKeywordRoot = "xmp_quality_keyword_root"
        case xmpQualityRatingMap = "xmp_quality_rating_map"
        case xmpQualityLabelMap = "xmp_quality_label_map"
        case xmpQualityUrgencyMap = "xmp_quality_urgency_map"
        case xmpQualityFlagMap = "xmp_quality_flag_map"
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
    }

    public init(
        mode: AnalysisMode? = nil,
        existing: ExistingPolicy? = nil,
        recursive: Bool? = nil,
        qualityAssessment: Bool? = nil,
        qualityScanMode: QualityScanMode? = nil,
        outputDir: String? = nil,
        model: String? = nil,
        modelEndpoint: String? = nil,
        modelKeepAlive: String? = nil,
        modelTimeoutSeconds: Double? = nil,
        modelRetryLimit: Int? = nil,
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
        gpsContext: GPSContextMode? = nil,
        modelContextWindow: Int? = nil,
        modelMaxResponseTokens: Int? = nil,
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
        xmpQualityGrading: Bool? = nil,
        xmpQualityConflicts: ScalarConflictPolicy? = nil,
        xmpQualityMinConfidence: QualityAssessmentRecord.Confidence? = nil,
        xmpQualityWriteRating: Bool? = nil,
        xmpQualityWriteLabel: Bool? = nil,
        xmpQualityWriteUrgency: Bool? = nil,
        xmpQualityWriteFlag: Bool? = nil,
        xmpQualityWriteKeywords: Bool? = nil,
        xmpQualityRejectAsMinusOne: Bool? = nil,
        xmpQualityPerCriterionProblemKeywords: Bool? = nil,
        xmpQualityKeywordRoot: String? = nil,
        xmpQualityRatingMap: [QualityTier: Int]? = nil,
        xmpQualityLabelMap: [QualityTier: String]? = nil,
        xmpQualityUrgencyMap: [QualityTier: Int]? = nil,
        xmpQualityFlagMap: [QualityTier: QualityPickFlag]? = nil,
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
        writeReportPath: String? = nil
    ) {
        self.mode = mode
        self.existing = existing
        self.recursive = recursive
        self.qualityAssessment = qualityAssessment
        self.qualityScanMode = qualityScanMode
        self.outputDir = outputDir
        self.model = model
        self.modelEndpoint = modelEndpoint
        self.modelKeepAlive = modelKeepAlive
        self.modelTimeoutSeconds = modelTimeoutSeconds
        self.modelRetryLimit = modelRetryLimit
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
        self.gpsContext = gpsContext
        self.modelContextWindow = modelContextWindow
        self.modelMaxResponseTokens = modelMaxResponseTokens
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
        self.xmpQualityGrading = xmpQualityGrading
        self.xmpQualityConflicts = xmpQualityConflicts
        self.xmpQualityMinConfidence = xmpQualityMinConfidence
        self.xmpQualityWriteRating = xmpQualityWriteRating
        self.xmpQualityWriteLabel = xmpQualityWriteLabel
        self.xmpQualityWriteUrgency = xmpQualityWriteUrgency
        self.xmpQualityWriteFlag = xmpQualityWriteFlag
        self.xmpQualityWriteKeywords = xmpQualityWriteKeywords
        self.xmpQualityRejectAsMinusOne = xmpQualityRejectAsMinusOne
        self.xmpQualityPerCriterionProblemKeywords = xmpQualityPerCriterionProblemKeywords
        self.xmpQualityKeywordRoot = xmpQualityKeywordRoot
        self.xmpQualityRatingMap = xmpQualityRatingMap
        self.xmpQualityLabelMap = xmpQualityLabelMap
        self.xmpQualityUrgencyMap = xmpQualityUrgencyMap
        self.xmpQualityFlagMap = xmpQualityFlagMap
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
        self.qualityAssessment = try container.decodeIfPresent(Bool.self, forKey: .qualityAssessment)
        self.qualityScanMode = try container.decodeIfPresent(QualityScanMode.self, forKey: .qualityScanMode)
        self.outputDir = try container.decodeIfPresent(String.self, forKey: .outputDir)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.modelEndpoint = try container.decodeIfPresent(String.self, forKey: .modelEndpoint)
        self.modelKeepAlive = try container.decodeIfPresent(String.self, forKey: .modelKeepAlive)
        self.modelTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .modelTimeoutSeconds)
        self.modelRetryLimit = try container.decodeIfPresent(Int.self, forKey: .modelRetryLimit)
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
        self.clearDerivativeCacheOnStart = try container.decodeIfPresent(
            Bool.self, forKey: .clearDerivativeCacheOnStart)
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
        self.gpsContext = try container.decodeIfPresent(GPSContextMode.self, forKey: .gpsContext)
        self.modelContextWindow = try container.decodeIfPresent(Int.self, forKey: .modelContextWindow)
        self.modelMaxResponseTokens = try container.decodeIfPresent(Int.self, forKey: .modelMaxResponseTokens)
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
        self.xmpQualityGrading = try container.decodeIfPresent(Bool.self, forKey: .xmpQualityGrading)
        self.xmpQualityConflicts = try container.decodeIfPresent(
            ScalarConflictPolicy.self,
            forKey: .xmpQualityConflicts
        )
        if let confidenceValue = try container.decodeIfPresent(String.self, forKey: .xmpQualityMinConfidence) {
            guard let confidence = QualityAssessmentRecord.Confidence(rawValue: confidenceValue) else {
                throw SidecarError.configInvalid("Unknown quality confidence: \(confidenceValue)")
            }
            self.xmpQualityMinConfidence = confidence
        } else {
            self.xmpQualityMinConfidence = nil
        }
        self.xmpQualityWriteRating = try container.decodeIfPresent(Bool.self, forKey: .xmpQualityWriteRating)
        self.xmpQualityWriteLabel = try container.decodeIfPresent(Bool.self, forKey: .xmpQualityWriteLabel)
        self.xmpQualityWriteUrgency = try container.decodeIfPresent(Bool.self, forKey: .xmpQualityWriteUrgency)
        self.xmpQualityWriteFlag = try container.decodeIfPresent(Bool.self, forKey: .xmpQualityWriteFlag)
        self.xmpQualityWriteKeywords = try container.decodeIfPresent(Bool.self, forKey: .xmpQualityWriteKeywords)
        self.xmpQualityRejectAsMinusOne = try container.decodeIfPresent(
            Bool.self,
            forKey: .xmpQualityRejectAsMinusOne
        )
        self.xmpQualityPerCriterionProblemKeywords = try container.decodeIfPresent(
            Bool.self,
            forKey: .xmpQualityPerCriterionProblemKeywords
        )
        self.xmpQualityKeywordRoot = try container.decodeIfPresent(String.self, forKey: .xmpQualityKeywordRoot)
        self.xmpQualityRatingMap = try Self.decodeTierMap(
            Int.self,
            from: container,
            forKey: .xmpQualityRatingMap
        )
        self.xmpQualityLabelMap = try Self.decodeTierMap(
            String.self,
            from: container,
            forKey: .xmpQualityLabelMap
        )
        self.xmpQualityUrgencyMap = try Self.decodeTierMap(
            Int.self,
            from: container,
            forKey: .xmpQualityUrgencyMap
        )
        self.xmpQualityFlagMap = try Self.decodeTierMap(
            QualityPickFlag.self,
            from: container,
            forKey: .xmpQualityFlagMap
        )
        self.vocabularyPath = try container.decodeIfPresent(String.self, forKey: .vocabularyPath)
        self.vocabularyMode = try container.decodeIfPresent(NormalizationVocabularyMode.self, forKey: .vocabularyMode)
        self.normalizationMode = try container.decodeIfPresent(NormalizationMode.self, forKey: .normalizationMode)
        self.sessionSubject = try container.decodeIfPresent(String.self, forKey: .sessionSubject)
        self.sessionHabitat = try container.decodeIfPresent(String.self, forKey: .sessionHabitat)
        self.sessionEvent = try container.decodeIfPresent(String.self, forKey: .sessionEvent)
        self.consensusThreshold = try container.decodeIfPresent(Double.self, forKey: .consensusThreshold)
        self.affinityMode = try container.decodeIfPresent(NormalizationAffinityMode.self, forKey: .affinityMode)
        self.affinityProfile = try container.decodeIfPresent(
            NormalizationAffinityProfile.self, forKey: .affinityProfile)
        self.minAffinityForConsensus = try container.decodeIfPresent(Double.self, forKey: .minAffinityForConsensus)
        self.sessionOnly = try container.decodeIfPresent(Bool.self, forKey: .sessionOnly)
        self.unknownSessionContextPolicy = try container.decodeIfPresent(
            UnknownSessionContextPolicy.self,
            forKey: .unknownSessionContextPolicy
        )
        self.allowSessionSubjectPropagation = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowSessionSubjectPropagation
        )
        self.allowSessionHabitatPropagation = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowSessionHabitatPropagation
        )
        self.allowSessionEventPropagation = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowSessionEventPropagation
        )
        self.affinityPrivacyMode = try container.decodeIfPresent(AffinityPrivacyMode.self, forKey: .affinityPrivacyMode)
        self.writeReportPath = try container.decodeIfPresent(String.self, forKey: .writeReportPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(existing, forKey: .existing)
        try container.encodeIfPresent(recursive, forKey: .recursive)
        try container.encodeIfPresent(qualityAssessment, forKey: .qualityAssessment)
        try container.encodeIfPresent(qualityScanMode, forKey: .qualityScanMode)
        try container.encodeIfPresent(outputDir, forKey: .outputDir)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(modelEndpoint, forKey: .modelEndpoint)
        try container.encodeIfPresent(modelKeepAlive, forKey: .modelKeepAlive)
        try container.encodeIfPresent(modelTimeoutSeconds, forKey: .modelTimeoutSeconds)
        try container.encodeIfPresent(modelRetryLimit, forKey: .modelRetryLimit)
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
        try container.encodeIfPresent(gpsContext, forKey: .gpsContext)
        try container.encodeIfPresent(modelContextWindow, forKey: .modelContextWindow)
        try container.encodeIfPresent(modelMaxResponseTokens, forKey: .modelMaxResponseTokens)
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
        try container.encodeIfPresent(xmpQualityGrading, forKey: .xmpQualityGrading)
        try container.encodeIfPresent(xmpQualityConflicts, forKey: .xmpQualityConflicts)
        try container.encodeIfPresent(xmpQualityMinConfidence?.rawValue, forKey: .xmpQualityMinConfidence)
        try container.encodeIfPresent(xmpQualityWriteRating, forKey: .xmpQualityWriteRating)
        try container.encodeIfPresent(xmpQualityWriteLabel, forKey: .xmpQualityWriteLabel)
        try container.encodeIfPresent(xmpQualityWriteUrgency, forKey: .xmpQualityWriteUrgency)
        try container.encodeIfPresent(xmpQualityWriteFlag, forKey: .xmpQualityWriteFlag)
        try container.encodeIfPresent(xmpQualityWriteKeywords, forKey: .xmpQualityWriteKeywords)
        try container.encodeIfPresent(xmpQualityRejectAsMinusOne, forKey: .xmpQualityRejectAsMinusOne)
        try container.encodeIfPresent(
            xmpQualityPerCriterionProblemKeywords,
            forKey: .xmpQualityPerCriterionProblemKeywords
        )
        try container.encodeIfPresent(xmpQualityKeywordRoot, forKey: .xmpQualityKeywordRoot)
        try container.encodeIfPresent(
            xmpQualityRatingMap.map(QualityGradingPolicy.rawTierMap),
            forKey: .xmpQualityRatingMap
        )
        try container.encodeIfPresent(
            xmpQualityLabelMap.map(QualityGradingPolicy.rawTierMap),
            forKey: .xmpQualityLabelMap
        )
        try container.encodeIfPresent(
            xmpQualityUrgencyMap.map(QualityGradingPolicy.rawTierMap),
            forKey: .xmpQualityUrgencyMap
        )
        try container.encodeIfPresent(
            xmpQualityFlagMap.map(QualityGradingPolicy.rawTierMap),
            forKey: .xmpQualityFlagMap
        )
        try container.encodeIfPresent(vocabularyPath, forKey: .vocabularyPath)
        try container.encodeIfPresent(vocabularyMode, forKey: .vocabularyMode)
        try container.encodeIfPresent(normalizationMode, forKey: .normalizationMode)
        try container.encodeIfPresent(sessionSubject, forKey: .sessionSubject)
        try container.encodeIfPresent(sessionHabitat, forKey: .sessionHabitat)
        try container.encodeIfPresent(sessionEvent, forKey: .sessionEvent)
        try container.encodeIfPresent(consensusThreshold, forKey: .consensusThreshold)
        try container.encodeIfPresent(affinityMode, forKey: .affinityMode)
        try container.encodeIfPresent(affinityProfile, forKey: .affinityProfile)
        try container.encodeIfPresent(minAffinityForConsensus, forKey: .minAffinityForConsensus)
        try container.encodeIfPresent(sessionOnly, forKey: .sessionOnly)
        try container.encodeIfPresent(unknownSessionContextPolicy, forKey: .unknownSessionContextPolicy)
        try container.encodeIfPresent(allowSessionSubjectPropagation, forKey: .allowSessionSubjectPropagation)
        try container.encodeIfPresent(allowSessionHabitatPropagation, forKey: .allowSessionHabitatPropagation)
        try container.encodeIfPresent(allowSessionEventPropagation, forKey: .allowSessionEventPropagation)
        try container.encodeIfPresent(affinityPrivacyMode, forKey: .affinityPrivacyMode)
        try container.encodeIfPresent(writeReportPath, forKey: .writeReportPath)
    }

    private static func decodeTierMap<Value: Decodable>(
        _: Value.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> [QualityTier: Value]? {
        guard let values = try container.decodeIfPresent([String: Value].self, forKey: key) else {
            return nil
        }
        return try QualityGradingPolicy.decodeTierMap(values, fieldName: key.rawValue)
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
