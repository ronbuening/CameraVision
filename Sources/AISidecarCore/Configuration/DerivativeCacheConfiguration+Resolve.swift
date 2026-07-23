import Foundation

extension ConfigurationResolver {
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

        let fileConfig: DerivativeCacheFileConfig = try loadConfigFile(
            path: selectedConfigPath,
            explicit: explicitConfigPath,
            fileManager: fileManager,
            defaultValue: DerivativeCacheFileConfig()
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
