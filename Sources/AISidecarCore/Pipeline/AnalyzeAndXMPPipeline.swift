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

    public init(
        fileManager: FileManager = .default,
        analyzePipeline: AnalyzePipeline? = nil,
        exportPipeline: XMPExportPipeline? = nil,
        logger: Logger = Logger(),
        maskProvider: (any ForegroundMaskProvider)? = nil,
        runner: any VisionModelRunner = OllamaVisionRunner(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.analyzePipeline = analyzePipeline ?? AnalyzePipeline(
            fileManager: fileManager,
            logger: logger,
            maskProvider: maskProvider,
            runner: runner,
            now: now
        )
        self.exportPipeline = exportPipeline ?? XMPExportPipeline(
            fileManager: fileManager,
            logger: logger,
            now: now
        )
    }

    /// Run Phase 1 analysis, then export successful raw sidecars through the shared XMP path.
    public func run(
        inputPath: String,
        runConfiguration: ResolvedRunConfiguration,
        exportConfiguration: ResolvedXMPExportConfiguration,
        interruptionMonitor: InterruptionMonitor? = nil
    ) async throws -> AnalyzeAndXMPResult {
        let preexistingRawSidecars = exportConfiguration.writeAIJSON
            ? []
            : (try? plannedRawSidecarPaths(inputPath: inputPath, configuration: runConfiguration)) ?? []
        var analyzeConfiguration = runConfiguration
        let shouldClearDerivativeCacheAfterOverallSuccess = analyzeConfiguration.clearDerivativeCacheAfterSuccess
        analyzeConfiguration.clearDerivativeCacheAfterSuccess = false

        let analyzeResult = try await analyzePipeline.run(
            inputPath: inputPath,
            configuration: analyzeConfiguration,
            interruptionMonitor: interruptionMonitor
        )
        let batch = rawInputBatch(from: analyzeResult)

        if !exportConfiguration.writeAIJSON {
            removeNewRawSidecars(from: analyzeResult, preexistingRawSidecars: preexistingRawSidecars)
        }

        let exportResult = try exportPipeline.runResolvedInputs(
            batch,
            inputPath: URL(fileURLWithPath: inputPath).standardizedFileURL.path,
            configuration: exportConfiguration,
            writesBatchArtifacts: analyzeResult.scanResult.inputPath == analyzeResult.scanResult.scanRoot,
            interruptionMonitor: interruptionMonitor
        )

        if shouldClearDerivativeCacheAfterOverallSuccess,
           analyzeSucceeded(analyzeResult),
           exportSucceeded(exportResult) {
            try DerivativeCache(
                directoryPath: runConfiguration.derivativeCacheDir,
                sizeCapBytes: runConfiguration.derivativeCacheSizeBytes,
                fileManager: fileManager
            ).clear()
        }

        return AnalyzeAndXMPResult(analyzeResult: analyzeResult, exportResult: exportResult)
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
            error: record.errors.first ?? SidecarError(
                code: .validationFailed,
                stage: .write,
                message: "Analyze did not produce a successful raw sidecar for XMP export.",
                recoverable: true
            )
        )
    }

    private func plannedRawSidecarPaths(
        inputPath: String,
        configuration: ResolvedRunConfiguration
    ) throws -> Set<String> {
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
            try? fileManager.removeItem(atPath: sidecarPath)
        }
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
