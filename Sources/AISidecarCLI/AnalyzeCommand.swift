import Foundation
import ArgumentParser
import AISidecarCore

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Analyze one image file or a folder of image files."
    )

    @Argument(help: "Image file or folder to analyze.")
    var inputPath: String

    @Flag(help: "Print the scan result with identities and relative paths, then exit.")
    var dryScan = false

    @Option(help: "Export rendered model-input images into this folder and write a manifest.")
    var exportModelInputs: String?

    @OptionGroup
    var shared: SharedOptions

    mutating func run() async throws {
        let resolved = try ConfigurationResolver.resolve(cli: shared.overrides)

        if dryScan {
            // `--dry-scan` exits after discovery; pipeline-level `--dry-run`
            // still plans sidecars without rendering or writing artifacts.
            let scanner = ImageScanner()
            let result = try scanner.scan(
                inputPath: inputPath,
                recursive: resolved.recursive,
                identityPolicy: resolved.sourceIdentityPolicy
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(result)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        let logger = Logger(minimumLevel: resolved.logLevel, format: resolved.logFormat)
        let interruptionMonitor = InterruptionMonitor()
        interruptionMonitor.installSignalHandlers()
        if let exportModelInputs {
            try ModelInputExportPipeline.validate(configuration: resolved)
            let pipeline = ModelInputExportPipeline(logger: logger)
            _ = try await pipeline.run(
                inputPath: inputPath,
                exportDirectoryPath: exportModelInputs,
                configuration: resolved,
                interruptionMonitor: interruptionMonitor
            )
            return
        }

        let pipeline = AnalyzeShellPipeline(logger: logger)
        _ = try await pipeline.run(
            inputPath: inputPath,
            configuration: resolved,
            interruptionMonitor: interruptionMonitor
        )
    }
}
