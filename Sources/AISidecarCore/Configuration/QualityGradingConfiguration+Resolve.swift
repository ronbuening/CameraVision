extension ConfigurationResolver {
    static func qualityGradingEnvironmentOverrides(
        from environment: [String: String]
    ) throws -> QualityGradingConfigurationOverrides {
        QualityGradingConfigurationOverrides(
            enabled: try boolValue(
                from: environment["AISIDECAR_XMP_QUALITY_GRADING"],
                key: "AISIDECAR_XMP_QUALITY_GRADING"
            ),
            conflictPolicy: try enumValue(
                ScalarConflictPolicy.self,
                from: environment["AISIDECAR_XMP_QUALITY_CONFLICTS"],
                key: "AISIDECAR_XMP_QUALITY_CONFLICTS"
            ),
            minimumConfidence: try enumValue(
                QualityAssessmentRecord.Confidence.self,
                from: environment["AISIDECAR_XMP_QUALITY_MIN_CONFIDENCE"],
                key: "AISIDECAR_XMP_QUALITY_MIN_CONFIDENCE"
            ),
            writeRating: try boolValue(
                from: environment["AISIDECAR_XMP_QUALITY_WRITE_RATING"],
                key: "AISIDECAR_XMP_QUALITY_WRITE_RATING"
            ),
            writeLabel: try boolValue(
                from: environment["AISIDECAR_XMP_QUALITY_WRITE_LABEL"],
                key: "AISIDECAR_XMP_QUALITY_WRITE_LABEL"
            ),
            writeUrgency: try boolValue(
                from: environment["AISIDECAR_XMP_QUALITY_WRITE_URGENCY"],
                key: "AISIDECAR_XMP_QUALITY_WRITE_URGENCY"
            ),
            writeFlag: try boolValue(
                from: environment["AISIDECAR_XMP_QUALITY_WRITE_FLAG"],
                key: "AISIDECAR_XMP_QUALITY_WRITE_FLAG"
            ),
            writeKeywords: try boolValue(
                from: environment["AISIDECAR_XMP_QUALITY_WRITE_KEYWORDS"],
                key: "AISIDECAR_XMP_QUALITY_WRITE_KEYWORDS"
            ),
            rejectAsMinusOne: try boolValue(
                from: environment["AISIDECAR_XMP_QUALITY_REJECT_AS_MINUS_ONE"],
                key: "AISIDECAR_XMP_QUALITY_REJECT_AS_MINUS_ONE"
            ),
            perCriterionProblemKeywords: try boolValue(
                from: environment["AISIDECAR_XMP_QUALITY_PER_CRITERION_PROBLEM_KEYWORDS"],
                key: "AISIDECAR_XMP_QUALITY_PER_CRITERION_PROBLEM_KEYWORDS"
            ),
            keywordRoot: environment["AISIDECAR_XMP_QUALITY_KEYWORD_ROOT"]
        )
    }
}

struct QualityGradingConfigurationBuilder {
    private var enabled: Bool
    private var conflictPolicy: ScalarConflictPolicy
    private var policy: QualityGradingPolicy

    init(defaults: ResolvedQualityGradingConfiguration) {
        self.enabled = defaults.enabled
        self.conflictPolicy = defaults.conflictPolicy
        self.policy = defaults.policy
    }

    mutating func apply(config: AppConfig) {
        merge(&enabled, config.xmpQualityGrading)
        merge(&conflictPolicy, config.xmpQualityConflicts)
        merge(&policy.minimumConfidence, config.xmpQualityMinConfidence)
        merge(&policy.writeRating, config.xmpQualityWriteRating)
        merge(&policy.writeLabel, config.xmpQualityWriteLabel)
        merge(&policy.writeUrgency, config.xmpQualityWriteUrgency)
        merge(&policy.writeFlag, config.xmpQualityWriteFlag)
        merge(&policy.writeKeywords, config.xmpQualityWriteKeywords)
        merge(&policy.rejectAsMinusOne, config.xmpQualityRejectAsMinusOne)
        merge(&policy.perCriterionProblemKeywords, config.xmpQualityPerCriterionProblemKeywords)
        merge(&policy.keywordRoot, config.xmpQualityKeywordRoot)
        merge(&policy.ratingMap, config.xmpQualityRatingMap)
        merge(&policy.labelMap, config.xmpQualityLabelMap)
        merge(&policy.urgencyMap, config.xmpQualityUrgencyMap)
        merge(&policy.flagMap, config.xmpQualityFlagMap)
    }

    mutating func apply(overrides: QualityGradingConfigurationOverrides) {
        merge(&enabled, overrides.enabled)
        merge(&conflictPolicy, overrides.conflictPolicy)
        merge(&policy.minimumConfidence, overrides.minimumConfidence)
        merge(&policy.writeRating, overrides.writeRating)
        merge(&policy.writeLabel, overrides.writeLabel)
        merge(&policy.writeUrgency, overrides.writeUrgency)
        merge(&policy.writeFlag, overrides.writeFlag)
        merge(&policy.writeKeywords, overrides.writeKeywords)
        merge(&policy.rejectAsMinusOne, overrides.rejectAsMinusOne)
        merge(&policy.perCriterionProblemKeywords, overrides.perCriterionProblemKeywords)
        merge(&policy.keywordRoot, overrides.keywordRoot)
        merge(&policy.ratingMap, overrides.ratingMap)
        merge(&policy.labelMap, overrides.labelMap)
        merge(&policy.urgencyMap, overrides.urgencyMap)
        merge(&policy.flagMap, overrides.flagMap)
    }

    func resolved() throws -> ResolvedQualityGradingConfiguration {
        // Validate the complete policy even while grading is disabled so dormant
        // configuration errors fail before any batch work begins.
        try policy.validate()
        return ResolvedQualityGradingConfiguration(
            enabled: enabled,
            conflictPolicy: conflictPolicy,
            policy: policy
        )
    }
}
