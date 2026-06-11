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
    private let writer: RawJSONSidecarWriter
    private let summaryWriter: BatchSummaryWriter
    private let logger: Logger
    private let maskProvider: any ForegroundMaskProvider
    private let runner: any VisionModelRunner
    private let now: @Sendable () -> Date

    public init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(),
        maskProvider: (any ForegroundMaskProvider)? = nil,
        runner: any VisionModelRunner = OllamaVisionRunner(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.scanner = ImageScanner(fileManager: fileManager)
        self.writer = RawJSONSidecarWriter(fileManager: fileManager)
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
    }

    /// Run full Phase 1 analysis for one file or folder.
    ///
    /// Folder runs create progress and summary artifacts after model preflight
    /// succeeds; single-file runs write only the raw sidecar and console status.
    public func run(
        inputPath: String,
        configuration: ResolvedRunConfiguration,
        interruptionMonitor: InterruptionMonitor? = nil
    ) async throws -> AnalyzeResult {
        let runStartedAt = now()
        let profile = try ModelInputProfileRegistry.resolve(name: configuration.profile)
        let lifecycleCache = cache(for: configuration)
        if configuration.clearDerivativeCacheOnStart {
            try lifecycleCache.clear()
        }
        let scanResult = try scanner.scan(
            inputPath: inputPath,
            recursive: configuration.recursive,
            identityPolicy: configuration.sourceIdentityPolicy
        )
        let plan = SidecarNaming.plan(for: scanResult.images, outputDir: configuration.outputDir)
        let actions = entryActions(for: plan.entries, configuration: configuration)
        let pendingWork = actions.enumerated().compactMap { index, action -> PendingWork? in
            guard case .pending(let startedAt) = action else {
                return nil
            }
            return PendingWork(index: index, entry: plan.entries[index], startedAt: startedAt)
        }

        // FR1-030b fail-fast model verification must happen before progress,
        // cache, sidecar, or summary artifacts are created for model work.
        let runtime = pendingWork.isEmpty ? nil : try await runner.prepare(configuration: configuration)

        let isBatch = scanResult.inputPath == scanResult.scanRoot
        let timestamp = timestampString(for: runStartedAt)
        let reportDirectory = reportDirectoryPath(scanRoot: scanResult.scanRoot, outputDir: configuration.outputDir)
        let progressPath = isBatch && !configuration.dryRun
            ? "\(reportDirectory)/batch-progress-\(timestamp).jsonl"
            : nil
        let summaryPath = isBatch && !configuration.dryRun
            ? "\(reportDirectory)/batch-summary-\(timestamp).json"
            : nil
        let progressLog = try progressPath.map { try ProgressLog(path: $0, fileManager: fileManager) }
        defer {
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
           completedSuccessfully(records: records, interrupted: interrupted) {
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
        interruptionMonitor: InterruptionMonitor?,
        emit: (ProgressRecord) throws -> Void
    ) async throws -> Bool {
        var interrupted = false
        let maxWorkers = max(1, min(configuration.stageConcurrency, pendingWork.count))
        let fileManagerBox = SendableFileManager(fileManager)
        let maskProvider = maskProvider
        let now = now

        var preparedByIndex: [Int: PreparedAnalysis] = [:]
        var nextPendingToSchedule = 0
        var inFlight = 0

        try await withThrowingTaskGroup(of: (Int, PreparedAnalysis).self) { group in
            func fillWorkers() {
                while inFlight < maxWorkers, nextPendingToSchedule < pendingWork.count {
                    let work = pendingWork[nextPendingToSchedule]
                    nextPendingToSchedule += 1
                    inFlight += 1
                    group.addTask {
                        let prepared = await Self.prepare(
                            entry: work.entry,
                            configuration: configuration,
                            profile: profile,
                            fileManager: fileManagerBox.value,
                            maskProvider: maskProvider,
                            now: now
                        )
                        return (work.index, prepared)
                    }
                }
            }

            fillWorkers()

            // Prepared results may finish out of order, but sidecar/progress
            // emission stays in scan order and model calls happen in this loop.
            for (index, action) in actions.enumerated() {
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

                    let record = await finishPrepared(
                        prepared,
                        entry: entries[index],
                        configuration: configuration,
                        profile: profile,
                        runtime: runtime,
                        startedAt: startedAt
                    )
                    try emit(record)
                }
            }

            group.cancelAll()
        }

        return interrupted
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
        fileManager: FileManager,
        maskProvider: any ForegroundMaskProvider,
        now: @escaping @Sendable () -> Date
    ) async -> PreparedAnalysis {
        let renderStartedAt = now()
        do {
            let cache = DerivativeCache(
                directoryPath: configuration.derivativeCacheDir,
                sizeCapBytes: configuration.derivativeCacheSizeBytes,
                fileManager: fileManager,
                now: now
            )
            let renderer = ImageRenderer(cache: cache)
            let subjectIsolationService = SubjectIsolationService(cache: cache, maskProvider: maskProvider)
            let rendered = try renderer.renderWholeImageSet(
                source: entry.source,
                profile: profile,
                debugDerivatives: configuration.debugDerivatives
            )
            let renderMs = Self.durationMs(from: renderStartedAt, to: now())
            var derivatives = rendered.derivatives
            var subjectIsolation: SubjectIsolationRecord?
            var errors: [SidecarError] = []
            var subjectIsolationMs = 0

            if configuration.mode != .whole {
                let isolationStartedAt = now()
                do {
                    let isolation = try await subjectIsolationService.isolate(
                        source: entry.source,
                        rendered: rendered,
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
                        rendered: rendered,
                        configuration: configuration,
                        profile: profile
                    )
                    errors.append(isolationError)
                }
            }

            return .prepared(
                PreparedRenderedAnalysis(
                    derivatives: derivatives,
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
        startedAt: Date
    ) async -> ProgressRecord {
        switch prepared {
        case .renderFailed(let error, let renderMs):
            return writeFailureSidecar(
                source: entry.source,
                sidecarPath: entry.sidecarPath,
                configuration: configuration,
                profile: profile,
                errors: [error],
                renderMs: renderMs,
                startedAt: startedAt
            )
        case .prepared(let prepared):
            let modelStartedAt = now()
            let modelRuns = await runModelRuns(
                derivatives: prepared.derivatives,
                configuration: configuration,
                runtime: runtime
            )
            let modelMs = durationMs(from: modelStartedAt, to: now())
            let errors = prepared.errors + modelRuns.compactMap(\.error)
            var sidecar = RawJSONSidecar(
                source: entry.source,
                runConfiguration: configuration,
                modelInputProfile: profile,
                derivatives: prepared.derivatives,
                subjectIsolation: prepared.subjectIsolation,
                modelRuns: modelRuns,
                errors: errors,
                timing: PipelineTimingRecord(
                    pipelineElapsedMs: durationMs(from: startedAt, to: now()),
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
                if outcome.status == .written {
                    sidecar.timing?.writeMs = writeMs
                    sidecar.timing?.pipelineElapsedMs = durationMs(from: startedAt, to: now())
                    _ = try writer.write(sidecar, to: entry.sidecarPath, existingPolicy: .overwrite)
                }
                let status: ProgressStatus
                switch outcome.status {
                case .skippedExisting:
                    status = .skippedExisting
                case .written:
                    status = modelRuns.contains { $0.error == nil && $0.jsonValid } ? .written : .failed
                }
                return ProgressRecord(
                    timestamp: now(),
                    sourcePath: entry.source.path,
                    relativePath: entry.source.relativePath,
                    sidecarPath: entry.sidecarPath,
                    status: status,
                    errors: errors,
                    durationMs: durationMs(from: startedAt, to: now())
                )
            } catch {
                return ProgressRecord(
                    timestamp: now(),
                    sourcePath: entry.source.path,
                    relativePath: entry.source.relativePath,
                    sidecarPath: entry.sidecarPath,
                    status: .failed,
                    errors: errors + [Self.sidecarError(from: error, sidecarPath: entry.sidecarPath)],
                    durationMs: durationMs(from: startedAt, to: now())
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
        var errorSidecar = RawJSONSidecar(
            source: source,
            runConfiguration: configuration,
            modelInputProfile: profile,
            errors: errors,
            timing: PipelineTimingRecord(
                pipelineElapsedMs: durationMs(from: startedAt, to: now()),
                renderMs: renderMs,
                subjectIsolationMs: 0,
                modelMs: 0,
                writeMs: 0
            ),
            createdAt: now()
        )
        var progressErrors = errors
        do {
            let writeStartedAt = now()
            let outcome = try writer.write(errorSidecar, to: sidecarPath, existingPolicy: configuration.existing)
            let writeMs = durationMs(from: writeStartedAt, to: now())
            if outcome.status == .written {
                errorSidecar.timing?.writeMs = writeMs
                errorSidecar.timing?.pipelineElapsedMs = durationMs(from: startedAt, to: now())
                _ = try writer.write(errorSidecar, to: sidecarPath, existingPolicy: .overwrite)
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
            durationMs: durationMs(from: startedAt, to: now())
        )
    }

    private func runModelRuns(
        derivatives: [DerivativeRecord],
        configuration: ResolvedRunConfiguration,
        runtime: ModelRuntimeContext
    ) async -> [ModelRunRecord] {
        var runs: [ModelRunRecord] = []
        // PW-015 requires exactly one model request in flight; keep this loop
        // sequential even when render/isolation preparation has worked ahead.
        for (role, derivative) in modelInputs(derivatives: derivatives, mode: configuration.mode) {
            runs.append(await runModel(role: role, derivative: derivative, configuration: configuration, runtime: runtime))
        }
        return runs
    }

    private func runModel(
        role: ModelInputRole,
        derivative: DerivativeRecord,
        configuration: ResolvedRunConfiguration,
        runtime: ModelRuntimeContext
    ) async -> ModelRunRecord {
        var options = ModelRunOptions.default
        options.keepAlive = configuration.modelKeepAlive
        options.responseRepairAttempts = configuration.modelResponseRepairAttempts
        do {
            let prompt = try PromptRegistry.prompt(for: role)
            let schema = try ResponseSchemas.schema(for: role)
            return await runner.analyze(
                image: derivative,
                inputRole: role,
                prompt: prompt,
                schema: schema,
                options: options,
                runtime: runtime
            )
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
                subject.map { (.subjectIsolated, $0) }
            ].compactMap { $0 }
        }
    }

    private func reportDirectoryPath(scanRoot: String, outputDir: String?) -> String {
        let path = outputDir ?? scanRoot
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private func timestampString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
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
        rendered: WholeImageRenderResult,
        configuration: ResolvedRunConfiguration,
        profile: ModelInputProfile
    ) -> SubjectIsolationRecord {
        let analysisDimensions = PixelDimensions(width: rendered.wholeImage.width, height: rendered.wholeImage.height)
        let fullDimensions = PixelDimensions(width: rendered.fullResolution.width, height: rendered.fullResolution.height)
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
    var entry: SidecarPlanEntry
    var startedAt: Date
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
}

private struct PreparedRenderedAnalysis: Sendable {
    var derivatives: [DerivativeRecord]
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

private struct SendableFileManager: @unchecked Sendable {
    var value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}
