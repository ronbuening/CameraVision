import Foundation

/// Resolves run configuration according to the project-wide precedence rules.
public enum ConfigurationResolver {
    /// Default persistent config path required by PW-006.
    public static func defaultConfigPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/Application Support/aisidecar/config.json"
    }

    /// Resolve which config file to load and whether it was explicitly requested.
    ///
    /// Path precedence is CLI `--config` > `AISIDECAR_CONFIG` > caller-injected default >
    /// built-in default. `explicit` is true when the path came from the CLI flag or the environment
    /// variable, so a missing file can be treated as an error only when the user named it directly.
    private static func selectConfigPath(
        cliConfigPath: String?,
        environment: [String: String],
        defaultConfigPath: String?
    ) -> (selected: String, explicit: Bool) {
        let selected = cliConfigPath
            ?? environment["AISIDECAR_CONFIG"]
            ?? defaultConfigPath
            ?? Self.defaultConfigPath(environment: environment)
        let explicit = cliConfigPath != nil || environment["AISIDECAR_CONFIG"] != nil
        return (selected, explicit)
    }

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

        let fileConfig = try loadConfig(
            path: selectedConfigPath,
            explicit: explicitConfigPath,
            fileManager: fileManager
        )
        let envOverrides = try environmentOverrides(from: environment)

        var builder = ConfigurationBuilder(defaults: .builtInDefaults)
        builder.apply(config: fileConfig)
        builder.apply(overrides: envOverrides)
        builder.apply(overrides: cli.withoutConfigPath())
        return try builder.resolved()
    }

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

        let fileConfig = try loadConfig(
            path: selectedConfigPath,
            explicit: explicitConfigPath,
            fileManager: fileManager
        )
        let envOverrides = try xmpEnvironmentOverrides(from: environment)

        var builder = XMPExportConfigurationBuilder(defaults: .builtInDefaults)
        builder.apply(config: fileConfig)
        builder.apply(overrides: envOverrides)
        builder.apply(overrides: cli.withoutConfigPath())
        return try builder.resolved()
    }

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

        let fileConfig = try loadConfig(
            path: selectedConfigPath,
            explicit: explicitConfigPath,
            fileManager: fileManager
        )
        let envOverrides = try normalizationEnvironmentOverrides(from: environment)

        var builder = NormalizationConfigurationBuilder(defaults: .builtInDefaults)
        builder.apply(config: fileConfig)
        builder.apply(overrides: envOverrides)
        builder.apply(overrides: cli.withoutConfigPath())
        return try builder.resolved()
    }

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

        let fileConfig = try loadConfig(
            path: selectedConfigPath,
            explicit: explicitConfigPath,
            fileManager: fileManager
        )
        let envOverrides = try applySessionEnvironmentOverrides(from: environment)

        var builder = ApplySessionConfigurationBuilder(defaults: .builtInDefaults)
        builder.apply(config: fileConfig)
        builder.apply(overrides: envOverrides)
        builder.apply(overrides: cli.withoutConfigPath())
        return try builder.resolved()
    }

    /// Resolve only derivative cache settings for maintenance commands.
    ///
    /// This intentionally avoids validating model/runtime fields so `aisidecar purge`
    /// remains usable even when an analyze-specific config value is temporarily bad.
    public static func resolveDerivativeCache(
        cli: DerivativeCacheConfigurationOverrides = DerivativeCacheConfigurationOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultConfigPath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> ResolvedDerivativeCacheConfiguration {
        let (selectedConfigPath, explicitConfigPath) = selectConfigPath(
            cliConfigPath: cli.configPath,
            environment: environment,
            defaultConfigPath: defaultConfigPath
        )

        let fileConfig = try loadDerivativeCacheConfig(
            path: selectedConfigPath,
            explicit: explicitConfigPath,
            fileManager: fileManager
        )
        let envCacheSize = try int64Value(
            from: environment["AISIDECAR_DERIVATIVE_CACHE_SIZE_BYTES"],
            key: "AISIDECAR_DERIVATIVE_CACHE_SIZE_BYTES"
        )

        var derivativeCacheDir = DerivativeCache.defaultDirectoryPath(environment: environment)
        var derivativeCacheSizeBytes = DerivativeCache.defaultSizeCapBytes

        if let value = fileConfig.derivativeCacheDir { derivativeCacheDir = value }
        if let value = fileConfig.derivativeCacheSizeBytes { derivativeCacheSizeBytes = value }
        if let value = environment["AISIDECAR_DERIVATIVE_CACHE_DIR"] { derivativeCacheDir = value }
        if let value = envCacheSize { derivativeCacheSizeBytes = value }
        if let value = cli.derivativeCacheDir { derivativeCacheDir = value }
        if let value = cli.derivativeCacheSizeBytes { derivativeCacheSizeBytes = value }

        guard derivativeCacheSizeBytes > 0 else {
            throw SidecarError.configInvalid("derivative_cache_size_bytes must be greater than zero")
        }

        return ResolvedDerivativeCacheConfiguration(
            derivativeCacheDir: derivativeCacheDir,
            derivativeCacheSizeBytes: derivativeCacheSizeBytes
        )
    }

    private static func loadConfig(
        path: String,
        explicit: Bool,
        fileManager: FileManager
    ) throws -> AppConfig {
        let lowercasedPath = path.lowercased()
        // PW-006 intentionally keeps the config format to JSON only.
        if lowercasedPath.hasSuffix(".yaml") || lowercasedPath.hasSuffix(".yml") {
            throw SidecarError.configInvalid("YAML configuration is not supported: \(path)")
        }

        guard fileManager.fileExists(atPath: path) else {
            // An implicit default config may be absent on first run; an explicit
            // path is treated as user intent and therefore must exist.
            if explicit {
                throw SidecarError.configInvalid("Configuration file does not exist: \(path)")
            }
            return AppConfig()
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            return try decoder.decode(AppConfig.self, from: data)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError.configInvalid("Invalid configuration file \(path): \(error.localizedDescription)")
        }
    }

    private static func loadDerivativeCacheConfig(
        path: String,
        explicit: Bool,
        fileManager: FileManager
    ) throws -> DerivativeCacheFileConfig {
        let lowercasedPath = path.lowercased()
        if lowercasedPath.hasSuffix(".yaml") || lowercasedPath.hasSuffix(".yml") {
            throw SidecarError.configInvalid("YAML configuration is not supported: \(path)")
        }

        guard fileManager.fileExists(atPath: path) else {
            if explicit {
                throw SidecarError.configInvalid("Configuration file does not exist: \(path)")
            }
            return DerivativeCacheFileConfig()
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONDecoder().decode(DerivativeCacheFileConfig.self, from: data)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError.configInvalid("Invalid configuration file \(path): \(error.localizedDescription)")
        }
    }

    private static func environmentOverrides(from environment: [String: String]) throws -> RunConfigurationOverrides {
        RunConfigurationOverrides(
            mode: try enumValue(AnalysisMode.self, from: environment["AISIDECAR_MODE"], key: "AISIDECAR_MODE"),
            existing: try enumValue(ExistingPolicy.self, from: environment["AISIDECAR_EXISTING"], key: "AISIDECAR_EXISTING"),
            recursive: try boolValue(from: environment["AISIDECAR_RECURSIVE"], key: "AISIDECAR_RECURSIVE"),
            outputDir: environment["AISIDECAR_OUTPUT_DIR"],
            model: environment["AISIDECAR_MODEL"],
            modelEndpoint: environment["AISIDECAR_MODEL_ENDPOINT"],
            modelKeepAlive: environment["AISIDECAR_MODEL_KEEP_ALIVE"],
            profile: environment["AISIDECAR_PROFILE"],
            logLevel: try enumValue(LogLevel.self, from: environment["AISIDECAR_LOG_LEVEL"], key: "AISIDECAR_LOG_LEVEL"),
            logFormat: try enumValue(LogFormat.self, from: environment["AISIDECAR_LOG_FORMAT"], key: "AISIDECAR_LOG_FORMAT"),
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
            )
        )
    }

    private static func xmpEnvironmentOverrides(
        from environment: [String: String]
    ) throws -> XMPExportConfigurationOverrides {
        XMPExportConfigurationOverrides(
            recursive: try boolValue(from: environment["AISIDECAR_RECURSIVE"], key: "AISIDECAR_RECURSIVE"),
            outputDir: environment["AISIDECAR_OUTPUT_DIR"],
            logLevel: try enumValue(LogLevel.self, from: environment["AISIDECAR_LOG_LEVEL"], key: "AISIDECAR_LOG_LEVEL"),
            logFormat: try enumValue(LogFormat.self, from: environment["AISIDECAR_LOG_FORMAT"], key: "AISIDECAR_LOG_FORMAT"),
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
            writeAIJSON: try boolValue(from: environment["AISIDECAR_WRITE_AI_JSON"], key: "AISIDECAR_WRITE_AI_JSON")
        )
    }

    private static func normalizationEnvironmentOverrides(
        from environment: [String: String]
    ) throws -> NormalizationConfigurationOverrides {
        NormalizationConfigurationOverrides(
            recursive: try boolValue(from: environment["AISIDECAR_RECURSIVE"], key: "AISIDECAR_RECURSIVE"),
            outputDir: environment["AISIDECAR_OUTPUT_DIR"],
            logLevel: try enumValue(LogLevel.self, from: environment["AISIDECAR_LOG_LEVEL"], key: "AISIDECAR_LOG_LEVEL"),
            logFormat: try enumValue(LogFormat.self, from: environment["AISIDECAR_LOG_FORMAT"], key: "AISIDECAR_LOG_FORMAT"),
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
            pairScope: try enumValue(XMPPairScope.self, from: environment["AISIDECAR_PAIR_SCOPE"], key: "AISIDECAR_PAIR_SCOPE"),
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
            writeReportPath: environment["AISIDECAR_WRITE_REPORT"]
        )
    }

    private static func applySessionEnvironmentOverrides(
        from environment: [String: String]
    ) throws -> ApplySessionConfigurationOverrides {
        ApplySessionConfigurationOverrides(
            outputDir: environment["AISIDECAR_OUTPUT_DIR"],
            logLevel: try enumValue(LogLevel.self, from: environment["AISIDECAR_LOG_LEVEL"], key: "AISIDECAR_LOG_LEVEL"),
            logFormat: try enumValue(LogFormat.self, from: environment["AISIDECAR_LOG_FORMAT"], key: "AISIDECAR_LOG_FORMAT"),
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
            )
        )
    }

    private static func enumValue<T: RawRepresentable>(
        _ type: T.Type,
        from rawValue: String?,
        key: String
    ) throws -> T? where T.RawValue == String {
        guard let rawValue else {
            return nil
        }
        guard let value = T(rawValue: rawValue) else {
            throw SidecarError.configInvalid("Invalid value for \(key): \(rawValue)")
        }
        return value
    }

    private static func boolValue(from rawValue: String?, key: String) throws -> Bool? {
        guard let rawValue else {
            return nil
        }
        switch rawValue.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            throw SidecarError.configInvalid("Invalid boolean value for \(key): \(rawValue)")
        }
    }

    private static func int64Value(from rawValue: String?, key: String) throws -> Int64? {
        guard let rawValue else {
            return nil
        }
        guard let value = Int64(rawValue), value > 0 else {
            throw SidecarError.configInvalid("Invalid positive integer value for \(key): \(rawValue)")
        }
        return value
    }

    private static func intValue(from rawValue: String?, key: String) throws -> Int? {
        guard let rawValue else {
            return nil
        }
        guard let value = Int(rawValue), value > 0 else {
            throw SidecarError.configInvalid("Invalid positive integer value for \(key): \(rawValue)")
        }
        return value
    }

    private static func nonNegativeIntValue(from rawValue: String?, key: String) throws -> Int? {
        guard let rawValue else {
            return nil
        }
        guard let value = Int(rawValue), value >= 0 else {
            throw SidecarError.configInvalid("Invalid non-negative integer value for \(key): \(rawValue)")
        }
        return value
    }

    private static func doubleValue(from rawValue: String?, key: String) throws -> Double? {
        guard let rawValue else {
            return nil
        }
        guard let value = Double(rawValue), value.isFinite else {
            throw SidecarError.configInvalid("Invalid finite decimal value for \(key): \(rawValue)")
        }
        return value
    }
}

private struct DerivativeCacheFileConfig: Decodable {
    var derivativeCacheDir: String?
    var derivativeCacheSizeBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case derivativeCacheDir = "derivative_cache_dir"
        case derivativeCacheSizeBytes = "derivative_cache_size_bytes"
    }

    init(derivativeCacheDir: String? = nil, derivativeCacheSizeBytes: Int64? = nil) {
        self.derivativeCacheDir = derivativeCacheDir
        self.derivativeCacheSizeBytes = derivativeCacheSizeBytes
    }
}

/// Overlay an optional candidate onto a required builder field, leaving it unchanged when the
/// candidate is nil. Centralizes the config/override precedence step so each field is one explicit
/// `merge` instead of a repeated `if let value = source.field { field = value }` block.
private func merge<Value>(_ destination: inout Value, _ candidate: Value?) {
    if let candidate {
        destination = candidate
    }
}

/// Overlay onto an optional destination field, preserving the same "skip when the candidate is
/// absent" semantics (a nil candidate never clears an existing value).
private func merge<Value>(_ destination: inout Value?, _ candidate: Value?) {
    if let candidate {
        destination = candidate
    }
}

private struct ConfigurationBuilder {
    private var mode: AnalysisMode
    private var existing: ExistingPolicy
    private var recursive: Bool
    private var outputDir: String?
    private var model: String
    private var modelEndpoint: String
    private var modelKeepAlive: String
    private var profile: String
    private var logLevel: LogLevel
    private var logFormat: LogFormat
    private var dryRun: Bool
    private var debugDerivatives: Bool
    private var sourceIdentityPolicy: SourceIdentityPolicy
    private var derivativeCacheDir: String
    private var derivativeCacheSizeBytes: Int64
    private var clearDerivativeCacheOnStart: Bool
    private var clearDerivativeCacheAfterSuccess: Bool
    private var subjectCropMarginFraction: Double
    private var subjectMergeDominanceThreshold: Double
    private var stageConcurrency: Int
    private var modelResponseRepairAttempts: Int
    private var gpsContext: GPSContextMode

    init(defaults: ResolvedRunConfiguration) {
        self.mode = defaults.mode
        self.existing = defaults.existing
        self.recursive = defaults.recursive
        self.outputDir = defaults.outputDir
        self.model = defaults.model
        self.modelEndpoint = defaults.modelEndpoint.absoluteString
        self.modelKeepAlive = defaults.modelKeepAlive
        self.profile = defaults.profile
        self.logLevel = defaults.logLevel
        self.logFormat = defaults.logFormat
        self.dryRun = defaults.dryRun
        self.debugDerivatives = defaults.debugDerivatives
        self.sourceIdentityPolicy = defaults.sourceIdentityPolicy
        self.derivativeCacheDir = defaults.derivativeCacheDir
        self.derivativeCacheSizeBytes = defaults.derivativeCacheSizeBytes
        self.clearDerivativeCacheOnStart = defaults.clearDerivativeCacheOnStart
        self.clearDerivativeCacheAfterSuccess = defaults.clearDerivativeCacheAfterSuccess
        self.subjectCropMarginFraction = defaults.subjectCropMarginFraction
        self.subjectMergeDominanceThreshold = defaults.subjectMergeDominanceThreshold
        self.stageConcurrency = defaults.stageConcurrency
        self.modelResponseRepairAttempts = defaults.modelResponseRepairAttempts
        self.gpsContext = defaults.gpsContext
    }

    mutating func apply(config: AppConfig) {
        merge(&mode, config.mode)
        merge(&existing, config.existing)
        merge(&recursive, config.recursive)
        merge(&outputDir, config.outputDir)
        merge(&model, config.model)
        merge(&modelEndpoint, config.modelEndpoint)
        merge(&modelKeepAlive, config.modelKeepAlive)
        merge(&profile, config.profile)
        merge(&logLevel, config.logLevel)
        merge(&logFormat, config.logFormat)
        merge(&dryRun, config.dryRun)
        merge(&debugDerivatives, config.debugDerivatives)
        merge(&sourceIdentityPolicy, config.sourceIdentityPolicy)
        merge(&derivativeCacheDir, config.derivativeCacheDir)
        merge(&derivativeCacheSizeBytes, config.derivativeCacheSizeBytes)
        merge(&clearDerivativeCacheOnStart, config.clearDerivativeCacheOnStart)
        merge(&clearDerivativeCacheAfterSuccess, config.clearDerivativeCacheAfterSuccess)
        merge(&subjectCropMarginFraction, config.subjectCropMarginFraction)
        merge(&subjectMergeDominanceThreshold, config.subjectMergeDominanceThreshold)
        merge(&stageConcurrency, config.stageConcurrency)
        merge(&modelResponseRepairAttempts, config.modelResponseRepairAttempts)
        merge(&gpsContext, config.gpsContext)
    }

    mutating func apply(overrides: RunConfigurationOverrides) {
        merge(&mode, overrides.mode)
        merge(&existing, overrides.existing)
        merge(&recursive, overrides.recursive)
        merge(&outputDir, overrides.outputDir)
        merge(&model, overrides.model)
        merge(&modelEndpoint, overrides.modelEndpoint)
        merge(&modelKeepAlive, overrides.modelKeepAlive)
        merge(&profile, overrides.profile)
        merge(&logLevel, overrides.logLevel)
        merge(&logFormat, overrides.logFormat)
        merge(&dryRun, overrides.dryRun)
        merge(&debugDerivatives, overrides.debugDerivatives)
        merge(&sourceIdentityPolicy, overrides.sourceIdentityPolicy)
        merge(&derivativeCacheDir, overrides.derivativeCacheDir)
        merge(&derivativeCacheSizeBytes, overrides.derivativeCacheSizeBytes)
        merge(&clearDerivativeCacheOnStart, overrides.clearDerivativeCacheOnStart)
        merge(&clearDerivativeCacheAfterSuccess, overrides.clearDerivativeCacheAfterSuccess)
        merge(&subjectCropMarginFraction, overrides.subjectCropMarginFraction)
        merge(&subjectMergeDominanceThreshold, overrides.subjectMergeDominanceThreshold)
        merge(&stageConcurrency, overrides.stageConcurrency)
        merge(&modelResponseRepairAttempts, overrides.modelResponseRepairAttempts)
        merge(&gpsContext, overrides.gpsContext)
    }

    func resolved() throws -> ResolvedRunConfiguration {
        guard let endpoint = URL(string: modelEndpoint),
              let scheme = endpoint.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              endpoint.host != nil
        else {
            throw SidecarError.configInvalid("Invalid model endpoint URL: \(modelEndpoint)")
        }
        guard !modelKeepAlive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SidecarError.configInvalid("model_keep_alive must not be empty")
        }
        _ = try ModelInputProfileRegistry.resolve(name: profile)
        guard derivativeCacheSizeBytes > 0 else {
            throw SidecarError.configInvalid("derivative_cache_size_bytes must be greater than zero")
        }
        guard subjectCropMarginFraction > 0, subjectCropMarginFraction <= 1, subjectCropMarginFraction.isFinite else {
            throw SidecarError.configInvalid("subject_crop_margin_fraction must be greater than zero and at most one")
        }
        guard subjectMergeDominanceThreshold > 0,
              subjectMergeDominanceThreshold <= 1,
              subjectMergeDominanceThreshold.isFinite
        else {
            throw SidecarError.configInvalid("subject_merge_dominance_threshold must be greater than zero and at most one")
        }
        guard stageConcurrency > 0 else {
            throw SidecarError.configInvalid("stage_concurrency must be greater than zero")
        }
        guard modelResponseRepairAttempts >= 0 else {
            throw SidecarError.configInvalid("model_response_repair_attempts must be zero or greater")
        }

        return ResolvedRunConfiguration(
            mode: mode,
            existing: existing,
            recursive: recursive,
            outputDir: outputDir,
            model: model,
            modelEndpoint: endpoint,
            modelKeepAlive: modelKeepAlive,
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
            gpsContext: gpsContext
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
    }

    func resolved() throws -> ResolvedXMPExportConfiguration {
        if xmpConflictPolicy == .backupAndMerge, !backupSidecars {
            throw SidecarError.configInvalid("xmp_conflict_policy backup-and-merge requires backup_sidecars to be true")
        }

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
            writeAIJSON: writeAIJSON
        )
    }
}

private struct NormalizationConfigurationBuilder {
    private var config: ResolvedNormalizationConfiguration
    private var vocabularyModeWasSet = false

    init(defaults: ResolvedNormalizationConfiguration) {
        self.config = defaults
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
        return config
    }
}

private struct ApplySessionConfigurationBuilder {
    private var config: ResolvedApplySessionConfiguration

    init(defaults: ResolvedApplySessionConfiguration) {
        self.config = defaults
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
    }

    func resolved() throws -> ResolvedApplySessionConfiguration {
        if config.xmpConflictPolicy == .backupAndMerge, !config.backupSidecars {
            throw SidecarError.configInvalid("xmp_conflict_policy backup-and-merge requires backup_sidecars to be true")
        }
        return config
    }
}

private extension RunConfigurationOverrides {
    func withoutConfigPath() -> RunConfigurationOverrides {
        // The selected config path controls which file is read, but it is not a
        // persisted run value and should not participate in provenance.
        RunConfigurationOverrides(
            mode: mode,
            existing: existing,
            recursive: recursive,
            outputDir: outputDir,
            model: model,
            modelEndpoint: modelEndpoint,
            modelKeepAlive: modelKeepAlive,
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
            gpsContext: gpsContext
        )
    }
}

private extension XMPExportConfigurationOverrides {
    func withoutConfigPath() -> XMPExportConfigurationOverrides {
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
            writeAIJSON: writeAIJSON
        )
    }
}

private extension NormalizationConfigurationOverrides {
    func withoutConfigPath() -> NormalizationConfigurationOverrides {
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
            writeReportPath: writeReportPath
        )
    }
}

private extension ApplySessionConfigurationOverrides {
    func withoutConfigPath() -> ApplySessionConfigurationOverrides {
        ApplySessionConfigurationOverrides(
            outputDir: outputDir,
            logLevel: logLevel,
            logFormat: logFormat,
            dryRun: dryRun,
            sourceRoot: sourceRoot,
            sourceVerification: sourceVerification,
            backupSidecars: backupSidecars,
            xmpConflictPolicy: xmpConflictPolicy,
            allowStale: allowStale
        )
    }
}
