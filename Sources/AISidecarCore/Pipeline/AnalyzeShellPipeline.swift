import Foundation

/// Result of the analyze shell pipeline.
public struct AnalyzeShellResult: Sendable, Equatable {
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

/// Phase 1 analyze pipeline through Milestone 3 rendering.
///
/// Subject isolation and model runtime remain deferred, but rendered derivative
/// provenance is now recorded in the raw sidecar.
public struct AnalyzeShellPipeline {
    private let fileManager: FileManager
    private let scanner: ImageScanner
    private let writer: RawJSONSidecarWriter
    private let summaryWriter: BatchSummaryWriter
    private let logger: Logger
    private let now: @Sendable () -> Date

    public init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.scanner = ImageScanner(fileManager: fileManager)
        self.writer = RawJSONSidecarWriter(fileManager: fileManager)
        self.summaryWriter = BatchSummaryWriter(fileManager: fileManager)
        self.logger = logger
        self.now = now
    }

    /// Run the analyze shell pipeline for one file or one folder.
    ///
    /// Folder runs create progress and summary artifacts unless `dryRun` is set;
    /// single-file runs write only the sidecar shell and log status.
    public func run(
        inputPath: String,
        configuration: ResolvedRunConfiguration,
        interruptionMonitor: InterruptionMonitor? = nil
    ) throws -> AnalyzeShellResult {
        let runStartedAt = now()
        let profile = try ModelInputProfileRegistry.resolve(name: configuration.profile)
        let renderer = ImageRenderer(
            cache: DerivativeCache(
                directoryPath: configuration.derivativeCacheDir,
                sizeCapBytes: configuration.derivativeCacheSizeBytes,
                fileManager: fileManager,
                now: now
            )
        )
        let scanResult = try scanner.scan(
            inputPath: inputPath,
            recursive: configuration.recursive,
            identityPolicy: configuration.sourceIdentityPolicy
        )
        let isBatch = scanResult.inputPath == scanResult.scanRoot
        let timestamp = timestampString(for: runStartedAt)
        let reportDirectory = reportDirectoryPath(scanRoot: scanResult.scanRoot, outputDir: configuration.outputDir)
        // FR1-012 defines progress and summary artifacts for folder runs; a
        // single file writes only its sidecar shell and CLI status.
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
            // `--dry-run` is the first write-capable milestone's preview mode:
            // it reports planned sidecars without creating any artifacts.
            if !configuration.dryRun {
                try progressLog?.append(record)
            }
            try logger.log(logRecord(for: record))
        }

        for scanError in scanResult.errors {
            let record = ProgressRecord(
                timestamp: now(),
                sourcePath: scanError.path,
                relativePath: scanError.relativePath,
                sidecarPath: nil,
                status: .failed,
                errors: [scanError.error],
                durationMs: 0
            )
            try emit(record)
        }

        let plan = SidecarNaming.plan(for: scanResult.images, outputDir: configuration.outputDir)
        for collision in plan.collisions {
            for source in collision.sources {
                let record = ProgressRecord(
                    timestamp: now(),
                    sourcePath: source.path,
                    relativePath: source.relativePath,
                    sidecarPath: collision.sidecarPath,
                    status: .failed,
                    errors: [collision.error],
                    durationMs: 0
                )
                try emit(record)
            }
        }

        for entry in plan.entries {
            if interruptionMonitor?.isInterrupted == true {
                // Stop before starting the next file; the previous file's
                // sidecar and progress record are already complete or absent.
                interrupted = true
                break
            }

            let fileStartedAt = now()
            let record: ProgressRecord
            if configuration.dryRun {
                record = ProgressRecord(
                    timestamp: now(),
                    sourcePath: entry.source.path,
                    relativePath: entry.source.relativePath,
                    sidecarPath: entry.sidecarPath,
                    status: .dryRun,
                    durationMs: durationMs(from: fileStartedAt, to: now())
                )
            } else {
                record = process(
                    entry,
                    configuration: configuration,
                    profile: profile,
                    renderer: renderer,
                    fileStartedAt: fileStartedAt
                )
            }

            try emit(record)
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

        return AnalyzeShellResult(
            scanResult: scanResult,
            records: records,
            progressLogPath: progressPath,
            summaryPath: summaryPath,
            summary: summary,
            interrupted: interrupted
        )
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
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }

    private func logRecord(for record: ProgressRecord) -> LogRecord {
        let level: LogLevel = record.status == .failed ? .error : .info
        let message: String
        switch record.status {
        case .written:
            message = "Wrote sidecar."
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

    private func process(
        _ entry: SidecarPlanEntry,
        configuration: ResolvedRunConfiguration,
        profile: ModelInputProfile,
        renderer: ImageRenderer,
        fileStartedAt: Date
    ) -> ProgressRecord {
        if fileManager.fileExists(atPath: entry.sidecarPath) {
            switch configuration.existing {
            case .skip:
                return ProgressRecord(
                    timestamp: now(),
                    sourcePath: entry.source.path,
                    relativePath: entry.source.relativePath,
                    sidecarPath: entry.sidecarPath,
                    status: .skippedExisting,
                    durationMs: durationMs(from: fileStartedAt, to: now())
                )
            case .fail:
                return ProgressRecord(
                    timestamp: now(),
                    sourcePath: entry.source.path,
                    relativePath: entry.source.relativePath,
                    sidecarPath: entry.sidecarPath,
                    status: .failed,
                    errors: [
                        SidecarError(
                            code: .sidecarExists,
                            stage: .write,
                            message: "Sidecar already exists: \(entry.sidecarPath)",
                            recoverable: true
                        )
                    ],
                    durationMs: durationMs(from: fileStartedAt, to: now())
                )
            case .overwrite:
                break
            }
        }

        do {
            let rendered = try renderer.renderWholeImageSet(
                source: entry.source,
                profile: profile,
                debugDerivatives: configuration.debugDerivatives
            )
            let sidecar = RawJSONSidecar(
                source: entry.source,
                runConfiguration: configuration,
                modelInputProfile: profile,
                derivatives: rendered.derivatives,
                createdAt: now()
            )
            let outcome = try writer.write(
                sidecar,
                to: entry.sidecarPath,
                existingPolicy: configuration.existing
            )
            return ProgressRecord(
                timestamp: now(),
                sourcePath: entry.source.path,
                relativePath: entry.source.relativePath,
                sidecarPath: entry.sidecarPath,
                status: outcome.status == .written ? .written : .skippedExisting,
                durationMs: durationMs(from: fileStartedAt, to: now())
            )
        } catch {
            let renderError = sidecarError(from: error, sidecarPath: entry.sidecarPath)
            var errors = [renderError]
            let errorSidecar = RawJSONSidecar(
                source: entry.source,
                runConfiguration: configuration,
                modelInputProfile: profile,
                errors: [renderError],
                createdAt: now()
            )
            do {
                _ = try writer.write(
                    errorSidecar,
                    to: entry.sidecarPath,
                    existingPolicy: configuration.existing
                )
            } catch {
                errors.append(sidecarError(from: error, sidecarPath: entry.sidecarPath))
            }

            return ProgressRecord(
                timestamp: now(),
                sourcePath: entry.source.path,
                relativePath: entry.source.relativePath,
                sidecarPath: entry.sidecarPath,
                status: .failed,
                errors: errors,
                durationMs: durationMs(from: fileStartedAt, to: now())
            )
        }
    }

    private func sidecarError(from error: Error, sidecarPath: String) -> SidecarError {
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
}
