import Foundation

/// Resolves run configuration according to the project-wide precedence rules.
public enum ConfigurationResolver {
    /// Default persistent config path required by PW-006.
    public static func defaultConfigPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/Application Support/aisidecar/config.json"
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
        let selectedConfigPath = cli.configPath
            ?? environment["AISIDECAR_CONFIG"]
            ?? defaultConfigPath
            ?? Self.defaultConfigPath(environment: environment)
        let explicitConfigPath = cli.configPath != nil || environment["AISIDECAR_CONFIG"] != nil

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
        let selectedConfigPath = cli.configPath
            ?? environment["AISIDECAR_CONFIG"]
            ?? defaultConfigPath
            ?? Self.defaultConfigPath(environment: environment)
        let explicitConfigPath = cli.configPath != nil || environment["AISIDECAR_CONFIG"] != nil

        let fileConfig = try loadConfig(
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

    private static func environmentOverrides(from environment: [String: String]) throws -> RunConfigurationOverrides {
        RunConfigurationOverrides(
            mode: try enumValue(AnalysisMode.self, from: environment["AISIDECAR_MODE"], key: "AISIDECAR_MODE"),
            existing: try enumValue(ExistingPolicy.self, from: environment["AISIDECAR_EXISTING"], key: "AISIDECAR_EXISTING"),
            recursive: try boolValue(from: environment["AISIDECAR_RECURSIVE"], key: "AISIDECAR_RECURSIVE"),
            outputDir: environment["AISIDECAR_OUTPUT_DIR"],
            model: environment["AISIDECAR_MODEL"],
            modelEndpoint: environment["AISIDECAR_MODEL_ENDPOINT"],
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

private struct ConfigurationBuilder {
    private var mode: AnalysisMode
    private var existing: ExistingPolicy
    private var recursive: Bool
    private var outputDir: String?
    private var model: String
    private var modelEndpoint: String
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

    init(defaults: ResolvedRunConfiguration) {
        self.mode = defaults.mode
        self.existing = defaults.existing
        self.recursive = defaults.recursive
        self.outputDir = defaults.outputDir
        self.model = defaults.model
        self.modelEndpoint = defaults.modelEndpoint.absoluteString
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
    }

    mutating func apply(config: AppConfig) {
        if let value = config.mode { mode = value }
        if let value = config.existing { existing = value }
        if let value = config.recursive { recursive = value }
        if let value = config.outputDir { outputDir = value }
        if let value = config.model { model = value }
        if let value = config.modelEndpoint { modelEndpoint = value }
        if let value = config.profile { profile = value }
        if let value = config.logLevel { logLevel = value }
        if let value = config.logFormat { logFormat = value }
        if let value = config.dryRun { dryRun = value }
        if let value = config.debugDerivatives { debugDerivatives = value }
        if let value = config.sourceIdentityPolicy { sourceIdentityPolicy = value }
        if let value = config.derivativeCacheDir { derivativeCacheDir = value }
        if let value = config.derivativeCacheSizeBytes { derivativeCacheSizeBytes = value }
        if let value = config.clearDerivativeCacheOnStart { clearDerivativeCacheOnStart = value }
        if let value = config.clearDerivativeCacheAfterSuccess { clearDerivativeCacheAfterSuccess = value }
        if let value = config.subjectCropMarginFraction { subjectCropMarginFraction = value }
        if let value = config.subjectMergeDominanceThreshold { subjectMergeDominanceThreshold = value }
        if let value = config.stageConcurrency { stageConcurrency = value }
        if let value = config.modelResponseRepairAttempts { modelResponseRepairAttempts = value }
    }

    mutating func apply(overrides: RunConfigurationOverrides) {
        if let value = overrides.mode { mode = value }
        if let value = overrides.existing { existing = value }
        if let value = overrides.recursive { recursive = value }
        if let value = overrides.outputDir { outputDir = value }
        if let value = overrides.model { model = value }
        if let value = overrides.modelEndpoint { modelEndpoint = value }
        if let value = overrides.profile { profile = value }
        if let value = overrides.logLevel { logLevel = value }
        if let value = overrides.logFormat { logFormat = value }
        if let value = overrides.dryRun { dryRun = value }
        if let value = overrides.debugDerivatives { debugDerivatives = value }
        if let value = overrides.sourceIdentityPolicy { sourceIdentityPolicy = value }
        if let value = overrides.derivativeCacheDir { derivativeCacheDir = value }
        if let value = overrides.derivativeCacheSizeBytes { derivativeCacheSizeBytes = value }
        if let value = overrides.clearDerivativeCacheOnStart { clearDerivativeCacheOnStart = value }
        if let value = overrides.clearDerivativeCacheAfterSuccess { clearDerivativeCacheAfterSuccess = value }
        if let value = overrides.subjectCropMarginFraction { subjectCropMarginFraction = value }
        if let value = overrides.subjectMergeDominanceThreshold { subjectMergeDominanceThreshold = value }
        if let value = overrides.stageConcurrency { stageConcurrency = value }
        if let value = overrides.modelResponseRepairAttempts { modelResponseRepairAttempts = value }
    }

    func resolved() throws -> ResolvedRunConfiguration {
        guard let endpoint = URL(string: modelEndpoint),
              let scheme = endpoint.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              endpoint.host != nil
        else {
            throw SidecarError.configInvalid("Invalid model endpoint URL: \(modelEndpoint)")
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
            modelResponseRepairAttempts: modelResponseRepairAttempts
        )
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
            modelResponseRepairAttempts: modelResponseRepairAttempts
        )
    }
}
