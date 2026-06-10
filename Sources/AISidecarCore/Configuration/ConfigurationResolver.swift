import Foundation

public enum ConfigurationResolver {
    public static func defaultConfigPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/Application Support/aisidecar/config.json"
    }

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

    private static func loadConfig(
        path: String,
        explicit: Bool,
        fileManager: FileManager
    ) throws -> AppConfig {
        let lowercasedPath = path.lowercased()
        if lowercasedPath.hasSuffix(".yaml") || lowercasedPath.hasSuffix(".yml") {
            throw SidecarError.configInvalid("YAML configuration is not supported: \(path)")
        }

        guard fileManager.fileExists(atPath: path) else {
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
    }

    func resolved() throws -> ResolvedRunConfiguration {
        guard let endpoint = URL(string: modelEndpoint),
              let scheme = endpoint.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              endpoint.host != nil
        else {
            throw SidecarError.configInvalid("Invalid model endpoint URL: \(modelEndpoint)")
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
            sourceIdentityPolicy: sourceIdentityPolicy
        )
    }
}

private extension RunConfigurationOverrides {
    func withoutConfigPath() -> RunConfigurationOverrides {
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
            sourceIdentityPolicy: sourceIdentityPolicy
        )
    }
}
