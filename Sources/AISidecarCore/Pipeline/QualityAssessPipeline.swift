import Foundation

/// Quality-only analysis entry point that reuses the guarded raw-sidecar pipeline.
public struct QualityAssessPipeline {
    private let analyzePipeline: AnalyzePipeline

    public init(analyzePipeline: AnalyzePipeline) {
        self.analyzePipeline = analyzePipeline
    }

    public init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(),
        maskProvider: (any ForegroundMaskProvider)? = nil,
        runner: any VisionModelRunner,
        now: @escaping @Sendable () -> Date = Date.init,
        filenameSuffix: @escaping @Sendable () -> String = Timestamp.randomFilenameSuffix
    ) {
        self.analyzePipeline = AnalyzePipeline(
            fileManager: fileManager,
            logger: logger,
            maskProvider: maskProvider,
            runner: runner,
            now: now,
            filenameSuffix: filenameSuffix
        )
    }

    /// Assess perceptual quality and write `.quality.ai.json` raw sidecars without invoking any XMP path.
    public func run(
        inputPath: String,
        configuration: ResolvedRunConfiguration,
        interruptionMonitor: InterruptionMonitor? = nil,
        progressHandler: (@Sendable (ProgressRecord) -> Void)? = nil
    ) async throws -> AnalyzeResult {
        try await analyzePipeline.run(
            inputPath: inputPath,
            configuration: configuration.with(taskProfile: .qualityOnly),
            interruptionMonitor: interruptionMonitor,
            progressHandler: progressHandler
        )
    }
}
