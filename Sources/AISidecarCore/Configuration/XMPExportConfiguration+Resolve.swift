import Foundation

extension ConfigurationResolver {
    /// Resolve Phase 2 export settings without changing Phase 1 run provenance.
    ///
    /// This path accepts shared CLI defaults used by `write-xmp --from-json`
    /// without validating model/runtime-only settings that are irrelevant there.
    public static func resolveXMPExport(
        cli: XMPExportConfigurationOverrides = XMPExportConfigurationOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultConfigPath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> ResolvedXMPExportConfiguration {
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
        let envOverrides = try xmpEnvironmentOverrides(from: environment)

        var builder = XMPExportConfigurationBuilder(defaults: .builtInDefaults)
        builder.apply(config: fileConfig)
        builder.apply(overrides: envOverrides)
        builder.apply(overrides: cli.withoutConfigPath())
        return try builder.resolved()
    }

    private static func xmpEnvironmentOverrides(
        from environment: [String: String]
    ) throws -> XMPExportConfigurationOverrides {
        XMPExportConfigurationOverrides(
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
                XMPPairScope.self,
                from: environment["AISIDECAR_PAIR_SCOPE"],
                key: "AISIDECAR_PAIR_SCOPE"
            ),
            writeAIJSON: try boolValue(
                from: environment["AISIDECAR_WRITE_AI_JSON"],
                key: "AISIDECAR_WRITE_AI_JSON"
            ),
            qualityGrading: try qualityGradingEnvironmentOverrides(from: environment)
        )
    }
}

private struct XMPExportConfigurationBuilder {
    private var recursive: Bool
    private var outputDir: String?
    private var logLevel: LogLevel
    private var logFormat: LogFormat
    private var dryRun: Bool
    private var sourceRoot: String?
    private var sourceVerification: XMPSourceVerificationPolicy
    private var writeFlatKeywords: Bool
    private var writeHierarchicalKeywords: Bool
    private var backupSidecars: Bool
    private var xmpConflictPolicy: XMPConflictPolicy
    private var minConfidence: XMPMinimumConfidence
    private var allowSpecificTags: Bool
    private var pairScope: XMPPairScope
    private var writeAIJSON: Bool
    private var qualityGrading: QualityGradingConfigurationBuilder

    init(defaults: ResolvedXMPExportConfiguration) {
        self.recursive = defaults.recursive
        self.outputDir = defaults.outputDir
        self.logLevel = defaults.logLevel
        self.logFormat = defaults.logFormat
        self.dryRun = defaults.dryRun
        self.sourceRoot = defaults.sourceRoot
        self.sourceVerification = defaults.sourceVerification
        self.writeFlatKeywords = defaults.writeFlatKeywords
        self.writeHierarchicalKeywords = defaults.writeHierarchicalKeywords
        self.backupSidecars = defaults.backupSidecars
        self.xmpConflictPolicy = defaults.xmpConflictPolicy
        self.minConfidence = defaults.minConfidence
        self.allowSpecificTags = defaults.allowSpecificTags
        self.pairScope = defaults.pairScope
        self.writeAIJSON = defaults.writeAIJSON
        self.qualityGrading = QualityGradingConfigurationBuilder(defaults: defaults.qualityGrading)
    }

    mutating func apply(config: AppConfig) {
        merge(&recursive, config.recursive)
        merge(&outputDir, config.outputDir)
        merge(&logLevel, config.logLevel)
        merge(&logFormat, config.logFormat)
        merge(&dryRun, config.dryRun)
        merge(&sourceRoot, config.sourceRoot)
        merge(&sourceVerification, config.sourceVerification)
        merge(&writeFlatKeywords, config.writeFlatKeywords)
        merge(&writeHierarchicalKeywords, config.writeHierarchicalKeywords)
        merge(&backupSidecars, config.backupSidecars)
        merge(&xmpConflictPolicy, config.xmpConflictPolicy)
        merge(&minConfidence, config.minConfidence)
        merge(&allowSpecificTags, config.allowSpecificTags)
        merge(&pairScope, config.pairScope)
        merge(&writeAIJSON, config.writeAIJSON)
        qualityGrading.apply(config: config)
    }

    mutating func apply(overrides: XMPExportConfigurationOverrides) {
        merge(&recursive, overrides.recursive)
        merge(&outputDir, overrides.outputDir)
        merge(&logLevel, overrides.logLevel)
        merge(&logFormat, overrides.logFormat)
        merge(&dryRun, overrides.dryRun)
        merge(&sourceRoot, overrides.sourceRoot)
        merge(&sourceVerification, overrides.sourceVerification)
        merge(&writeFlatKeywords, overrides.writeFlatKeywords)
        merge(&writeHierarchicalKeywords, overrides.writeHierarchicalKeywords)
        merge(&backupSidecars, overrides.backupSidecars)
        merge(&xmpConflictPolicy, overrides.xmpConflictPolicy)
        merge(&minConfidence, overrides.minConfidence)
        merge(&allowSpecificTags, overrides.allowSpecificTags)
        merge(&pairScope, overrides.pairScope)
        merge(&writeAIJSON, overrides.writeAIJSON)
        qualityGrading.apply(overrides: overrides.qualityGrading)
    }

    func resolved() throws -> ResolvedXMPExportConfiguration {
        if xmpConflictPolicy == .backupAndMerge, !backupSidecars {
            throw SidecarError.configInvalid("xmp_conflict_policy backup-and-merge requires backup_sidecars to be true")
        }

        let resolvedQualityGrading = try qualityGrading.resolved()
        return ResolvedXMPExportConfiguration(
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
            qualityGrading: resolvedQualityGrading
        )
    }
}

extension XMPExportConfigurationOverrides {
    fileprivate func withoutConfigPath() -> XMPExportConfigurationOverrides {
        // Match the Phase 1 resolver: the selected config path is read input,
        // not part of the resolved operational settings.
        XMPExportConfigurationOverrides(
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
            qualityGrading: qualityGrading
        )
    }
}
