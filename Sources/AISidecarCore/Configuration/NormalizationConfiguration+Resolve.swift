import Foundation

extension ConfigurationResolver {
    /// Resolve Phase 3 normalization settings without starting analysis or writes.
    public static func resolveNormalization(
        cli: NormalizationConfigurationOverrides = NormalizationConfigurationOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultConfigPath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> ResolvedNormalizationConfiguration {
        let (selectedConfigPath, explicitConfigPath) = selectConfigPath(
            cliConfigPath: cli.configPath,
            environment: environment,
            defaultConfigPath: defaultConfigPath
        )

        let fileConfig: AppConfig = try loadConfigFile(
            path: selectedConfigPath,
            explicit: explicitConfigPath,
            fileManager: fileManager,
            defaultValue: AppConfig()
        )
        let envOverrides = try normalizationEnvironmentOverrides(from: environment)

        var builder = NormalizationConfigurationBuilder(defaults: .builtInDefaults)
        builder.apply(config: fileConfig)
        builder.apply(overrides: envOverrides)
        builder.apply(overrides: cli.withoutConfigPath())
        return try builder.resolved()
    }

    private static func normalizationEnvironmentOverrides(
        from environment: [String: String]
    ) throws -> NormalizationConfigurationOverrides {
        NormalizationConfigurationOverrides(
            recursive: try boolValue(from: environment["AISIDECAR_RECURSIVE"], key: "AISIDECAR_RECURSIVE"),
            outputDir: environment["AISIDECAR_OUTPUT_DIR"],
            logLevel: try enumValue(
                LogLevel.self, from: environment["AISIDECAR_LOG_LEVEL"], key: "AISIDECAR_LOG_LEVEL"),
            logFormat: try enumValue(
                LogFormat.self, from: environment["AISIDECAR_LOG_FORMAT"], key: "AISIDECAR_LOG_FORMAT"),
            dryRun: try boolValue(from: environment["AISIDECAR_DRY_RUN"], key: "AISIDECAR_DRY_RUN"),
            sourceRoot: environment["AISIDECAR_SOURCE_ROOT"],
            sourceVerification: try enumValue(
                XMPSourceVerificationPolicy.self,
                from: environment["AISIDECAR_SOURCE_VERIFICATION"],
                key: "AISIDECAR_SOURCE_VERIFICATION"
            ),
            writeFlatKeywords: try boolValue(
                from: environment["AISIDECAR_WRITE_FLAT_KEYWORDS"],
                key: "AISIDECAR_WRITE_FLAT_KEYWORDS"
            ),
            writeHierarchicalKeywords: try boolValue(
                from: environment["AISIDECAR_WRITE_HIERARCHICAL_KEYWORDS"],
                key: "AISIDECAR_WRITE_HIERARCHICAL_KEYWORDS"
            ),
            backupSidecars: try boolValue(
                from: environment["AISIDECAR_BACKUP_SIDECARS"],
                key: "AISIDECAR_BACKUP_SIDECARS"
            ),
            xmpConflictPolicy: try enumValue(
                XMPConflictPolicy.self,
                from: environment["AISIDECAR_XMP_CONFLICT_POLICY"],
                key: "AISIDECAR_XMP_CONFLICT_POLICY"
            ),
            minConfidence: try enumValue(
                XMPMinimumConfidence.self,
                from: environment["AISIDECAR_MIN_CONFIDENCE"],
                key: "AISIDECAR_MIN_CONFIDENCE"
            ),
            allowSpecificTags: try boolValue(
                from: environment["AISIDECAR_ALLOW_SPECIFIC_TAGS"],
                key: "AISIDECAR_ALLOW_SPECIFIC_TAGS"
            ),
            pairScope: try enumValue(
                XMPPairScope.self, from: environment["AISIDECAR_PAIR_SCOPE"], key: "AISIDECAR_PAIR_SCOPE"),
            writeAIJSON: try boolValue(from: environment["AISIDECAR_WRITE_AI_JSON"], key: "AISIDECAR_WRITE_AI_JSON"),
            vocabularyPath: environment["AISIDECAR_VOCABULARY"],
            vocabularyMode: try enumValue(
                NormalizationVocabularyMode.self,
                from: environment["AISIDECAR_VOCABULARY_MODE"],
                key: "AISIDECAR_VOCABULARY_MODE"
            ),
            normalizationMode: try enumValue(
                NormalizationMode.self,
                from: environment["AISIDECAR_NORMALIZATION_MODE"],
                key: "AISIDECAR_NORMALIZATION_MODE"
            ),
            sessionSubject: environment["AISIDECAR_SESSION_SUBJECT"],
            sessionHabitat: environment["AISIDECAR_SESSION_HABITAT"],
            sessionEvent: environment["AISIDECAR_SESSION_EVENT"],
            consensusThreshold: try doubleValue(
                from: environment["AISIDECAR_CONSENSUS_THRESHOLD"],
                key: "AISIDECAR_CONSENSUS_THRESHOLD"
            ),
            affinityMode: try enumValue(
                NormalizationAffinityMode.self,
                from: environment["AISIDECAR_AFFINITY_MODE"],
                key: "AISIDECAR_AFFINITY_MODE"
            ),
            affinityProfile: try enumValue(
                NormalizationAffinityProfile.self,
                from: environment["AISIDECAR_AFFINITY_PROFILE"],
                key: "AISIDECAR_AFFINITY_PROFILE"
            ),
            minAffinityForConsensus: try doubleValue(
                from: environment["AISIDECAR_MIN_AFFINITY_FOR_CONSENSUS"],
                key: "AISIDECAR_MIN_AFFINITY_FOR_CONSENSUS"
            ),
            sessionOnly: try boolValue(from: environment["AISIDECAR_SESSION_ONLY"], key: "AISIDECAR_SESSION_ONLY"),
            unknownSessionContextPolicy: try enumValue(
                UnknownSessionContextPolicy.self,
                from: environment["AISIDECAR_UNKNOWN_SESSION_CONTEXT_POLICY"],
                key: "AISIDECAR_UNKNOWN_SESSION_CONTEXT_POLICY"
            ),
            allowSessionSubjectPropagation: try boolValue(
                from: environment["AISIDECAR_ALLOW_SESSION_SUBJECT_PROPAGATION"],
                key: "AISIDECAR_ALLOW_SESSION_SUBJECT_PROPAGATION"
            ),
            allowSessionHabitatPropagation: try boolValue(
                from: environment["AISIDECAR_ALLOW_SESSION_HABITAT_PROPAGATION"],
                key: "AISIDECAR_ALLOW_SESSION_HABITAT_PROPAGATION"
            ),
            allowSessionEventPropagation: try boolValue(
                from: environment["AISIDECAR_ALLOW_SESSION_EVENT_PROPAGATION"],
                key: "AISIDECAR_ALLOW_SESSION_EVENT_PROPAGATION"
            ),
            affinityPrivacyMode: try enumValue(
                AffinityPrivacyMode.self,
                from: environment["AISIDECAR_AFFINITY_PRIVACY_MODE"],
                key: "AISIDECAR_AFFINITY_PRIVACY_MODE"
            ),
            writeReportPath: environment["AISIDECAR_WRITE_REPORT"],
            qualityGrading: try qualityGradingEnvironmentOverrides(from: environment)
        )
    }
}

private struct NormalizationConfigurationBuilder {
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
        config.qualityGrading = try qualityGrading.resolved()
        return config
    }
}

extension NormalizationConfigurationOverrides {
    fileprivate func withoutConfigPath() -> NormalizationConfigurationOverrides {
        NormalizationConfigurationOverrides(
            recursive: recursive,
            outputDir: outputDir,
            logLevel: logLevel,
            logFormat: logFormat,
            dryRun: dryRun,
            sourceRoot: sourceRoot,
            sourceVerification: sourceVerification,
            writeFlatKeywords: writeFlatKeywords,
            writeHierarchicalKeywords: writeHierarchicalKeywords,
            backupSidecars: backupSidecars,
            xmpConflictPolicy: xmpConflictPolicy,
            minConfidence: minConfidence,
            allowSpecificTags: allowSpecificTags,
            pairScope: pairScope,
            writeAIJSON: writeAIJSON,
            vocabularyPath: vocabularyPath,
            vocabularyMode: vocabularyMode,
            normalizationMode: normalizationMode,
            sessionSubject: sessionSubject,
            sessionHabitat: sessionHabitat,
            sessionEvent: sessionEvent,
            consensusThreshold: consensusThreshold,
            affinityMode: affinityMode,
            affinityProfile: affinityProfile,
            minAffinityForConsensus: minAffinityForConsensus,
            sessionOnly: sessionOnly,
            unknownSessionContextPolicy: unknownSessionContextPolicy,
            allowSessionSubjectPropagation: allowSessionSubjectPropagation,
            allowSessionHabitatPropagation: allowSessionHabitatPropagation,
            allowSessionEventPropagation: allowSessionEventPropagation,
            affinityPrivacyMode: affinityPrivacyMode,
            writeReportPath: writeReportPath,
            qualityGrading: qualityGrading
        )
    }
}
