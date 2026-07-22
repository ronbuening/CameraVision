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
            stageConcurrency: try intValue(
                from: environment["AISIDECAR_STAGE_CONCURRENCY"],
                key: "AISIDECAR_STAGE_CONCURRENCY"
            ),
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

extension NormalizationConfigurationOverrides {
    fileprivate func withoutConfigPath() -> NormalizationConfigurationOverrides {
        NormalizationConfigurationOverrides(
            recursive: recursive,
            outputDir: outputDir,
            logLevel: logLevel,
            logFormat: logFormat,
            dryRun: dryRun,
            stageConcurrency: stageConcurrency,
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
