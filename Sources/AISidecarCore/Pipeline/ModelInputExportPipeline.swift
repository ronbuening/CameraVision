import CoreImage
import Foundation

/// Per-source outcome for diagnostic model-input export runs.
public enum ModelInputExportStatus: String, Codable, Sendable, Equatable {
    case exported
    case partial
    case skippedExisting = "skipped_existing"
    case failed
}

/// File-level write action recorded for exported model-input artifacts.
public enum ModelInputExportWriteAction: String, Codable, Sendable, Equatable {
    case exported
    case skippedExisting = "skipped_existing"
}

/// One model-input image written, or intentionally left in place, by an export run.
///
/// The provenance mirrors `DerivativeRecord` while using the export destination
/// path, so users can inspect exactly which files would be submitted to a model.
public struct ModelInputExportOutput: Codable, Sendable, Equatable {
    public var role: DerivativeRole
    public var path: String
    public var relativePath: String
    public var action: ModelInputExportWriteAction
    public var format: DerivativeFormat
    public var width: Int
    public var height: Int
    public var colorSpace: ModelInputColorSpace
    public var appliedOrientation: AppliedOrientation
    public var recipeVersion: String
    public var sha256: String
    public var sourceIdentity: SourceIdentity

    enum CodingKeys: String, CodingKey {
        case role
        case path
        case relativePath = "relative_path"
        case action
        case format
        case width
        case height
        case colorSpace = "color_space"
        case appliedOrientation = "applied_orientation"
        case recipeVersion = "recipe_version"
        case sha256
        case sourceIdentity = "source_identity"
    }

    fileprivate init(
        derivative: DerivativeRecord,
        plannedOutput: ModelInputExportPlannedOutput,
        action: ModelInputExportWriteAction
    ) {
        self.role = derivative.role
        self.path = plannedOutput.path
        self.relativePath = plannedOutput.relativePath
        self.action = action
        self.format = derivative.format
        self.width = derivative.width
        self.height = derivative.height
        self.colorSpace = derivative.colorSpace
        self.appliedOrientation = derivative.appliedOrientation
        self.recipeVersion = derivative.recipeVersion
        self.sha256 = derivative.sha256
        self.sourceIdentity = derivative.sourceIdentity
    }
}

/// One completed source-image record in a model-input export manifest.
public struct ModelInputExportRecord: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var source: SourceImage?
    public var sourcePath: String
    public var relativePath: String?
    public var status: ModelInputExportStatus
    public var outputs: [ModelInputExportOutput]
    public var subjectIsolation: SubjectIsolationRecord?
    public var errors: [SidecarError]
    public var durationMs: Int

    enum CodingKeys: String, CodingKey {
        case timestamp
        case source
        case sourcePath = "source_path"
        case relativePath = "relative_path"
        case status
        case outputs
        case subjectIsolation = "subject_isolation"
        case errors
        case durationMs = "duration_ms"
    }

    public init(
        timestamp: Date = Date(),
        source: SourceImage?,
        sourcePath: String,
        relativePath: String?,
        status: ModelInputExportStatus,
        outputs: [ModelInputExportOutput] = [],
        subjectIsolation: SubjectIsolationRecord? = nil,
        errors: [SidecarError] = [],
        durationMs: Int
    ) {
        self.timestamp = timestamp
        self.source = source
        self.sourcePath = sourcePath
        self.relativePath = relativePath
        self.status = status
        self.outputs = outputs
        self.subjectIsolation = subjectIsolation
        self.errors = errors
        self.durationMs = durationMs
    }
}

/// Aggregate counts and errors for one diagnostic export run.
public struct ModelInputExportSummary: Codable, Sendable, Equatable {
    public var totalImages: Int
    public var exported: Int
    public var partial: Int
    public var skipped: Int
    public var failed: Int
    public var errors: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case totalImages = "total_images"
        case exported
        case partial
        case skipped
        case failed
        case errors
    }

    public init(
        totalImages: Int,
        exported: Int,
        partial: Int,
        skipped: Int,
        failed: Int,
        errors: [SidecarError]
    ) {
        self.totalImages = totalImages
        self.exported = exported
        self.partial = partial
        self.skipped = skipped
        self.failed = failed
        self.errors = errors
    }

    public static func derive(
        totalImages: Int,
        records: [ModelInputExportRecord],
        interrupted: Bool
    ) -> ModelInputExportSummary {
        var errors = records.flatMap(\.errors)
        if interrupted {
            errors.append(
                SidecarError(
                    code: .interrupted,
                    stage: .write,
                    message: "Model-input export interrupted before all files completed.",
                    recoverable: true
                )
            )
        }

        return ModelInputExportSummary(
            totalImages: totalImages,
            exported: records.filter { $0.status == .exported }.count,
            partial: records.filter { $0.status == .partial }.count,
            skipped: records.filter { $0.status == .skippedExisting }.count,
            failed: records.filter { $0.status == .failed }.count,
            errors: errors
        )
    }
}

/// Manifest written by `aisidecar analyze --export-model-inputs`.
public struct ModelInputExportManifest: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var createdAt: Date
    public var inputPath: String
    public var scanRoot: String
    public var recursive: Bool
    public var mode: AnalysisMode
    public var exportDir: String
    public var modelInputProfile: ModelInputProfile
    public var records: [ModelInputExportRecord]
    public var summary: ModelInputExportSummary

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case inputPath = "input_path"
        case scanRoot = "scan_root"
        case recursive
        case mode
        case exportDir = "export_dir"
        case modelInputProfile = "model_input_profile"
        case records
        case summary
    }

    public init(
        schemaVersion: String = "ai-sidecar-model-input-export/1.0",
        createdAt: Date = Date(),
        inputPath: String,
        scanRoot: String,
        recursive: Bool,
        mode: AnalysisMode,
        exportDir: String,
        modelInputProfile: ModelInputProfile,
        records: [ModelInputExportRecord],
        summary: ModelInputExportSummary
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.inputPath = inputPath
        self.scanRoot = scanRoot
        self.recursive = recursive
        self.mode = mode
        self.exportDir = exportDir
        self.modelInputProfile = modelInputProfile
        self.records = records
        self.summary = summary
    }
}

/// Result returned by a diagnostic model-input export run.
public struct ModelInputExportResult: Sendable, Equatable {
    public var scanResult: ScanResult
    public var records: [ModelInputExportRecord]
    public var manifestPath: String
    public var manifest: ModelInputExportManifest
    public var interrupted: Bool

    public init(
        scanResult: ScanResult,
        records: [ModelInputExportRecord],
        manifestPath: String,
        manifest: ModelInputExportManifest,
        interrupted: Bool
    ) {
        self.scanResult = scanResult
        self.records = records
        self.manifestPath = manifestPath
        self.manifest = manifest
        self.interrupted = interrupted
    }
}

/// Diagnostic pipeline that exports the exact model-input images without writing sidecars.
public struct ModelInputExportPipeline {
    private let fileManager: FileManager
    private let scanner: ImageScanner
    private let logger: Logger
    private let maskProvider: any ForegroundMaskProvider
    private let now: @Sendable () -> Date

    public init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(),
        maskProvider: (any ForegroundMaskProvider)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.scanner = ImageScanner(fileManager: fileManager)
        self.logger = logger
        if let maskProvider {
            self.maskProvider = maskProvider
        } else if #available(macOS 15.0, *) {
            self.maskProvider = AppleVisionForegroundMaskProvider()
        } else {
            self.maskProvider = ExportUnavailableForegroundMaskProvider()
        }
        self.now = now
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
        if configuration.clearDerivativeCacheOnStart {
            try cache.clear()
        }
        let renderer = ImageRenderer(cache: cache)
        let subjectIsolationService = SubjectIsolationService(cache: cache, maskProvider: maskProvider)
        let scanResult = try scanner.scan(
            inputPath: inputPath,
            recursive: configuration.recursive,
            identityPolicy: configuration.sourceIdentityPolicy
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
        let manifestPath = "\(exportDirectory)/model-input-export-\(timestampString(for: startedAt)).json"
        try writeManifest(manifest, to: manifestPath)

        if configuration.clearDerivativeCacheAfterSuccess,
           completedSuccessfully(records: records, interrupted: interrupted) {
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
        sourceStartedAt: Date
    ) async -> ModelInputExportRecord {
        do {
            if configuration.existing == .fail,
               let existingOutput = entry.plannedOutputs.first(where: { fileManager.fileExists(atPath: $0.path) }) {
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

            let rendered = try renderer.renderWholeImageSet(
                source: entry.source,
                profile: profile,
                debugDerivatives: false
            )
            var outputs: [ModelInputExportOutput] = []
            var subjectIsolation: SubjectIsolationRecord?
            var errors: [SidecarError] = []

            if let wholeOutput = entry.plannedOutput(for: .wholeImage) {
                outputs.append(
                    try exportArtifact(
                        rendered.wholeImage,
                        to: wholeOutput,
                        existing: configuration.existing
                    )
                )
            }

            if configuration.mode != .whole {
                do {
                    let isolation = try await subjectIsolationService.isolate(
                        source: entry.source,
                        rendered: rendered,
                        profile: profile,
                        configuration: configuration
                    )
                    subjectIsolation = isolation.record
                    if let derivative = isolation.derivative,
                       let subjectOutput = entry.plannedOutput(for: .subjectIsolated) {
                        outputs.append(
                            try exportArtifact(
                                derivative,
                                to: subjectOutput,
                                existing: configuration.existing
                            )
                        )
                    }
                    if let error = isolation.error {
                        errors.append(error)
                    }
                } catch {
                    let isolationError = subjectIsolationError(from: error)
                    subjectIsolation = failedSubjectIsolationRecord(
                        rendered: rendered,
                        configuration: configuration,
                        profile: profile
                    )
                    errors.append(isolationError)
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
                durationMs: durationMs(from: sourceStartedAt, to: now())
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
            durationMs: durationMs(from: startedAt, to: now())
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

    private func subjectIsolationError(from error: Error) -> SidecarError {
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

    private func failedSubjectIsolationRecord(
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
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
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

    private func timestampString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func durationMs(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }

    private func completedSuccessfully(records: [ModelInputExportRecord], interrupted: Bool) -> Bool {
        !interrupted && records.allSatisfy { $0.status == .exported || $0.status == .skippedExisting }
    }
}

fileprivate struct ModelInputExportPlannedOutput: Sendable, Equatable {
    var role: DerivativeRole
    var path: String
    var relativePath: String

    init(role: DerivativeRole, path: String, relativePath: String) {
        self.role = role
        self.path = path
        self.relativePath = relativePath
    }
}

fileprivate struct ModelInputExportPlanEntry: Sendable, Equatable {
    var source: SourceImage
    var plannedOutputs: [ModelInputExportPlannedOutput]

    func plannedOutput(for role: DerivativeRole) -> ModelInputExportPlannedOutput? {
        plannedOutputs.first { $0.role == role }
    }
}

private struct ModelInputExportPlanCollision: Sendable, Equatable {
    var sources: [SourceImage]
    var error: SidecarError
}

private struct ModelInputExportPlan: Sendable, Equatable {
    var entries: [ModelInputExportPlanEntry]
    var collisions: [ModelInputExportPlanCollision]
}

private enum ModelInputExportNaming {
    static func plan(
        for sources: [SourceImage],
        mode: AnalysisMode,
        profile: ModelInputProfile,
        exportDirectory: String
    ) -> ModelInputExportPlan {
        let provisional = sources.map { source in
            ModelInputExportPlanEntry(
                source: source,
                plannedOutputs: plannedOutputs(
                    for: source,
                    mode: mode,
                    profile: profile,
                    exportDirectory: exportDirectory
                )
            )
        }
        let outputPairs = provisional.flatMap { entry in
            entry.plannedOutputs.map { output in (entry.source, output) }
        }
        let grouped = Dictionary(grouping: outputPairs) { $0.1.path.lowercased() }
        let collidingKeys = Set(grouped.filter { $0.value.count > 1 }.map(\.key))
        let collidingSourcePaths = Set(
            grouped
                .filter { collidingKeys.contains($0.key) }
                .flatMap { $0.value.map(\.0.path) }
        )

        let collisions = grouped
            .filter { collidingKeys.contains($0.key) }
            .map { _, pairs in
                let sources = pairs.map(\.0).sorted { $0.relativePath < $1.relativePath }
                let outputPath = pairs.map(\.1.path).sorted().first ?? "unknown"
                let relativePaths = sources.map(\.relativePath).joined(separator: ", ")
                return ModelInputExportPlanCollision(
                    sources: sources,
                    error: SidecarError(
                        code: .sidecarCollision,
                        stage: .write,
                        message: "Multiple sources resolve to the same model-input export path \(outputPath): \(relativePaths)",
                        recoverable: true
                    )
                )
            }

        return ModelInputExportPlan(
            entries: provisional
                .filter { !collidingSourcePaths.contains($0.source.path) }
                .sorted { $0.source.relativePath < $1.source.relativePath },
            collisions: collisions
        )
    }

    private static func plannedOutputs(
        for source: SourceImage,
        mode: AnalysisMode,
        profile: ModelInputProfile,
        exportDirectory: String
    ) -> [ModelInputExportPlannedOutput] {
        roles(for: mode).map { role in
            let relativePath = relativeOutputPath(for: source, role: role, profile: profile)
            let path = relativeComponents(for: relativePath)
                .reduce(URL(fileURLWithPath: exportDirectory)) { url, component in
                    url.appendingPathComponent(component)
                }
                .standardizedFileURL
                .path
            return ModelInputExportPlannedOutput(role: role, path: path, relativePath: relativePath)
        }
    }

    private static func roles(for mode: AnalysisMode) -> [DerivativeRole] {
        switch mode {
        case .whole:
            return [.wholeImage]
        case .subject:
            return [.subjectIsolated]
        case .both:
            return [.wholeImage, .subjectIsolated]
        }
    }

    private static func relativeOutputPath(
        for source: SourceImage,
        role: DerivativeRole,
        profile: ModelInputProfile
    ) -> String {
        let components = relativeComponents(for: source.relativePath)
        let directoryComponents = Array(components.dropLast())
        let fileName = components.last ?? source.fileName
        let outputName = "\(fileName).aisidecar.\(role.rawValue).\(format(for: role, profile: profile).fileExtension)"
        return (directoryComponents + [outputName]).joined(separator: "/")
    }

    private static func format(for role: DerivativeRole, profile: ModelInputProfile) -> DerivativeFormat {
        switch role {
        case .wholeImage:
            return profile.preferredWholeImageFormat
        case .subjectIsolated:
            return .jpeg
        case .fullResolution:
            return .tiff
        }
    }

    private static func relativeComponents(for relativePath: String) -> [String] {
        relativePath.split(separator: "/").map(String.init)
    }
}

private extension DerivativeFormat {
    var fileExtension: String {
        switch self {
        case .jpeg:
            return "jpg"
        case .tiff:
            return "tiff"
        }
    }
}

private struct ExportUnavailableForegroundMaskProvider: ForegroundMaskProvider {
    func foregroundMasks(in _: CIImage, dimensions _: PixelDimensions) async throws -> ForegroundMaskResult {
        throw SidecarError(
            code: .subjectIsolationFailed,
            stage: .isolate,
            message: "Apple Vision foreground masking requires macOS 15 or newer.",
            recoverable: true
        )
    }
}
