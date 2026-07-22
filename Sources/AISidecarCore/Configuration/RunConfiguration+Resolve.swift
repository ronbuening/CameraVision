import Foundation

extension ConfigurationResolver {
    /// Build a provenance-ready configuration snapshot.
    ///
    /// Precedence is CLI flag > `AISIDECAR_*` environment > JSON config file >
    /// built-in default. `defaultConfigPath` is injectable so tests remain
    /// deterministic and do not depend on the user's home directory.
    public static func resolve(
        cli: RunConfigurationOverrides = RunConfigurationOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultConfigPath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> ResolvedRunConfiguration {
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
        let envOverrides = try environmentOverrides(from: environment)

        var builder = ConfigurationBuilder(defaults: .builtInDefaults)
        builder.apply(config: fileConfig)
        builder.apply(overrides: envOverrides)
        builder.apply(overrides: cli.withoutConfigPath())
        return try builder.resolved()
    }

    private static func environmentOverrides(from environment: [String: String]) throws -> RunConfigurationOverrides {
        RunConfigurationOverrides(
            mode: try enumValue(AnalysisMode.self, from: environment["AISIDECAR_MODE"], key: "AISIDECAR_MODE"),
            existing: try enumValue(
                ExistingPolicy.self, from: environment["AISIDECAR_EXISTING"], key: "AISIDECAR_EXISTING"),
            recursive: try boolValue(from: environment["AISIDECAR_RECURSIVE"], key: "AISIDECAR_RECURSIVE"),
            qualityAssessment: try boolValue(
                from: environment["AISIDECAR_QUALITY_ASSESSMENT"],
                key: "AISIDECAR_QUALITY_ASSESSMENT"
            ),
            qualityScanMode: try enumValue(
                QualityScanMode.self,
                from: environment["AISIDECAR_QUALITY_SCAN_MODE"],
                key: "AISIDECAR_QUALITY_SCAN_MODE"
            ),
            outputDir: environment["AISIDECAR_OUTPUT_DIR"],
            model: environment["AISIDECAR_MODEL"],
            modelEndpoint: environment["AISIDECAR_MODEL_ENDPOINT"],
            modelKeepAlive: environment["AISIDECAR_MODEL_KEEP_ALIVE"],
            modelTimeoutSeconds: try doubleValue(
                from: environment["AISIDECAR_MODEL_TIMEOUT_SECONDS"],
                key: "AISIDECAR_MODEL_TIMEOUT_SECONDS"
            ),
            modelRetryLimit: try nonNegativeIntValue(
                from: environment["AISIDECAR_MODEL_RETRY_LIMIT"],
                key: "AISIDECAR_MODEL_RETRY_LIMIT"
            ),
            profile: environment["AISIDECAR_PROFILE"],
            logLevel: try enumValue(
                LogLevel.self, from: environment["AISIDECAR_LOG_LEVEL"], key: "AISIDECAR_LOG_LEVEL"),
            logFormat: try enumValue(
                LogFormat.self, from: environment["AISIDECAR_LOG_FORMAT"], key: "AISIDECAR_LOG_FORMAT"),
            dryRun: try boolValue(from: environment["AISIDECAR_DRY_RUN"], key: "AISIDECAR_DRY_RUN"),
            debugDerivatives: try boolValue(
                from: environment["AISIDECAR_DEBUG_DERIVATIVES"],
                key: "AISIDECAR_DEBUG_DERIVATIVES"
            ),
            sourceIdentityPolicy: try enumValue(
                SourceIdentityPolicy.self,
                from: environment["AISIDECAR_SOURCE_IDENTITY_POLICY"],
                key: "AISIDECAR_SOURCE_IDENTITY_POLICY"
            ),
            derivativeCacheDir: environment["AISIDECAR_DERIVATIVE_CACHE_DIR"],
            derivativeCacheSizeBytes: try int64Value(
                from: environment["AISIDECAR_DERIVATIVE_CACHE_SIZE_BYTES"],
                key: "AISIDECAR_DERIVATIVE_CACHE_SIZE_BYTES"
            ),
            clearDerivativeCacheOnStart: try boolValue(
                from: environment["AISIDECAR_CLEAR_DERIVATIVE_CACHE_ON_START"],
                key: "AISIDECAR_CLEAR_DERIVATIVE_CACHE_ON_START"
            ),
            clearDerivativeCacheAfterSuccess: try boolValue(
                from: environment["AISIDECAR_CLEAR_DERIVATIVE_CACHE_AFTER_SUCCESS"],
                key: "AISIDECAR_CLEAR_DERIVATIVE_CACHE_AFTER_SUCCESS"
            ),
            subjectCropMarginFraction: try doubleValue(
                from: environment["AISIDECAR_SUBJECT_CROP_MARGIN_FRACTION"],
                key: "AISIDECAR_SUBJECT_CROP_MARGIN_FRACTION"
            ),
            subjectMergeDominanceThreshold: try doubleValue(
                from: environment["AISIDECAR_SUBJECT_MERGE_DOMINANCE_THRESHOLD"],
                key: "AISIDECAR_SUBJECT_MERGE_DOMINANCE_THRESHOLD"
            ),
            stageConcurrency: try intValue(
                from: environment["AISIDECAR_STAGE_CONCURRENCY"],
                key: "AISIDECAR_STAGE_CONCURRENCY"
            ),
            modelResponseRepairAttempts: try nonNegativeIntValue(
                from: environment["AISIDECAR_MODEL_RESPONSE_REPAIR_ATTEMPTS"],
                key: "AISIDECAR_MODEL_RESPONSE_REPAIR_ATTEMPTS"
            ),
            gpsContext: try enumValue(
                GPSContextMode.self,
                from: environment["AISIDECAR_GPS_CONTEXT"],
                key: "AISIDECAR_GPS_CONTEXT"
            ),
            modelContextWindow: try nonNegativeIntValue(
                from: environment["AISIDECAR_MODEL_CONTEXT_WINDOW"],
                key: "AISIDECAR_MODEL_CONTEXT_WINDOW"
            ),
            modelMaxResponseTokens: try intValue(
                from: environment["AISIDECAR_MODEL_MAX_RESPONSE_TOKENS"],
                key: "AISIDECAR_MODEL_MAX_RESPONSE_TOKENS"
            )
        )
    }
}

extension RunConfigurationOverrides {
    fileprivate func withoutConfigPath() -> RunConfigurationOverrides {
        // The selected config path controls which file is read, but it is not a
        // persisted run value and should not participate in provenance.
        RunConfigurationOverrides(
            mode: mode,
            existing: existing,
            recursive: recursive,
            qualityAssessment: qualityAssessment,
            qualityScanMode: qualityScanMode,
            outputDir: outputDir,
            model: model,
            modelEndpoint: modelEndpoint,
            modelKeepAlive: modelKeepAlive,
            modelTimeoutSeconds: modelTimeoutSeconds,
            modelRetryLimit: modelRetryLimit,
            profile: profile,
            logLevel: logLevel,
            logFormat: logFormat,
            dryRun: dryRun,
            debugDerivatives: debugDerivatives,
            sourceIdentityPolicy: sourceIdentityPolicy,
            derivativeCacheDir: derivativeCacheDir,
            derivativeCacheSizeBytes: derivativeCacheSizeBytes,
            clearDerivativeCacheOnStart: clearDerivativeCacheOnStart,
            clearDerivativeCacheAfterSuccess: clearDerivativeCacheAfterSuccess,
            subjectCropMarginFraction: subjectCropMarginFraction,
            subjectMergeDominanceThreshold: subjectMergeDominanceThreshold,
            stageConcurrency: stageConcurrency,
            modelResponseRepairAttempts: modelResponseRepairAttempts,
            gpsContext: gpsContext,
            modelContextWindow: modelContextWindow,
            modelMaxResponseTokens: modelMaxResponseTokens
        )
    }
}
