import Foundation

/// Result of analyze-and-normalize, carrying Phase 1, Phase 3, and XMP outcomes.
public struct AnalyzeAndNormalizeResult: Sendable, Equatable {
    public var analyzeResult: AnalyzeResult
    public var normalizeResult: NormalizePipelineResult
    public var exportResult: XMPExportPipelineResult

    public init(
        analyzeResult: AnalyzeResult,
        normalizeResult: NormalizePipelineResult,
        exportResult: XMPExportPipelineResult
    ) {
        self.analyzeResult = analyzeResult
        self.normalizeResult = normalizeResult
        self.exportResult = exportResult
    }
}

/// Thin adapter from Phase 1 analysis into Phase 3 normalization and XMP export.
public struct AnalyzeAndNormalizePipeline {
    private let fileManager: FileManager
    private let analyzePipeline: AnalyzePipeline
    private let normalizePipeline: NormalizePipeline
    private let exportPipeline: XMPExportPipeline
    private let invocationEngine: OwnedXMPSidecarEngine?
    private let executionRecorder: NormalizationXMPExecutionRecorder
    private let afterNormalization: @Sendable () -> Void
    private let logger: Logger
    private let preScanRawSidecars: (@Sendable (String, ResolvedRunConfiguration) throws -> Set<String>)?

    /// Create an analyze-and-normalize pipeline with injectable collaborators.
    ///
    /// `afterNormalization` fires after the session and normalized change plan are written,
    /// but before XMP export begins, so tests can assert the Milestone 9 interruption boundary.
    public init(
        fileManager: FileManager = .default,
        analyzePipeline: AnalyzePipeline? = nil,
        normalizePipeline: NormalizePipeline? = nil,
        exportPipeline: XMPExportPipeline? = nil,
        logger: Logger = Logger(),
        maskProvider: (any ForegroundMaskProvider)? = nil,
        runner: any VisionModelRunner = OllamaVisionRunner(),
        now: @escaping @Sendable () -> Date = Date.init,
        afterNormalization: @escaping @Sendable () -> Void = {},
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
        if normalizePipeline == nil, exportPipeline == nil {
            let invocationEngine = OwnedXMPSidecarEngine(fileManager: fileManager)
            self.normalizePipeline = NormalizePipeline(
                snapshotReader: { try invocationEngine.readSnapshot(at: $0) },
                fileManager: fileManager
            )
            self.exportPipeline = XMPExportPipeline(
                fileManager: fileManager,
                engine: invocationEngine,
                logger: logger,
                now: now
            )
            self.invocationEngine = invocationEngine
        } else {
            self.normalizePipeline = normalizePipeline ?? NormalizePipeline(fileManager: fileManager)
            self.exportPipeline =
                exportPipeline
                ?? XMPExportPipeline(
                    fileManager: fileManager,
                    engine: OwnedXMPSidecarEngine(fileManager: fileManager),
                    logger: logger,
                    now: now
                )
            self.invocationEngine = nil
        }
        self.executionRecorder = NormalizationXMPExecutionRecorder(fileManager: fileManager)
        self.afterNormalization = afterNormalization
        self.logger = logger
        self.preScanRawSidecars = preScanRawSidecars
    }

    /// Run Phase 1 analysis, normalize successful sidecars, then execute normalized XMP plans.
    public func run(
        inputPath: String,
        runConfiguration: ResolvedRunConfiguration,
        normalizationConfiguration: ResolvedNormalizationConfiguration,
        interruptionMonitor: InterruptionMonitor? = nil
    ) async throws -> AnalyzeAndNormalizeResult {
        invocationEngine?.beginPreWriteInvocation()
        defer {
            try? invocationEngine?.shutdown()
        }
        var preexistingRawSidecars: Set<String> = []
        var preScanFailed = false
        if !normalizationConfiguration.writeAIJSON {
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
        let rawBatch = RawSidecarBatchHelpers.rawInputBatch(
            from: analyzeResult,
            failureContext: "normalization",
            fileManager: fileManager
        )
        let resolvedInput = NormalizationInputResolver(fileManager: fileManager).resolve(
            rawSidecarBatch: rawBatch,
            workflow: .analyze,
            inputPath: URL(fileURLWithPath: inputPath).standardizedFileURL.path,
            inputBasePath: analyzeResult.scanResult.scanRoot,
            scanRoot: analyzeResult.scanResult.scanRoot,
            configuration: normalizationConfiguration
        )

        if !normalizationConfiguration.writeAIJSON, !preScanFailed {
            RawSidecarBatchHelpers.removeNewRawSidecars(
                from: analyzeResult,
                preexistingRawSidecars: preexistingRawSidecars,
                fileManager: fileManager,
                logger: logger
            )
        }

        let normalizeResult = try normalizePipeline.runResolvedInputs(
            resolvedInput,
            configuration: normalizationConfiguration,
            includeXMPPlans: true,
            interruptionMonitor: interruptionMonitor
        )
        let changePlan =
            normalizeResult.changePlan
            ?? XMPChangePlanDocument(
                dryRun: normalizationConfiguration.dryRun,
                targetPlans: [],
                inputFailures: []
            )
        afterNormalization()
        let exportResult = try exportPipeline.runChangePlan(
            changePlan,
            inputPath: URL(fileURLWithPath: inputPath).standardizedFileURL.path,
            configuration: xmpConfiguration(from: normalizationConfiguration),
            interruptionMonitor: interruptionMonitor
        )
        let finalNormalizeResult = try executionRecorder.recordExecution(
            normalizeResult: normalizeResult,
            exportResult: exportResult,
            progressMessage: "Analyze-and-normalize XMP target processed.",
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

        return AnalyzeAndNormalizeResult(
            analyzeResult: analyzeResult,
            normalizeResult: finalNormalizeResult,
            exportResult: exportResult
        )
    }

    private func xmpConfiguration(
        from configuration: ResolvedNormalizationConfiguration
    ) -> ResolvedXMPExportConfiguration {
        ResolvedXMPExportConfiguration(
            recursive: configuration.recursive,
            outputDir: configuration.outputDir,
            logLevel: configuration.logLevel,
            logFormat: configuration.logFormat,
            dryRun: configuration.dryRun,
            sourceRoot: configuration.sourceRoot,
            sourceVerification: configuration.sourceVerification,
            writeFlatKeywords: configuration.writeFlatKeywords,
            writeHierarchicalKeywords: configuration.writeHierarchicalKeywords,
            backupSidecars: configuration.backupSidecars,
            xmpConflictPolicy: configuration.xmpConflictPolicy,
            minConfidence: configuration.minConfidence,
            allowSpecificTags: configuration.allowSpecificTags,
            pairScope: configuration.pairScope,
            writeAIJSON: configuration.writeAIJSON,
            qualityGrading: configuration.qualityGrading
        )
    }

}
