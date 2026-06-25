import Foundation

/// Result of a Phase 3 normalize write invocation over existing inputs.
public struct NormalizeAndWritePipelineResult: Sendable, Equatable {
    public var normalizeResult: NormalizePipelineResult
    public var exportResult: XMPExportPipelineResult

    public init(normalizeResult: NormalizePipelineResult, exportResult: XMPExportPipelineResult) {
        self.normalizeResult = normalizeResult
        self.exportResult = exportResult
    }
}

/// Executes normalized XMP writes for already-available Phase 3 inputs.
public struct NormalizeAndWritePipeline {
    private let fileManager: FileManager
    private let normalizePipeline: NormalizePipeline
    private let exportPipeline: XMPExportPipeline
    private let executionRecorder: NormalizationXMPExecutionRecorder
    private let afterNormalization: @Sendable () -> Void

    /// Create a normalize-and-write pipeline with injectable collaborators.
    ///
    /// `afterNormalization` fires after the session and normalized change plan are written,
    /// but before XMP export begins, so tests can assert the Milestone 9 interruption boundary.
    public init(
        fileManager: FileManager = .default,
        normalizePipeline: NormalizePipeline = NormalizePipeline(),
        exportPipeline: XMPExportPipeline? = nil,
        logger: Logger = Logger(),
        now: @escaping @Sendable () -> Date = Date.init,
        afterNormalization: @escaping @Sendable () -> Void = {}
    ) {
        self.fileManager = fileManager
        self.normalizePipeline = normalizePipeline
        self.exportPipeline = exportPipeline ?? XMPExportPipeline(
            fileManager: fileManager,
            logger: logger,
            now: now
        )
        self.executionRecorder = NormalizationXMPExecutionRecorder(fileManager: fileManager)
        self.afterNormalization = afterNormalization
    }

    /// Build a normalization session, execute its XMP plans, and update report artifacts.
    public func run(
        mode: NormalizationInvocationMode,
        configuration: ResolvedNormalizationConfiguration,
        interruptionMonitor: InterruptionMonitor? = nil
    ) throws -> NormalizeAndWritePipelineResult {
        guard mode.isExistingInputMode else {
            throw SidecarError.configInvalid(
                "NormalizeAndWritePipeline requires --from-json or --file-list; use AnalyzeAndNormalizePipeline for image input."
            )
        }
        let normalizeResult = try normalizePipeline.runWritePlan(
            mode: mode,
            configuration: configuration,
            interruptionMonitor: interruptionMonitor
        )
        let changePlan = normalizeResult.changePlan ?? XMPChangePlanDocument(
            dryRun: configuration.dryRun,
            targetPlans: [],
            inputFailures: []
        )
        afterNormalization()
        let exportResult = try exportPipeline.runChangePlan(
            changePlan,
            inputPath: inputPath(for: mode),
            configuration: xmpConfiguration(from: configuration),
            interruptionMonitor: interruptionMonitor
        )
        let finalNormalizeResult = try executionRecorder.recordExecution(
            normalizeResult: normalizeResult,
            exportResult: exportResult,
            progressMessage: "Normalize XMP target processed."
        )
        return NormalizeAndWritePipelineResult(
            normalizeResult: finalNormalizeResult,
            exportResult: exportResult
        )
    }

    private func inputPath(for mode: NormalizationInvocationMode) -> String {
        let path: String
        switch mode {
        case .fromJSON(let selected), .fileList(let selected):
            path = selected
        case .analyze(let selected):
            path = selected
        }
        return absoluteURL(for: path).path
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
            writeAIJSON: configuration.writeAIJSON
        )
    }

    private func absoluteURL(for path: String) -> URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expandedPath)
            .standardizedFileURL
    }
}

private extension NormalizationInvocationMode {
    var isExistingInputMode: Bool {
        switch self {
        case .fromJSON, .fileList:
            return true
        case .analyze:
            return false
        }
    }
}
