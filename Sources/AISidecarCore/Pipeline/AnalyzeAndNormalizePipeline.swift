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
        normalizePipeline: NormalizePipeline = NormalizePipeline(),
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
        self.normalizePipeline = normalizePipeline
        self.exportPipeline =
            exportPipeline
            ?? XMPExportPipeline(
                fileManager: fileManager,
                logger: logger,
                now: now
            )
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
        var preexistingRawSidecars: Set<String> = []
        var preScanFailed = false
        if !normalizationConfiguration.writeAIJSON {
            do {
                preexistingRawSidecars = try plannedRawSidecarPaths(
                    inputPath: inputPath,
                    configuration: runConfiguration
                )
            } catch {
                preScanFailed = true
                logCleanupWarning("Raw-sidecar pre-scan failed; keeping all raw sidecars.", error: error)
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
        let rawBatch = rawInputBatch(from: analyzeResult)
        let resolvedInput = NormalizationInputResolver(fileManager: fileManager).resolve(
            rawSidecarBatch: rawBatch,
            workflow: .analyze,
            inputPath: URL(fileURLWithPath: inputPath).standardizedFileURL.path,
            inputBasePath: analyzeResult.scanResult.scanRoot,
            scanRoot: analyzeResult.scanResult.scanRoot,
            configuration: normalizationConfiguration
        )

        if !normalizationConfiguration.writeAIJSON, !preScanFailed {
            removeNewRawSidecars(from: analyzeResult, preexistingRawSidecars: preexistingRawSidecars)
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
            progressMessage: "Analyze-and-normalize XMP target processed."
        )

        if shouldClearDerivativeCacheAfterOverallSuccess,
            analyzeSucceeded(analyzeResult),
            exportSucceeded(exportResult)
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

    private func rawInputBatch(from analyzeResult: AnalyzeResult) -> RawJSONSidecarInputBatch {
        let reader = RawJSONSidecarReader(fileManager: fileManager)
        var inputs: [ResolvedRawSidecarInput] = []
        var failures: [RawJSONSidecarInputFailure] = []

        for record in analyzeResult.records {
            guard record.status == .written || record.status == .skippedExisting else {
                failures.append(rawInputFailure(from: record))
                continue
            }
            guard let sidecarPath = record.sidecarPath else {
                failures.append(rawInputFailure(from: record))
                continue
            }
            let sidecarURL = URL(fileURLWithPath: sidecarPath).standardizedFileURL
            do {
                let document = try reader.read(from: sidecarURL)
                inputs.append(
                    ResolvedRawSidecarInput(
                        sidecarPath: sidecarURL,
                        document: document,
                        sourcePath: URL(fileURLWithPath: document.sidecar.source.path).standardizedFileURL,
                        sourceIdentityStatus: .matched,
                        relativePath: SidecarNaming.sidecarRelativePath(for: document.sidecar.source),
                        warnings: []
                    )
                )
            } catch let error as SidecarError {
                failures.append(
                    RawJSONSidecarInputFailure(sidecarPath: sidecarURL, relativePath: record.relativePath, error: error)
                )
            } catch {
                failures.append(
                    RawJSONSidecarInputFailure(
                        sidecarPath: sidecarURL,
                        relativePath: record.relativePath,
                        error: SidecarError(
                            code: .validationFailed,
                            stage: .scan,
                            message: "Unable to read analyze output \(sidecarPath): \(error.localizedDescription)",
                            recoverable: true
                        )
                    )
                )
            }
        }

        return RawJSONSidecarInputBatch(inputs: inputs, failures: failures)
    }

    private func rawInputFailure(from record: ProgressRecord) -> RawJSONSidecarInputFailure {
        let path = record.sidecarPath ?? record.sourcePath ?? "analyze-output"
        return RawJSONSidecarInputFailure(
            sidecarPath: URL(fileURLWithPath: path).standardizedFileURL,
            relativePath: record.relativePath,
            error: record.errors.first
                ?? SidecarError(
                    code: .validationFailed,
                    stage: .write,
                    message: "Analyze did not produce a successful raw sidecar for normalization.",
                    recoverable: true
                )
        )
    }

    private func plannedRawSidecarPaths(
        inputPath: String,
        configuration: ResolvedRunConfiguration
    ) throws -> Set<String> {
        if let preScanRawSidecars {
            return try preScanRawSidecars(inputPath, configuration)
        }
        let scan = try ImageScanner(fileManager: fileManager).scan(
            inputPath: inputPath,
            recursive: configuration.recursive,
            identityPolicy: configuration.sourceIdentityPolicy
        )
        return Set(
            SidecarNaming.plan(for: scan.images, outputDir: configuration.outputDir)
                .entries
                .map(\.sidecarPath)
                .filter { fileManager.fileExists(atPath: $0) }
        )
    }

    private func removeNewRawSidecars(from analyzeResult: AnalyzeResult, preexistingRawSidecars: Set<String>) {
        for record in analyzeResult.records where record.status == .written {
            guard let sidecarPath = record.sidecarPath, !preexistingRawSidecars.contains(sidecarPath) else {
                continue
            }
            do {
                try fileManager.removeItem(atPath: sidecarPath)
            } catch {
                logCleanupWarning("Unable to remove temporary raw sidecar: \(sidecarPath)", error: error)
            }
        }
    }

    private func logCleanupWarning(_ message: String, error: Error) {
        let sidecarError =
            error as? SidecarError
            ?? SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "\(message) \(error.localizedDescription)",
                recoverable: true
            )
        try? logger.log(
            LogRecord(
                level: .warn,
                event: "pipeline.raw_sidecar_cleanup_warning",
                message: message,
                errors: [sidecarError]
            ))
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

    private func analyzeSucceeded(_ result: AnalyzeResult) -> Bool {
        !result.interrupted && result.records.allSatisfy { $0.status != .failed }
    }

    private func exportSucceeded(_ result: XMPExportPipelineResult) -> Bool {
        guard !result.interrupted, let report = result.report else {
            return false
        }
        return report.failedCount == 0 && report.targetReports.allSatisfy { $0.status != .failed }
    }
}
