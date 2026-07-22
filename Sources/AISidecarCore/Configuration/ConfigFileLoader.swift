import Foundation

extension ConfigurationResolver {
    /// Resolve which config file to load and whether it was explicitly requested.
    ///
    /// Path precedence is CLI `--config` > `AISIDECAR_CONFIG` > caller-injected default >
    /// built-in default. `explicit` is true when the path came from the CLI flag or the environment
    /// variable, so a missing file can be treated as an error only when the user named it directly.
    static func selectConfigPath(
        cliConfigPath: String?,
        environment: [String: String],
        defaultConfigPath: String?
    ) -> (selected: String, explicit: Bool) {
        let selected =
            cliConfigPath
            ?? environment["AISIDECAR_CONFIG"]
            ?? defaultConfigPath
            ?? Self.defaultConfigPath(environment: environment)
        let explicit = cliConfigPath != nil || environment["AISIDECAR_CONFIG"] != nil
        return (selected, explicit)
    }

    static func loadConfigFile<Config: Decodable>(
        path: String,
        explicit: Bool,
        fileManager: FileManager,
        defaultValue: @autoclosure () -> Config
    ) throws -> Config {
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
            return defaultValue()
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            return try decoder.decode(Config.self, from: data)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError.configInvalid("Invalid configuration file \(path): \(error.localizedDescription)")
        }
    }
}
