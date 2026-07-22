import Foundation

struct NormalizationConfigurationBuilder {
    private var config: ResolvedNormalizationConfiguration
    private var qualityGrading: QualityGradingConfigurationBuilder
    private var vocabularyModeWasSet = false

    init(defaults: ResolvedNormalizationConfiguration) {
        self.config = defaults
        self.qualityGrading = QualityGradingConfigurationBuilder(defaults: defaults.qualityGrading)
    }

    mutating func apply(config fileConfig: AppConfig) {
        merge(&config.recursive, fileConfig.recursive)
        merge(&config.outputDir, fileConfig.outputDir)
        merge(&config.logLevel, fileConfig.logLevel)
        merge(&config.logFormat, fileConfig.logFormat)
        merge(&config.dryRun, fileConfig.dryRun)
        merge(&config.stageConcurrency, fileConfig.stageConcurrency)
        merge(&config.sourceRoot, fileConfig.sourceRoot)
        merge(&config.sourceVerification, fileConfig.sourceVerification)
        merge(&config.writeFlatKeywords, fileConfig.writeFlatKeywords)
        merge(&config.writeHierarchicalKeywords, fileConfig.writeHierarchicalKeywords)
        merge(&config.backupSidecars, fileConfig.backupSidecars)
        merge(&config.xmpConflictPolicy, fileConfig.xmpConflictPolicy)
        merge(&config.minConfidence, fileConfig.minConfidence)
        merge(&config.allowSpecificTags, fileConfig.allowSpecificTags)
        merge(&config.pairScope, fileConfig.pairScope)
        merge(&config.writeAIJSON, fileConfig.writeAIJSON)
        merge(&config.vocabularyPath, fileConfig.vocabularyPath)
        if let value = fileConfig.vocabularyMode {
            config.vocabularyMode = value
            vocabularyModeWasSet = true
        }
        merge(&config.normalizationMode, fileConfig.normalizationMode)
        merge(&config.sessionSubject, fileConfig.sessionSubject)
        merge(&config.sessionHabitat, fileConfig.sessionHabitat)
        merge(&config.sessionEvent, fileConfig.sessionEvent)
        merge(&config.consensusThreshold, fileConfig.consensusThreshold)
        merge(&config.affinityMode, fileConfig.affinityMode)
        merge(&config.affinityProfile, fileConfig.affinityProfile)
        merge(&config.minAffinityForConsensus, fileConfig.minAffinityForConsensus)
        merge(&config.sessionOnly, fileConfig.sessionOnly)
        merge(&config.unknownSessionContextPolicy, fileConfig.unknownSessionContextPolicy)
        merge(&config.allowSessionSubjectPropagation, fileConfig.allowSessionSubjectPropagation)
        merge(&config.allowSessionHabitatPropagation, fileConfig.allowSessionHabitatPropagation)
        merge(&config.allowSessionEventPropagation, fileConfig.allowSessionEventPropagation)
        merge(&config.affinityPrivacyMode, fileConfig.affinityPrivacyMode)
        merge(&config.writeReportPath, fileConfig.writeReportPath)
        qualityGrading.apply(config: fileConfig)
    }

    mutating func apply(overrides: NormalizationConfigurationOverrides) {
        merge(&config.recursive, overrides.recursive)
        merge(&config.outputDir, overrides.outputDir)
        merge(&config.logLevel, overrides.logLevel)
        merge(&config.logFormat, overrides.logFormat)
        merge(&config.dryRun, overrides.dryRun)
        merge(&config.stageConcurrency, overrides.stageConcurrency)
        merge(&config.sourceRoot, overrides.sourceRoot)
        merge(&config.sourceVerification, overrides.sourceVerification)
        merge(&config.writeFlatKeywords, overrides.writeFlatKeywords)
        merge(&config.writeHierarchicalKeywords, overrides.writeHierarchicalKeywords)
        merge(&config.backupSidecars, overrides.backupSidecars)
        merge(&config.xmpConflictPolicy, overrides.xmpConflictPolicy)
        merge(&config.minConfidence, overrides.minConfidence)
        merge(&config.allowSpecificTags, overrides.allowSpecificTags)
        merge(&config.pairScope, overrides.pairScope)
        merge(&config.writeAIJSON, overrides.writeAIJSON)
        merge(&config.vocabularyPath, overrides.vocabularyPath)
        if let value = overrides.vocabularyMode {
            config.vocabularyMode = value
            vocabularyModeWasSet = true
        }
        merge(&config.normalizationMode, overrides.normalizationMode)
        merge(&config.sessionSubject, overrides.sessionSubject)
        merge(&config.sessionHabitat, overrides.sessionHabitat)
        merge(&config.sessionEvent, overrides.sessionEvent)
        merge(&config.consensusThreshold, overrides.consensusThreshold)
        merge(&config.affinityMode, overrides.affinityMode)
        merge(&config.affinityProfile, overrides.affinityProfile)
        merge(&config.minAffinityForConsensus, overrides.minAffinityForConsensus)
        merge(&config.sessionOnly, overrides.sessionOnly)
        merge(&config.unknownSessionContextPolicy, overrides.unknownSessionContextPolicy)
        merge(&config.allowSessionSubjectPropagation, overrides.allowSessionSubjectPropagation)
        merge(&config.allowSessionHabitatPropagation, overrides.allowSessionHabitatPropagation)
        merge(&config.allowSessionEventPropagation, overrides.allowSessionEventPropagation)
        merge(&config.affinityPrivacyMode, overrides.affinityPrivacyMode)
        merge(&config.writeReportPath, overrides.writeReportPath)
        qualityGrading.apply(overrides: overrides.qualityGrading)
    }

    func resolved() throws -> ResolvedNormalizationConfiguration {
        var config = config
        if !vocabularyModeWasSet, config.vocabularyPath != nil {
            config.vocabularyMode = .controlledVocabulary
        }
        if config.vocabularyMode == .observedTags, config.vocabularyPath != nil {
            throw SidecarError.configInvalid(
                "vocabulary_path requires vocabulary_mode controlled-vocabulary"
            )
        }
        guard (0...1).contains(config.consensusThreshold), config.consensusThreshold.isFinite else {
            throw SidecarError.configInvalid("consensus_threshold must be a finite value between zero and one")
        }
        guard (0...1).contains(config.minAffinityForConsensus), config.minAffinityForConsensus.isFinite else {
            throw SidecarError.configInvalid("min_affinity_for_consensus must be a finite value between zero and one")
        }
        if config.xmpConflictPolicy == .backupAndMerge, !config.backupSidecars {
            throw SidecarError.configInvalid("xmp_conflict_policy backup-and-merge requires backup_sidecars to be true")
        }
        if let stageConcurrency = config.stageConcurrency, stageConcurrency <= 0 {
            throw SidecarError.configInvalid("stage_concurrency must be greater than zero")
        }
        config.qualityGrading = try qualityGrading.resolved()
        return config
    }
}
