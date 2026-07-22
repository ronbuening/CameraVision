import Foundation

/// Diagnostic pipeline that exports the exact model-input images without writing sidecars.
public struct ModelInputExportPipeline {
    private let fileManager: FileManager
    private let scanner: ImageScanner
    private let logger: Logger
    private let maskProvider: any ForegroundMaskProvider
    private let now: @Sendable () -> Date
    private let filenameSuffix: @Sendable () -> String

    public init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(),
        maskProvider: (any ForegroundMaskProvider)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        filenameSuffix: @escaping @Sendable () -> String = Timestamp.randomFilenameSuffix
    ) {
        self.fileManager = fileManager
        self.scanner = ImageScanner(fileManager: fileManager)
        self.logger = logger
        self.maskProvider = maskProvider ?? .makeDefault()
        self.now = now
        self.filenameSuffix = filenameSuffix
    }

    /// Ensure export mode writes only its requested destination artifacts.
    public static func validate(configuration: ResolvedRunConfiguration) throws {
        if configuration.dryRun {
            throw SidecarError.configInvalid("--export-model-inputs cannot be combined with --dry-run.")
        }
        if configuration.debugDerivatives {
            throw SidecarError.configInvalid("--export-model-inputs cannot be combined with --debug-derivatives.")
        }
    }

    /// Render and export model-input derivatives, then write one manifest.
    public func run(
        inputPath: String,
        exportDirectoryPath: String,
        configuration: ResolvedRunConfiguration,
        interruptionMonitor: InterruptionMonitor? = nil
    ) async throws -> ModelInputExportResult {
        try Self.validate(configuration: configuration)

        let startedAt = now()
        let profile = try ModelInputProfileRegistry.resolve(name: configuration.profile)
        let exportDirectory = URL(fileURLWithPath: (exportDirectoryPath as NSString).expandingTildeInPath)
            .standardizedFileURL
            .path
        let cache = DerivativeCache(
            directoryPath: configuration.derivativeCacheDir,
            sizeCapBytes: configuration.derivativeCacheSizeBytes,
            fileManager: fileManager,
            now: now
        )
        defer { cache.releaseRetained() }
        if configuration.clearDerivativeCacheOnStart {
            try cache.clear()
        }
        let renderer = ImageRenderer(cache: cache)
        let subjectIsolationService = SubjectIsolationService(cache: cache, maskProvider: maskProvider)
        let scanResult = try await scanner.scan(
            inputPath: inputPath,
            recursive: configuration.recursive,
            identityPolicy: configuration.sourceIdentityPolicy,
            stageConcurrency: configuration.stageConcurrency
        )
        let plan = ModelInputExportNaming.plan(
            for: scanResult.images,
            mode: configuration.mode,
            profile: profile,
            exportDirectory: exportDirectory
        )

        var records: [ModelInputExportRecord] = []
        for scanError in scanResult.errors {
            let record = ModelInputExportRecord(
                timestamp: now(),
                source: nil,
                sourcePath: scanError.path,
                relativePath: scanError.relativePath,
                status: .failed,
                errors: [scanError.error],
                durationMs: 0
            )
            records.append(record)
            try logger.log(logRecord(for: record))
        }
        var interrupted = false

        for collision in plan.collisions {
            let timestamp = now()
            for source in collision.sources {
                let record = ModelInputExportRecord(
                    timestamp: timestamp,
                    source: source,
                    sourcePath: source.path,
                    relativePath: source.relativePath,
                    status: .failed,
                    errors: [collision.error],
                    durationMs: 0
                )
                records.append(record)
                try logger.log(logRecord(for: record))
            }
        }

        for entry in plan.entries {
            if interruptionMonitor?.isInterrupted == true {
                interrupted = true
                break
            }

            let sourceStartedAt = now()
            let record = await process(
                entry,
                configuration: configuration,
                profile: profile,
                renderer: renderer,
                subjectIsolationService: subjectIsolationService,
                cache: cache,
                sourceStartedAt: sourceStartedAt
            )
            records.append(record)
            try logger.log(logRecord(for: record))
        }

        if interruptionMonitor?.isInterrupted == true {
            interrupted = true
        }

        let summary = ModelInputExportSummary.derive(
            totalImages: scanResult.images.count,
            records: records,
            interrupted: interrupted
        )
        let manifest = ModelInputExportManifest(
            createdAt: now(),
            inputPath: scanResult.inputPath,
            scanRoot: scanResult.scanRoot,
            recursive: scanResult.recursive,
            mode: configuration.mode,
            exportDir: exportDirectory,
            modelInputProfile: profile,
            records: records,
            summary: summary
        )
        let timestamp = Timestamp.filenameToken(startedAt, suffix: filenameSuffix())
        let manifestPath = "\(exportDirectory)/\(ArtifactNames.modelInputExportManifestPrefix)\(timestamp).json"
        try writeManifest(manifest, to: manifestPath)

        if configuration.clearDerivativeCacheAfterSuccess,
            completedSuccessfully(records: records, interrupted: interrupted)
        {
            try cache.clear()
        }

        return ModelInputExportResult(
            scanResult: scanResult,
            records: records,
            manifestPath: manifestPath,
            manifest: manifest,
            interrupted: interrupted
        )
    }

    private func process(
        _ entry: ModelInputExportPlanEntry,
        configuration: ResolvedRunConfiguration,
        profile: ModelInputProfile,
        renderer: ImageRenderer,
        subjectIsolationService: SubjectIsolationService,
        cache: DerivativeCache,
        sourceStartedAt: Date
    ) async -> ModelInputExportRecord {
        var leasedDerivatives: [DerivativeRecord] = []
        defer { cache.release(leasedDerivatives) }
        do {
            if configuration.existing == .fail,
                let existingOutput = entry.plannedOutputs.first(where: { fileManager.fileExists(atPath: $0.path) })
            {
                return failedRecord(
                    source: entry.source,
                    startedAt: sourceStartedAt,
                    error: SidecarError(
                        code: .sidecarExists,
                        stage: .write,
                        message: "Export output already exists: \(existingOutput.path)",
                        recoverable: true
                    )
                )
            }

            var outputs: [ModelInputExportOutput] = []
            var subjectIsolation: SubjectIsolationRecord?
            var errors: [SidecarError] = []

            switch configuration.mode {
            case .whole:
                let rendered = try renderer.renderWholeImage(
                    source: entry.source,
                    profile: profile,
                    debugDerivatives: false
                )
                leasedDerivatives.append(rendered.wholeImage)
                if let wholeOutput = entry.plannedOutput(for: .wholeImage) {
                    outputs.append(
                        try exportArtifact(
                            rendered.wholeImage,
                            to: wholeOutput,
                            existing: configuration.existing
                        )
                    )
                }
            case .subject, .both:
                let prepared = try renderer.prepareSourceRender(source: entry.source, profile: profile)
                if let wholeOutput = entry.plannedOutput(for: .wholeImage) {
                    let whole = try renderer.renderWholeImageDerivative(
                        source: entry.source,
                        prepared: prepared,
                        profile: profile,
                        debugDerivatives: false
                    )
                    leasedDerivatives.append(whole)
                    outputs.append(
                        try exportArtifact(
                            whole,
                            to: wholeOutput,
                            existing: configuration.existing
                        )
                    )
                }

                do {
                    let isolation = try await subjectIsolationService.isolate(
                        source: entry.source,
                        prepared: prepared,
                        profile: profile,
                        configuration: configuration
                    )
                    subjectIsolation = isolation.record
                    if let derivative = isolation.derivative {
                        leasedDerivatives.append(derivative)
                        if let subjectOutput = entry.plannedOutput(for: .subjectIsolated) {
                            outputs.append(
                                try exportArtifact(
                                    derivative,
                                    to: subjectOutput,
                                    existing: configuration.existing
                                )
                            )
                        }
                    }
                    if let error = isolation.error {
                        errors.append(error)
                    }
                } catch {
                    let failure = SubjectIsolationFailure.make(
                        from: error,
                        prepared: prepared,
                        configuration: configuration,
                        profile: profile
                    )
                    subjectIsolation = failure.record
                    errors.append(failure.error)
                }
            }

            return ModelInputExportRecord(
                timestamp: now(),
                source: entry.source,
                sourcePath: entry.source.path,
                relativePath: entry.source.relativePath,
                status: status(outputs: outputs, errors: errors),
                outputs: outputs,
                subjectIsolation: subjectIsolation,
                errors: errors,
                durationMs: Timestamp.durationMs(from: sourceStartedAt, to: now())
            )
        } catch {
            return failedRecord(
                source: entry.source,
                startedAt: sourceStartedAt,
                error: exportError(from: error)
            )
        }
    }

    private func exportArtifact(
        _ derivative: DerivativeRecord,
        to plannedOutput: ModelInputExportPlannedOutput,
        existing: ExistingPolicy
    ) throws -> ModelInputExportOutput {
        let destination = URL(fileURLWithPath: plannedOutput.path)
        if fileManager.fileExists(atPath: plannedOutput.path) {
            switch existing {
            case .skip:
                return ModelInputExportOutput(
                    derivative: derivative,
                    plannedOutput: plannedOutput,
                    action: .skippedExisting
                )
            case .fail:
                throw SidecarError(
                    code: .sidecarExists,
                    stage: .write,
                    message: "Export output already exists: \(plannedOutput.path)",
                    recoverable: true
                )
            case .overwrite:
                break
            }
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: derivative.cachePath))
            try AtomicFileWriter.write(data, to: destination, fileManager: fileManager)
            return ModelInputExportOutput(
                derivative: derivative,
                plannedOutput: plannedOutput,
                action: .exported
            )
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to export model input \(plannedOutput.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func status(outputs: [ModelInputExportOutput], errors: [SidecarError]) -> ModelInputExportStatus {
        if outputs.isEmpty {
            return .failed
        }
        if !errors.isEmpty {
            return .partial
        }
        if outputs.allSatisfy({ $0.action == .skippedExisting }) {
            return .skippedExisting
        }
        return .exported
    }

    private func failedRecord(source: SourceImage, startedAt: Date, error: SidecarError) -> ModelInputExportRecord {
        ModelInputExportRecord(
            timestamp: now(),
            source: source,
            sourcePath: source.path,
            relativePath: source.relativePath,
            status: .failed,
            errors: [error],
            durationMs: Timestamp.durationMs(from: startedAt, to: now())
        )
    }

    private func exportError(from error: Error) -> SidecarError {
        if let sidecarError = error as? SidecarError {
            return sidecarError
        }
        return SidecarError(
            code: .writeFailed,
            stage: .write,
            message: "Unable to export model input: \(error.localizedDescription)",
            recoverable: true
        )
    }

    private func logRecord(for record: ModelInputExportRecord) -> LogRecord {
        let level: LogLevel = record.status == .failed ? .error : (record.errors.isEmpty ? .info : .warn)
        let message: String
        switch record.status {
        case .exported:
            message = "Exported model input."
        case .partial:
            message = "Exported partial model input set."
        case .skippedExisting:
            message = "Skipped existing model input export."
        case .failed:
            message = record.errors.first?.message ?? "Model input export failed."
        }
        return LogRecord(
            timestamp: record.timestamp,
            level: level,
            event: "model_input_export.\(record.status.rawValue)",
            message: message,
            sourcePath: record.sourcePath,
            status: record.status.rawValue,
            errors: record.errors
        )
    }

    private func writeManifest(_ manifest: ModelInputExportManifest, to path: String) throws {
        do {
            let encoder = JSONCoding.documentEncoder()
            let data = try encoder.encode(manifest)
            try AtomicFileWriter.write(data, to: URL(fileURLWithPath: path), fileManager: fileManager)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to write model input export manifest \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func completedSuccessfully(records: [ModelInputExportRecord], interrupted: Bool) -> Bool {
        !interrupted && records.allSatisfy { $0.status == .exported || $0.status == .skippedExisting }
    }
}
