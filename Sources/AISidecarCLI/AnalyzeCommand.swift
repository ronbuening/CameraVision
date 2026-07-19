import AISidecarCore
import ArgumentParser
import Foundation

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Analyze one image file or a folder of image files.",
        discussion: BatchExitHelp.discussion
    )

    @Argument(help: "Image file or folder to analyze.")
    var inputPath: String

    @Flag(help: "Print the scan result with identities and relative paths, then exit.")
    var dryScan = false

    @Flag(
        help:
            "Also produce a perceptual quality assessment per image (adds the quality_assessment block to raw sidecars)."
    )
    var assessQuality = false

    @Option(
        help:
            "With --assess-quality: 'combined' assesses in the tagging model call; 'sequential' runs a dedicated second pass that writes .quality.ai.json sidecars and keeps tagging output identical to a run without assessment."
    )
    var qualityScanMode: QualityScanMode?

    @Option(help: "Export rendered model-input images into this folder and write a manifest.")
    var exportModelInputs: String?

    @OptionGroup
    var shared: SharedOptions

    mutating func run() async throws {
        var overrides = shared.overrides
        overrides.qualityAssessment = assessQuality ? true : nil
        overrides.qualityScanMode = qualityScanMode
        let resolved = try ConfigurationResolver.resolve(cli: overrides)

        if dryScan {
            let cache = DerivativeCache(
                directoryPath: resolved.derivativeCacheDir,
                sizeCapBytes: resolved.derivativeCacheSizeBytes
            )
            if resolved.clearDerivativeCacheOnStart {
                try cache.clear()
            }
            // `--dry-scan` exits after discovery; pipeline-level `--dry-run`
            // still plans sidecars without rendering or writing artifacts.
            let scanner = ImageScanner()
            let result = try scanner.scan(
                inputPath: inputPath,
                recursive: resolved.recursive,
                identityPolicy: resolved.sourceIdentityPolicy
            )
            let encoder = JSONCoding.jsonlEncoder()
            let data = try encoder.encode(result)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            if resolved.clearDerivativeCacheAfterSuccess {
                try cache.clear()
            }
            return
        }

        let logger = Logger(minimumLevel: resolved.logLevel, format: resolved.logFormat)
        let interruptionMonitor = InterruptionMonitor()
        interruptionMonitor.installSignalHandlers()
        if let exportModelInputs {
            try ModelInputExportPipeline.validate(configuration: resolved)
            let pipeline = ModelInputExportPipeline(logger: logger)
            let result = try await withAsyncBatchInterruptionExit {
                try await pipeline.run(
                    inputPath: inputPath,
                    exportDirectoryPath: exportModelInputs,
                    configuration: resolved,
                    interruptionMonitor: interruptionMonitor
                )
            }
            try enforceBatchExitPolicy(
                failureCount: result.records.filter { $0.status == .failed }.count,
                interrupted: result.interrupted
            )
            return
        }

        let pipeline = AnalyzePipeline(logger: logger, runner: OllamaVisionRunner())
        let result = try await withAsyncBatchInterruptionExit {
            try await pipeline.run(
                inputPath: inputPath,
                configuration: resolved,
                interruptionMonitor: interruptionMonitor
            )
        }
        try enforceBatchExitPolicy(
            failureCount: result.records.filter { $0.status == .failed }.count,
            interrupted: result.interrupted
        )
    }
}
