import Foundation

/// Resolves run configuration according to the project-wide precedence rules.
public enum ConfigurationResolver {
    /// Default persistent config path required by PW-006.
    public static func defaultConfigPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String
    {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/Application Support/aisidecar/config.json"
    }
}
