import Foundation
import ArgumentParser
import AISidecarCore

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct PurgeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "purge",
        abstract: "Purge cached derivative artifacts."
    )

    @Option(help: "Alternate JSON configuration file.")
    var config: String?

    @Option(help: "Derivative cache directory to purge.")
    var cacheDir: String?

    mutating func run() throws {
        let resolved = try ConfigurationResolver.resolveDerivativeCache(
            cli: DerivativeCacheConfigurationOverrides(
                configPath: config,
                derivativeCacheDir: cacheDir
            )
        )
        let cache = DerivativeCache(
            directoryPath: resolved.derivativeCacheDir,
            sizeCapBytes: resolved.derivativeCacheSizeBytes
        )
        let result = try cache.purge()
        let message = "Purged derivative cache at \(result.directoryPath) (\(result.removedFileCount) files removed).\n"
        FileHandle.standardOutput.write(Data(message.utf8))
    }
}
