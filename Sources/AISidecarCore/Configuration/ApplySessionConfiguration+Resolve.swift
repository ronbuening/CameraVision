import Foundation

extension ConfigurationResolver {
    /// Resolve model-free `apply-session` write-safety settings.
    ///
    /// `allow-stale` is accepted only from the explicit invocation override;
    /// FR3-030b forbids persistent config defaults for stale-session writes.
    public static func resolveApplySession(
        cli: ApplySessionConfigurationOverrides = ApplySessionConfigurationOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultConfigPath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> ResolvedApplySessionConfiguration {
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
        let envOverrides = try applySessionEnvironmentOverrides(from: environment)

        var builder = ApplySessionConfigurationBuilder(defaults: .builtInDefaults)
        builder.apply(config: fileConfig)
        builder.apply(overrides: envOverrides)
        builder.apply(overrides: cli.withoutConfigPath())
        return try builder.resolved()
    }

    private static func applySessionEnvironmentOverrides(
        from environment: [String: String]
    ) throws -> ApplySessionConfigurationOverrides {
        ApplySessionConfigurationOverrides(
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
            backupSidecars: try boolValue(
                from: environment["AISIDECAR_BACKUP_SIDECARS"],
                key: "AISIDECAR_BACKUP_SIDECARS"
            ),
            xmpConflictPolicy: try enumValue(
                XMPConflictPolicy.self,
                from: environment["AISIDECAR_XMP_CONFLICT_POLICY"],
                key: "AISIDECAR_XMP_CONFLICT_POLICY"
            ),
            qualityGrading: try qualityGradingEnvironmentOverrides(from: environment)
        )
    }
}

private struct ApplySessionConfigurationBuilder {
    private var config: ResolvedApplySessionConfiguration
    private var qualityGrading: QualityGradingConfigurationBuilder

    init(defaults: ResolvedApplySessionConfiguration) {
        self.config = defaults
        self.qualityGrading = QualityGradingConfigurationBuilder(defaults: defaults.qualityGrading)
    }

    mutating func apply(config fileConfig: AppConfig) {
        merge(&config.outputDir, fileConfig.outputDir)
        merge(&config.logLevel, fileConfig.logLevel)
        merge(&config.logFormat, fileConfig.logFormat)
        merge(&config.dryRun, fileConfig.dryRun)
        merge(&config.sourceRoot, fileConfig.sourceRoot)
        merge(&config.sourceVerification, fileConfig.sourceVerification)
        merge(&config.backupSidecars, fileConfig.backupSidecars)
        merge(&config.xmpConflictPolicy, fileConfig.xmpConflictPolicy)
        qualityGrading.apply(config: fileConfig)
    }

    mutating func apply(overrides: ApplySessionConfigurationOverrides) {
        merge(&config.outputDir, overrides.outputDir)
        merge(&config.logLevel, overrides.logLevel)
        merge(&config.logFormat, overrides.logFormat)
        merge(&config.dryRun, overrides.dryRun)
        merge(&config.sourceRoot, overrides.sourceRoot)
        merge(&config.sourceVerification, overrides.sourceVerification)
        merge(&config.backupSidecars, overrides.backupSidecars)
        merge(&config.xmpConflictPolicy, overrides.xmpConflictPolicy)
        merge(&config.allowStale, overrides.allowStale)
        qualityGrading.apply(overrides: overrides.qualityGrading)
    }

    func resolved() throws -> ResolvedApplySessionConfiguration {
        if config.xmpConflictPolicy == .backupAndMerge, !config.backupSidecars {
            throw SidecarError.configInvalid("xmp_conflict_policy backup-and-merge requires backup_sidecars to be true")
        }
        var resolved = config
        resolved.qualityGrading = try qualityGrading.resolved()
        return resolved
    }
}

extension ApplySessionConfigurationOverrides {
    fileprivate func withoutConfigPath() -> ApplySessionConfigurationOverrides {
        ApplySessionConfigurationOverrides(
            outputDir: outputDir,
            logLevel: logLevel,
            logFormat: logFormat,
            dryRun: dryRun,
            sourceRoot: sourceRoot,
            sourceVerification: sourceVerification,
            backupSidecars: backupSidecars,
            xmpConflictPolicy: xmpConflictPolicy,
            allowStale: allowStale,
            qualityGrading: qualityGrading
        )
    }
}
