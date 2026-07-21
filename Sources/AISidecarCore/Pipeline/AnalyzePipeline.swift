import CoreImage
import Foundation

/// Result of the full Phase 1 analyze pipeline.
public struct AnalyzeResult: Sendable, Equatable {
    public var scanResult: ScanResult
    public var records: [ProgressRecord]
    public var progressLogPath: String?
    public var summaryPath: String?
    public var summary: BatchSummary?
    public var interrupted: Bool

    public init(
        scanResult: ScanResult,
        records: [ProgressRecord],
        progressLogPath: String?,
        summaryPath: String?,
        summary: BatchSummary?,
        interrupted: Bool
    ) {
        self.scanResult = scanResult
        self.records = records
        self.progressLogPath = progressLogPath
        self.summaryPath = summaryPath
        self.summary = summary
        self.interrupted = interrupted
    }
}

/// Phase 1 analyze pipeline with bounded render/isolation prep and serialized model calls.
public struct AnalyzePipeline {
    private let fileManager: FileManager
    private let scanner: ImageScanner
    private let writer: any RawJSONSidecarWriting
    private let summaryWriter: BatchSummaryWriter
    private let logger: Logger
    private let maskProvider: any ForegroundMaskProvider
    private let runner: any VisionModelRunner
    private let now: @Sendable () -> Date
    private let filenameSuffix: @Sendable () -> String
    private let imageRendererFactory: @Sendable (DerivativeCache) -> ImageRenderer
    private let subjectIsolationServiceFactory:
        @Sendable (DerivativeCache, any ForegroundMaskProvider) -> SubjectIsolationService

    public init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(),
        maskProvider: (any ForegroundMaskProvider)? = nil,
        runner: any VisionModelRunner = OllamaVisionRunner(),
        now: @escaping @Sendable () -> Date = Date.init,
        filenameSuffix: @escaping @Sendable () -> String = Timestamp.randomFilenameSuffix
    ) {
        self.init(
            fileManager: fileManager,
            logger: logger,
            maskProvider: maskProvider,
            runner: runner,
            now: now,
            filenameSuffix: filenameSuffix,
            sidecarWriter: RawJSONSidecarWriter(fileManager: fileManager)
        )
    }

    init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(),
        maskProvider: (any ForegroundMaskProvider)? = nil,
        runner: any VisionModelRunner = OllamaVisionRunner(),
        now: @escaping @Sendable () -> Date = Date.init,
        filenameSuffix: @escaping @Sendable () -> String = Timestamp.randomFilenameSuffix,
        sidecarWriter: any RawJSONSidecarWriting,
        imageRendererFactory: @escaping @Sendable (DerivativeCache) -> ImageRenderer = { ImageRenderer(cache: $0) },
        subjectIsolationServiceFactory:
            @escaping @Sendable (
                DerivativeCache,
                any ForegroundMaskProvider
            ) -> SubjectIsolationService = { SubjectIsolationService(cache: $0, maskProvider: $1) }
    ) {
        self.fileManager = fileManager
        self.scanner = ImageScanner(fileManager: fileManager)
        self.writer = sidecarWriter
        self.summaryWriter = BatchSummaryWriter(fileManager: fileManager)
        self.logger = logger
        if let maskProvider {
            self.maskProvider = maskProvider
        } else if #available(macOS 15.0, *) {
            self.maskProvider = AppleVisionForegroundMaskProvider()
        } else {
            self.maskProvider = PipelineUnavailableForegroundMaskProvider()
        }
        self.runner = runner
        self.now = now
        self.filenameSuffix = filenameSuffix
        self.imageRendererFactory = imageRendererFactory
        self.subjectIsolationServiceFactory = subjectIsolationServiceFactory
    }

    /// Run full Phase 1 analysis for one file or folder.
    ///
    /// Folder runs create progress and summary artifacts after model preflight
    /// succeeds; single-file runs write only the raw sidecar and console status.
    ///
    /// `writesBatchArtifacts: false` (CORE-2) keeps `.ai.json` sidecar writes
    /// but suppresses the batch progress JSONL and summary files, for hosts
    /// (the GUI) that hold run state in-process instead of in report files.
    /// `progressHandler` (CORE-1) is invoked once per emitted record, serially,
    /// in addition to — never instead of — the existing log writes.
    public func run(
        inputPath: String,
        configuration: ResolvedRunConfiguration,
        interruptionMonitor: InterruptionMonitor? = nil,
        writesBatchArtifacts: Bool = true,
        progressHandler: (@Sendable (ProgressRecord) -> Void)? = nil
    ) async throws -> AnalyzeResult {
        if configuration.taskProfile == .taggingWithQuality, configuration.qualityScanMode == .sequential {
            return try await runSequentialScanAndAssess(
                inputPath: inputPath,
                configuration: configuration,
                interruptionMonitor: interruptionMonitor,
                writesBatchArtifacts: writesBatchArtifacts,
                progressHandler: progressHandler
            )
        }
        let runStartedAt = now()
        let profile = try ModelInputProfileRegistry.resolve(name: configuration.profile)
        let lifecycleCache = cache(for: configuration)
        defer { lifecycleCache.releaseRetained() }
        if configuration.clearDerivativeCacheOnStart {
            try lifecycleCache.clear()
        }
        let scanResult = try scanner.scan(
            inputPath: inputPath,
            recursive: configuration.recursive,
            identityPolicy: configuration.sourceIdentityPolicy
        )
        let isQualityOnly = configuration.taskProfile == .qualityOnly
        let sidecarKind: RawSidecarKind = isQualityOnly ? .quality : .tagging
        let plan = SidecarNaming.plan(
            for: scanResult.images,
            outputDir: configuration.outputDir,
            kind: sidecarKind
        )
        let actions = entryActions(for: plan.entries, configuration: configuration)
        let pendingWork = actions.indices.compactMap { index -> PendingWork? in
            guard case .pending = actions[index] else {
                return nil
            }
            return PendingWork(index: index)
        }

        // FR1-030b fail-fast model verification must happen before progress,
        // cache, sidecar, or summary artifacts are created for model work.
        let runtime = pendingWork.isEmpty ? nil : try await runner.prepare(configuration: configuration)

        let isBatch = scanResult.inputPath == scanResult.scanRoot
        let timestamp = Timestamp.filenameToken(runStartedAt, suffix: filenameSuffix())
        let reportDirectory = reportDirectoryPath(scanRoot: scanResult.scanRoot, outputDir: configuration.outputDir)
        let progressPath =
            isBatch && !configuration.dryRun && writesBatchArtifacts
            ? "\(reportDirectory)/\(isQualityOnly ? ArtifactNames.qualityProgressPrefix : ArtifactNames.batchProgressPrefix)\(timestamp).jsonl"
            : nil
        let summaryPath =
            isBatch && !configuration.dryRun && writesBatchArtifacts
            ? "\(reportDirectory)/\(isQualityOnly ? ArtifactNames.qualitySummaryPrefix : ArtifactNames.batchSummaryPrefix)\(timestamp).json"
            : nil
        let progressLog = try progressPath.map { try ProgressLog(path: $0, fileManager: fileManager) }
        let progressFlushRegistration = progressLog.flatMap { progressLog in
            interruptionMonitor?.onInterruption {
                try? progressLog.flush()
            }
        }
        defer {
            progressFlushRegistration?.cancel()
            try? progressLog?.close()
        }

        var records: [ProgressRecord] = []
        var interrupted = false

        func emit(_ record: ProgressRecord) throws {
            records.append(record)
            if !configuration.dryRun {
                try progressLog?.append(record)
            }
            try logger.log(logRecord(for: record))
            progressHandler?(record)
        }

        for scanError in scanResult.errors {
            try emit(
                ProgressRecord(
                    timestamp: now(),
                    sourcePath: scanError.path,
                    relativePath: scanError.relativePath,
                    sidecarPath: nil,
                    status: .failed,
                    errors: [scanError.error],
                    durationMs: 0
                )
            )
        }

        for collision in plan.collisions {
            for source in collision.sources {
                try emit(
                    ProgressRecord(
                        timestamp: now(),
                        sourcePath: source.path,
                        relativePath: source.relativePath,
                        sidecarPath: collision.sidecarPath,
                        status: .failed,
                        errors: [collision.error],
                        durationMs: 0
                    )
                )
            }
        }

        if pendingWork.isEmpty {
            for (index, action) in actions.enumerated() {
                if interruptionMonitor?.isInterrupted == true {
                    interrupted = true
                    break
                }
                if let record = nonPendingRecord(
                    action: action,
                    entry: plan.entries[index]
                ) {
                    try emit(record)
                }
            }
        } else {
            interrupted = try await processPendingWork(
                pendingWork,
                actions: actions,
                entries: plan.entries,
                configuration: configuration,
                profile: profile,
                runtime: runtime!,
                cache: lifecycleCache,
                interruptionMonitor: interruptionMonitor,
                emit: emit
            )
        }

        if interruptionMonitor?.isInterrupted == true {
            interrupted = true
        }

        let summary: BatchSummary?
        if let summaryPath {
            let batchSummary = BatchSummary.derive(
                from: scanResult,
                records: records,
                outputDir: configuration.outputDir,
                createdAt: now(),
                interrupted: interrupted
            )
            try summaryWriter.write(batchSummary, to: summaryPath)
            summary = batchSummary
        } else {
            summary = nil
        }

        if configuration.clearDerivativeCacheAfterSuccess,
            completedSuccessfully(records: records, interrupted: interrupted)
        {
            try lifecycleCache.clear()
        }

        return AnalyzeResult(
            scanResult: scanResult,
            records: records,
            progressLogPath: progressPath,
            summaryPath: summaryPath,
            summary: summary,
            interrupted: interrupted
        )
    }

    /// Sequential quality mode: a tagging pass, then a dedicated quality pass.
    ///
    /// The tagging pass writes `.ai.json` exactly as a tagging-only run would;
    /// the quality pass writes `.quality.ai.json` siblings that the sidecar
    /// input resolver pairs at read time. Cache lifecycle options keep their
    /// whole-run meaning: clear-on-start applies before the first pass and
    /// clear-after-success after the second, so the quality pass reuses the
    /// tagging pass's rendered derivatives instead of re-rendering them.
    private func runSequentialScanAndAssess(
        inputPath: String,
        configuration: ResolvedRunConfiguration,
        interruptionMonitor: InterruptionMonitor?,
        writesBatchArtifacts: Bool,
        progressHandler: (@Sendable (ProgressRecord) -> Void)?
    ) async throws -> AnalyzeResult {
        var taggingConfiguration = configuration.with(taskProfile: .tagging)
        taggingConfiguration.clearDerivativeCacheAfterSuccess = false
        let tagging = try await run(
            inputPath: inputPath,
            configuration: taggingConfiguration,
            interruptionMonitor: interruptionMonitor,
            writesBatchArtifacts: writesBatchArtifacts,
            progressHandler: progressHandler
        )
        if tagging.interrupted {
            return tagging
        }

        var qualityConfiguration = configuration.with(taskProfile: .qualityOnly)
        qualityConfiguration.clearDerivativeCacheOnStart = false
        let quality = try await run(
            inputPath: inputPath,
            configuration: qualityConfiguration,
            interruptionMonitor: interruptionMonitor,
            writesBatchArtifacts: writesBatchArtifacts,
            progressHandler: progressHandler
        )
        return AnalyzeResult(
            scanResult: tagging.scanResult,
            records: tagging.records + quality.records,
            progressLogPath: tagging.progressLogPath,
            summaryPath: tagging.summaryPath,
            summary: tagging.summary,
            interrupted: quality.interrupted
        )
    }

    private func cache(for configuration: ResolvedRunConfiguration) -> DerivativeCache {
        DerivativeCache(
            directoryPath: configuration.derivativeCacheDir,
            sizeCapBytes: configuration.derivativeCacheSizeBytes,
            fileManager: fileManager,
            now: now
        )
    }

    private func completedSuccessfully(records: [ProgressRecord], interrupted: Bool) -> Bool {
        !interrupted && records.allSatisfy { $0.status != .failed }
    }

    private func processPendingWork(
        _ pendingWork: [PendingWork],
        actions: [EntryAction],
        entries: [SidecarPlanEntry],
        configuration: ResolvedRunConfiguration,
        profile: ModelInputProfile,
        runtime: ModelRuntimeContext,
        cache: DerivativeCache,
        interruptionMonitor: InterruptionMonitor?,
        emit: (ProgressRecord) throws -> Void
    ) async throws -> Bool {
        var interrupted = false
        let maxWorkers = max(1, min(configuration.stageConcurrency, pendingWork.count))
        let maskProvider = maskProvider
        let now = now
        let renderer = imageRendererFactory(cache)
        let subjectIsolationService = subjectIsolationServiceFactory(cache, maskProvider)

        if maxWorkers == 1 {
            return try await processPendingWorkSequentially(
                actions: actions,
                entries: entries,
                configuration: configuration,
                profile: profile,
                runtime: runtime,
                cache: cache,
                interruptionMonitor: interruptionMonitor,
                renderer: renderer,
                subjectIsolationService: subjectIsolationService,
                now: now,
                emit: emit
            )
        }

        var preparedByIndex: [Int: PreparedAnalysis] = [:]
        var nextPendingToSchedule = 0
        var inFlight = 0

        try await withThrowingTaskGroup(of: (Int, PreparedAnalysis).self) { group in
            func fillWorkers() {
                while inFlight + preparedByIndex.count < maxWorkers,
                    nextPendingToSchedule < pendingWork.count
                {
                    let work = pendingWork[nextPendingToSchedule]
                    let entry = entries[work.index]
                    nextPendingToSchedule += 1
                    inFlight += 1
                    group.addTask {
                        let prepared = await Self.prepare(
                            entry: entry,
                            configuration: configuration,
                            profile: profile,
                            renderer: renderer,
                            subjectIsolationService: subjectIsolationService,
                            now: now
                        )
                        return (work.index, prepared)
                    }
                }
            }

            fillWorkers()

            // Prepared results may finish out of order, but sidecar/progress
            // emission stays in scan order and model calls happen in this loop.
            processingLoop: for (index, action) in actions.enumerated() {
                if interruptionMonitor?.isInterrupted == true {
                    interrupted = true
                    group.cancelAll()
                    break
                }

                switch action {
                case .dryRun, .existingSkip, .existingFailure:
                    if let record = nonPendingRecord(action: action, entry: entries[index]) {
                        try emit(record)
                    }
                case .pending(let startedAt):
                    while preparedByIndex[index] == nil {
                        guard let (preparedIndex, prepared) = try await group.next() else {
                            break
                        }
                        inFlight -= 1
                        preparedByIndex[preparedIndex] = prepared
                        fillWorkers()
                    }

                    if interruptionMonitor?.isInterrupted == true {
                        interrupted = true
                        group.cancelAll()
                        break
                    }

                    guard let prepared = preparedByIndex.removeValue(forKey: index) else {
                        interrupted = true
                        group.cancelAll()
                        break
                    }
                    fillWorkers()

                    let outcome = await finishPrepared(
                        prepared,
                        entry: entries[index],
                        configuration: configuration,
                        profile: profile,
                        runtime: runtime,
                        interruptionMonitor: interruptionMonitor,
                        startedAt: startedAt
                    )
                    cache.release(prepared.derivatives)
                    switch outcome {
                    case .completed(let record):
                        try emit(record)
                    case .interrupted:
                        interrupted = true
                        group.cancelAll()
                        break processingLoop
                    }
                    if interruptionMonitor?.isInterrupted == true {
                        interrupted = true
                        group.cancelAll()
                        break processingLoop
                    }
                }
            }

            group.cancelAll()
        }

        return interrupted
    }

    private func processPendingWorkSequentially(
        actions: [EntryAction],
        entries: [SidecarPlanEntry],
        configuration: ResolvedRunConfiguration,
        profile: ModelInputProfile,
        runtime: ModelRuntimeContext,
        cache: DerivativeCache,
        interruptionMonitor: InterruptionMonitor?,
        renderer: ImageRenderer,
        subjectIsolationService: SubjectIsolationService,
        now: @escaping @Sendable () -> Date,
        emit: (ProgressRecord) throws -> Void
    ) async throws -> Bool {
        for (index, action) in actions.enumerated() {
            if interruptionMonitor?.isInterrupted == true {
                return true
            }

            switch action {
            case .dryRun, .existingSkip, .existingFailure:
                if let record = nonPendingRecord(action: action, entry: entries[index]) {
                    try emit(record)
                }
            case .pending(let startedAt):
                // `stage_concurrency == 1` is the low-memory mode: do not
                // render the next source while the current model request holds
                // the encoded derivative in memory.
                let prepared = await Self.prepare(
                    entry: entries[index],
                    configuration: configuration,
                    profile: profile,
                    renderer: renderer,
                    subjectIsolationService: subjectIsolationService,
                    now: now
                )
                if interruptionMonitor?.isInterrupted == true {
                    return true
                }
                let outcome = await finishPrepared(
                    prepared,
                    entry: entries[index],
                    configuration: configuration,
                    profile: profile,
                    runtime: runtime,
                    interruptionMonitor: interruptionMonitor,
                    startedAt: startedAt
                )
                cache.release(prepared.derivatives)
                switch outcome {
                case .completed(let record):
                    try emit(record)
                case .interrupted:
                    return true
                }
                if interruptionMonitor?.isInterrupted == true {
                    return true
                }
            }
        }

        return false
    }

    private func entryActions(
        for entries: [SidecarPlanEntry],
        configuration: ResolvedRunConfiguration
    ) -> [EntryAction] {
        entries.map { entry in
            let startedAt = now()
            if configuration.dryRun {
                return .dryRun(startedAt)
            }
            if fileManager.fileExists(atPath: entry.sidecarPath) {
                switch configuration.existing {
                case .skip:
                    return .existingSkip(startedAt)
                case .fail:
                    return .existingFailure(
                        SidecarError(
                            code: .sidecarExists,
                            stage: .write,
                            message: "Sidecar already exists: \(entry.sidecarPath)",
                            recoverable: true
                        ),
                        startedAt
                    )
                case .overwrite:
                    break
                }
            }
            return .pending(startedAt)
        }
    }

    private func nonPendingRecord(action: EntryAction, entry: SidecarPlanEntry) -> ProgressRecord? {
        switch action {
        case .dryRun(let startedAt):
            return ProgressRecord(
                timestamp: now(),
                sourcePath: entry.source.path,
                relativePath: entry.source.relativePath,
                sidecarPath: entry.sidecarPath,
                status: .dryRun,
                durationMs: durationMs(from: startedAt, to: now())
            )
        case .existingSkip(let startedAt):
            return ProgressRecord(
                timestamp: now(),
                sourcePath: entry.source.path,
                relativePath: entry.source.relativePath,
                sidecarPath: entry.sidecarPath,
                status: .skippedExisting,
                durationMs: durationMs(from: startedAt, to: now())
            )
        case .existingFailure(let error, let startedAt):
            return ProgressRecord(
                timestamp: now(),
                sourcePath: entry.source.path,
                relativePath: entry.source.relativePath,
                sidecarPath: entry.sidecarPath,
                status: .failed,
                errors: [error],
                durationMs: durationMs(from: startedAt, to: now())
            )
        case .pending:
            return nil
        }
    }

    private static func prepare(
        entry: SidecarPlanEntry,
        configuration: ResolvedRunConfiguration,
        profile: ModelInputProfile,
        renderer: ImageRenderer,
        subjectIsolationService: SubjectIsolationService,
        now: @escaping @Sendable () -> Date
    ) async -> PreparedAnalysis {
        let renderStartedAt = now()
        do {
            var derivatives: [DerivativeRecord] = []
            var subjectIsolation: SubjectIsolationRecord?
            var errors: [SidecarError] = []
            var renderMs = 0
            var subjectIsolationMs = 0

            switch configuration.mode {
            case .whole:
                let rendered = try renderer.renderWholeImage(
                    source: entry.source,
                    profile: profile,
                    debugDerivatives: configuration.debugDerivatives
                )
                derivatives = rendered.derivatives
                renderMs = Self.durationMs(from: renderStartedAt, to: now())
            case .subject, .both:
                let prepared = try renderer.prepareSourceRender(source: entry.source, profile: profile)
                if configuration.mode == .both {
                    let whole = try renderer.renderWholeImageDerivative(
                        source: entry.source,
                        prepared: prepared,
                        profile: profile,
                        debugDerivatives: configuration.debugDerivatives
                    )
                    derivatives.append(whole)
                }
                renderMs = Self.durationMs(from: renderStartedAt, to: now())

                let isolationStartedAt = now()
                do {
                    let isolation = try await subjectIsolationService.isolate(
                        source: entry.source,
                        prepared: prepared,
                        profile: profile,
                        configuration: configuration
                    )
                    subjectIsolation = isolation.record
                    if let derivative = isolation.derivative {
                        derivatives.append(derivative)
                    }
                    if let error = isolation.error {
                        errors.append(error)
                    }
                    subjectIsolationMs = Self.durationMs(from: isolationStartedAt, to: now())
                } catch {
                    subjectIsolationMs = Self.durationMs(from: isolationStartedAt, to: now())
                    let isolationError = subjectIsolationError(from: error)
                    subjectIsolation = failedSubjectIsolationRecord(
                        prepared: prepared,
                        configuration: configuration,
                        profile: profile
                    )
                    errors.append(isolationError)
                }
            }

            return .prepared(
                PreparedRenderedAnalysis(
                    derivatives: derivatives,
                    modelInputContext: configuration.taskProfile == .qualityOnly
                        ? nil
                        : GPSContextExtractor.context(
                            for: entry.source,
                            mode: configuration.gpsContext
                        ),
                    subjectIsolation: subjectIsolation,
                    errors: errors,
                    renderMs: renderMs,
                    subjectIsolationMs: subjectIsolationMs
                )
            )
        } catch {
            return .renderFailed(
                sidecarError(from: error, sidecarPath: entry.sidecarPath),
                renderMs: Self.durationMs(from: renderStartedAt, to: now())
            )
        }
    }

    private func finishPrepared(
        _ prepared: PreparedAnalysis,
        entry: SidecarPlanEntry,
        configuration: ResolvedRunConfiguration,
        profile: ModelInputProfile,
        runtime: ModelRuntimeContext,
        interruptionMonitor: InterruptionMonitor?,
        startedAt: Date
    ) async -> FinishPreparedOutcome {
        switch prepared {
        case .renderFailed(let error, let renderMs):
            return .completed(
                writeFailureSidecar(
                    source: entry.source,
                    sidecarPath: entry.sidecarPath,
                    configuration: configuration,
                    profile: profile,
                    errors: [error],
                    renderMs: renderMs,
                    startedAt: startedAt
                )
            )
        case .prepared(let prepared):
            let modelStartedAt = now()
            let modelOutcome = await runModelRuns(
                derivatives: prepared.derivatives,
                modelInputContext: prepared.modelInputContext,
                configuration: configuration,
                runtime: runtime,
                interruptionMonitor: interruptionMonitor
            )
            let modelMs = durationMs(from: modelStartedAt, to: now())
            guard case .completed(let modelRuns) = modelOutcome,
                interruptionMonitor?.isInterrupted != true
            else {
                return .interrupted
            }
            let errors = prepared.errors + modelRuns.compactMap(\.error)
            let pipelineElapsedMs = durationMs(from: startedAt, to: now())
            let sidecar = RawJSONSidecar(
                source: entry.source,
                runConfiguration: configuration,
                modelInputProfile: profile,
                derivatives: prepared.derivatives,
                subjectIsolation: prepared.subjectIsolation,
                modelRuns: modelRuns,
                errors: errors,
                timing: PipelineTimingRecord(
                    pipelineElapsedMs: pipelineElapsedMs,
                    renderMs: prepared.renderMs,
                    subjectIsolationMs: prepared.subjectIsolationMs,
                    modelMs: modelMs,
                    writeMs: 0
                ),
                createdAt: now()
            )

            do {
                let writeStartedAt = now()
                let outcome = try writer.write(
                    sidecar,
                    to: entry.sidecarPath,
                    existingPolicy: configuration.existing
                )
                let writeMs = durationMs(from: writeStartedAt, to: now())
                let status: ProgressStatus
                switch outcome.status {
                case .skippedExisting:
                    status = .skippedExisting
                case .written:
                    status = modelRuns.contains { $0.error == nil && $0.jsonValid } ? .written : .failed
                }
                return .completed(
                    ProgressRecord(
                        timestamp: now(),
                        sourcePath: entry.source.path,
                        relativePath: entry.source.relativePath,
                        sidecarPath: entry.sidecarPath,
                        status: status,
                        errors: errors,
                        durationMs: durationMs(from: startedAt, to: now()),
                        writeMs: outcome.status == .written ? writeMs : nil
                    )
                )
            } catch {
                return .completed(
                    ProgressRecord(
                        timestamp: now(),
                        sourcePath: entry.source.path,
                        relativePath: entry.source.relativePath,
                        sidecarPath: entry.sidecarPath,
                        status: .failed,
                        errors: errors + [Self.sidecarError(from: error, sidecarPath: entry.sidecarPath)],
                        durationMs: durationMs(from: startedAt, to: now())
                    )
                )
            }
        }
    }

    private func writeFailureSidecar(
        source: SourceImage,
        sidecarPath: String,
        configuration: ResolvedRunConfiguration,
        profile: ModelInputProfile,
        errors: [SidecarError],
        renderMs: Int,
        startedAt: Date
    ) -> ProgressRecord {
        let pipelineElapsedMs = durationMs(from: startedAt, to: now())
        let errorSidecar = RawJSONSidecar(
            source: source,
            runConfiguration: configuration,
            modelInputProfile: profile,
            errors: errors,
            timing: PipelineTimingRecord(
                pipelineElapsedMs: pipelineElapsedMs,
                renderMs: renderMs,
                subjectIsolationMs: 0,
                modelMs: 0,
                writeMs: 0
            ),
            createdAt: now()
        )
        var progressErrors = errors
        var writeMs: Int?
        do {
            let writeStartedAt = now()
            let outcome = try writer.write(
                errorSidecar, to: sidecarPath, existingPolicy: configuration.existing)
            if outcome.status == .written {
                writeMs = durationMs(from: writeStartedAt, to: now())
            }
        } catch {
            progressErrors.append(Self.sidecarError(from: error, sidecarPath: sidecarPath))
        }

        return ProgressRecord(
            timestamp: now(),
            sourcePath: source.path,
            relativePath: source.relativePath,
            sidecarPath: sidecarPath,
            status: .failed,
            errors: progressErrors,
            durationMs: durationMs(from: startedAt, to: now()),
            writeMs: writeMs
        )
    }

    private func runModelRuns(
        derivatives: [DerivativeRecord],
        modelInputContext: ModelInputContext?,
        configuration: ResolvedRunConfiguration,
        runtime: ModelRuntimeContext,
        interruptionMonitor: InterruptionMonitor?
    ) async -> ModelRunsOutcome {
        var runs: [ModelRunRecord] = []
        // PW-015 requires exactly one model request in flight; keep this loop
        // sequential even when render/isolation preparation has worked ahead.
        for (role, derivative) in modelInputs(derivatives: derivatives, mode: configuration.mode) {
            if interruptionMonitor?.isInterrupted == true {
                return .interrupted
            }
            let run = await runModel(
                role: role,
                derivative: derivative,
                modelInputContext: modelInputContext,
                configuration: configuration,
                runtime: runtime,
                interruptionMonitor: interruptionMonitor
            )
            if interruptionMonitor?.isInterrupted == true || run.error?.code == .interrupted {
                return .interrupted
            }
            runs.append(run)
        }
        return .completed(runs)
    }

    private func runModel(
        role: ModelInputRole,
        derivative: DerivativeRecord,
        modelInputContext: ModelInputContext?,
        configuration: ResolvedRunConfiguration,
        runtime: ModelRuntimeContext,
        interruptionMonitor: InterruptionMonitor?
    ) async -> ModelRunRecord {
        var options = ModelRunOptions.default
        options.keepAlive = configuration.modelKeepAlive
        options.timeoutSeconds = configuration.modelTimeoutSeconds
        options.retryLimit = configuration.modelRetryLimit
        options.responseRepairAttempts = configuration.modelResponseRepairAttempts
        // 0 means "model default": send no num_ctx and let Ollama size the window.
        options.contextWindow = configuration.modelContextWindow > 0 ? configuration.modelContextWindow : nil
        options.maxResponseTokens = configuration.modelMaxResponseTokens
        do {
            let prompt = try PromptRegistry.prompt(
                for: role, task: configuration.taskProfile, context: modelInputContext)
            let schema = try ResponseSchemas.schema(for: role, task: configuration.taskProfile)
            let runner = self.runner
            let task = Task {
                await runner.analyze(
                    image: derivative,
                    inputRole: role,
                    prompt: prompt,
                    schema: schema,
                    options: options,
                    runtime: runtime,
                    isInterrupted: { interruptionMonitor?.isInterrupted == true }
                )
            }
            let registration = interruptionMonitor?.onInterruption {
                task.cancel()
            }
            defer { registration?.cancel() }
            var record = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            record.modelInputContext = modelInputContext?.isEmpty == false ? modelInputContext : nil
            return record
        } catch {
            return ModelRunRecord(
                inputRole: role,
                model: runtime.model,
                modelDigest: runtime.modelDigest,
                runtime: runtime.runtime,
                runtimeVersion: runtime.runtimeVersion,
                promptVersion: "",
                promptSHA256: "",
                responseSchemaVersion: "",
                requestOptions: options,
                modelInputContext: modelInputContext?.isEmpty == false ? modelInputContext : nil,
                inputDerivativeSHA256: derivative.sha256,
                rawResponseText: "",
                parsedResponseJSON: nil,
                jsonValid: false,
                durationMs: 0,
                error: Self.modelPreparationError(from: error, role: role)
            )
        }
    }

    private func modelInputs(
        derivatives: [DerivativeRecord],
        mode: AnalysisMode
    ) -> [(ModelInputRole, DerivativeRecord)] {
        let whole = derivatives.first { $0.role == .wholeImage }
        let subject = derivatives.first { $0.role == .subjectIsolated }
        switch mode {
        case .whole:
            return whole.map { [(.wholeImage, $0)] } ?? []
        case .subject:
            return subject.map { [(.subjectIsolated, $0)] } ?? []
        case .both:
            return [
                whole.map { (.wholeImage, $0) },
                subject.map { (.subjectIsolated, $0) },
            ].compactMap { $0 }
        }
    }

    private func reportDirectoryPath(scanRoot: String, outputDir: String?) -> String {
        let path = outputDir ?? scanRoot
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private func durationMs(from start: Date, to end: Date) -> Int {
        Self.durationMs(from: start, to: end)
    }

    private static func durationMs(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }

    private func logRecord(for record: ProgressRecord) -> LogRecord {
        let level: LogLevel = record.status == .failed ? .error : (record.errors.isEmpty ? .info : .warn)
        let message: String
        switch record.status {
        case .written:
            message = record.errors.isEmpty ? "Wrote sidecar." : "Wrote sidecar with recoverable errors."
        case .skippedExisting:
            message = "Skipped existing sidecar."
        case .failed:
            message = record.errors.first?.message ?? "Analysis failed."
        case .dryRun:
            message = "Dry run planned sidecar."
        }

        return LogRecord(
            timestamp: record.timestamp,
            level: level,
            event: "analyze.\(record.status.rawValue)",
            message: message,
            sourcePath: record.sourcePath,
            sidecarPath: record.sidecarPath,
            status: record.status.rawValue,
            errors: record.errors
        )
    }

    private static func sidecarError(from error: Error, sidecarPath: String) -> SidecarError {
        if let sidecarError = error as? SidecarError {
            return sidecarError
        }
        return SidecarError(
            code: .renderFailed,
            stage: .render,
            message: "Unable to render derivative before writing \(sidecarPath): \(error.localizedDescription)",
            recoverable: true
        )
    }

    private static func subjectIsolationError(from error: Error) -> SidecarError {
        if let sidecarError = error as? SidecarError, sidecarError.stage == .isolate {
            return sidecarError
        }
        return SidecarError(
            code: .subjectIsolationFailed,
            stage: .isolate,
            message: "Unable to isolate subject: \(error.localizedDescription)",
            recoverable: true
        )
    }

    private static func modelPreparationError(from error: Error, role: ModelInputRole) -> SidecarError {
        if let sidecarError = error as? SidecarError {
            return sidecarError
        }
        return SidecarError(
            code: .validationFailed,
            stage: .model,
            message: "Unable to prepare \(role.rawValue) model prompt or schema: \(error.localizedDescription)",
            recoverable: true
        )
    }

    private static func failedSubjectIsolationRecord(
        prepared: PreparedSourceRender,
        configuration: ResolvedRunConfiguration,
        profile: ModelInputProfile
    ) -> SubjectIsolationRecord {
        let analysisDimensions = prepared.analysisDimensions
        let fullDimensions = prepared.fullDimensions
        return SubjectIsolationRecord(
            status: .failed,
            instanceCount: 0,
            selectedInstanceIndices: [],
            mergedInstances: false,
            instances: [],
            analysisResolution: analysisDimensions,
            fullResolution: fullDimensions,
            scaleFactors: SubjectIsolationScaleFactors(
                x: Double(fullDimensions.width) / Double(analysisDimensions.width),
                y: Double(fullDimensions.height) / Double(analysisDimensions.height)
            ),
            selectedBoundingBox: nil,
            cropBoundingBox: nil,
            cropMarginFraction: configuration.subjectCropMarginFraction,
            cropMarginPixels: 0,
            mergeDominanceThreshold: configuration.subjectMergeDominanceThreshold,
            selectedToUnionAreaRatio: nil,
            matteRGB: profile.matteRGB,
            finalDimensions: nil,
            upscaled: false
        )
    }
}

private struct PendingWork: Sendable {
    var index: Int
}

private enum EntryAction: Sendable {
    case dryRun(Date)
    case existingSkip(Date)
    case existingFailure(SidecarError, Date)
    case pending(Date)
}

private enum PreparedAnalysis: Sendable {
    case prepared(PreparedRenderedAnalysis)
    case renderFailed(SidecarError, renderMs: Int)

    var derivatives: [DerivativeRecord] {
        switch self {
        case .prepared(let prepared):
            return prepared.derivatives
        case .renderFailed:
            return []
        }
    }
}

private enum FinishPreparedOutcome: Sendable {
    case completed(ProgressRecord)
    case interrupted
}

private enum ModelRunsOutcome: Sendable {
    case completed([ModelRunRecord])
    case interrupted
}

private struct PreparedRenderedAnalysis: Sendable {
    var derivatives: [DerivativeRecord]
    var modelInputContext: ModelInputContext?
    var subjectIsolation: SubjectIsolationRecord?
    var errors: [SidecarError]
    var renderMs: Int
    var subjectIsolationMs: Int
}

private struct PipelineUnavailableForegroundMaskProvider: ForegroundMaskProvider {
    func foregroundMasks(in _: CIImage, dimensions _: PixelDimensions) async throws -> ForegroundMaskResult {
        throw SidecarError(
            code: .subjectIsolationFailed,
            stage: .isolate,
            message: "Apple Vision foreground masking requires macOS 15 or newer.",
            recoverable: true
        )
    }
}
