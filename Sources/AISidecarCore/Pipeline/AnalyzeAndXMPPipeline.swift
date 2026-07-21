import Foundation

/// Result of analyze-and-write, carrying both Phase 1 analysis and Phase 2 export outcomes.
public struct AnalyzeAndXMPResult: Sendable, Equatable {
    public var analyzeResult: AnalyzeResult
    public var exportResult: XMPExportPipelineResult

    public init(analyzeResult: AnalyzeResult, exportResult: XMPExportPipelineResult) {
        self.analyzeResult = analyzeResult
        self.exportResult = exportResult
    }
}

/// Thin adapter from Phase 1 analysis into the shared Phase 2 XMP export pipeline.
public struct AnalyzeAndXMPPipeline {
    private let fileManager: FileManager
    private let analyzePipeline: AnalyzePipeline
    private let exportPipeline: XMPExportPipeline
    private let logger: Logger
    private let preScanRawSidecars: (@Sendable (String, ResolvedRunConfiguration) throws -> Set<String>)?

    public init(
        fileManager: FileManager = .default,
        analyzePipeline: AnalyzePipeline? = nil,
        exportPipeline: XMPExportPipeline? = nil,
        logger: Logger = Logger(),
        maskProvider: (any ForegroundMaskProvider)? = nil,
        runner: any VisionModelRunner = OllamaVisionRunner(),
        now: @escaping @Sendable () -> Date = Date.init,
        preScanRawSidecars: (@Sendable (String, ResolvedRunConfiguration) throws -> Set<String>)? = nil
    ) {
        self.fileManager = fileManager
        self.analyzePipeline =
            analyzePipeline
            ?? AnalyzePipeline(
                fileManager: fileManager,
                logger: logger,
                maskProvider: maskProvider,
                runner: runner,
                now: now
            )
        self.exportPipeline =
            exportPipeline
            ?? XMPExportPipeline(
                fileManager: fileManager,
                logger: logger,
                now: now
            )
        self.logger = logger
        self.preScanRawSidecars = preScanRawSidecars
    }

    /// Run Phase 1 analysis, then export successful raw sidecars through the shared XMP path.
    public func run(
        inputPath: String,
        runConfiguration: ResolvedRunConfiguration,
        exportConfiguration: ResolvedXMPExportConfiguration,
        interruptionMonitor: InterruptionMonitor? = nil
    ) async throws -> AnalyzeAndXMPResult {
        var preexistingRawSidecars: Set<String> = []
        var preScanFailed = false
        if !exportConfiguration.writeAIJSON {
            do {
                preexistingRawSidecars = try RawSidecarBatchHelpers.plannedRawSidecarPaths(
                    inputPath: inputPath,
                    configuration: runConfiguration,
                    fileManager: fileManager,
                    preScanRawSidecars: preScanRawSidecars
                )
            } catch {
                preScanFailed = true
                RawSidecarBatchHelpers.logCleanupWarning(
                    "Raw-sidecar pre-scan failed; keeping all raw sidecars.",
                    error: error,
                    logger: logger
                )
            }
        }
        var analyzeConfiguration = runConfiguration
        let shouldClearDerivativeCacheAfterOverallSuccess = analyzeConfiguration.clearDerivativeCacheAfterSuccess
        analyzeConfiguration.clearDerivativeCacheAfterSuccess = false

        let analyzeResult = try await analyzePipeline.run(
            inputPath: inputPath,
            configuration: analyzeConfiguration,
            interruptionMonitor: interruptionMonitor
        )
        let batch = RawSidecarBatchHelpers.rawInputBatch(
            from: analyzeResult,
            failureContext: "XMP export",
            fileManager: fileManager
        )

        if !exportConfiguration.writeAIJSON, !preScanFailed {
            RawSidecarBatchHelpers.removeNewRawSidecars(
                from: analyzeResult,
                preexistingRawSidecars: preexistingRawSidecars,
                fileManager: fileManager,
                logger: logger
            )
        }

        let exportResult = try exportPipeline.runResolvedInputs(
            batch,
            inputPath: URL(fileURLWithPath: inputPath).standardizedFileURL.path,
            configuration: exportConfiguration,
            writesBatchArtifacts: analyzeResult.scanResult.inputPath == analyzeResult.scanResult.scanRoot,
            interruptionMonitor: interruptionMonitor
        )

        if shouldClearDerivativeCacheAfterOverallSuccess,
            RawSidecarBatchHelpers.analyzeSucceeded(analyzeResult),
            RawSidecarBatchHelpers.exportSucceeded(exportResult)
        {
            try DerivativeCache(
                directoryPath: runConfiguration.derivativeCacheDir,
                sizeCapBytes: runConfiguration.derivativeCacheSizeBytes,
                fileManager: fileManager
            ).clear()
        }

        return AnalyzeAndXMPResult(analyzeResult: analyzeResult, exportResult: exportResult)
    }

}
