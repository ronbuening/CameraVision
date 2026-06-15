import Foundation

/// Result of a Phase 2 XMP export pipeline invocation.
public struct XMPExportPipelineResult: Sendable, Equatable {
    public var changePlan: XMPChangePlanDocument
    public var report: XMPExportReport?
    public var progressLogPath: String?
    public var reportPath: String?
    public var summaryPath: String?
    public var interrupted: Bool

    public init(
        changePlan: XMPChangePlanDocument,
        report: XMPExportReport?,
        progressLogPath: String?,
        reportPath: String?,
        summaryPath: String?,
        interrupted: Bool
    ) {
        self.changePlan = changePlan
        self.report = report
        self.progressLogPath = progressLogPath
        self.reportPath = reportPath
        self.summaryPath = summaryPath
        self.interrupted = interrupted
    }
}

/// Executes Phase 2 XMP export from resolved raw sidecars.
public struct XMPExportPipeline {
    private let fileManager: FileManager
    private let engine: any MetadataWriteEngine
    private let backupManager: XMPBackupManager
    private let validator: XMPMergeValidator
    private let logger: Logger
    private let now: @Sendable () -> Date
    private let afterBackup: @Sendable () -> Void

    public init(
        fileManager: FileManager = .default,
        engine: any MetadataWriteEngine = OwnedXMPSidecarEngine(),
        backupManager: XMPBackupManager? = nil,
        validator: XMPMergeValidator = XMPMergeValidator(),
        logger: Logger = Logger(),
        now: @escaping @Sendable () -> Date = Date.init,
        afterBackup: @escaping @Sendable () -> Void = {}
    ) {
        self.fileManager = fileManager
        self.engine = engine
        self.backupManager = backupManager ?? XMPBackupManager(fileManager: fileManager, now: now)
        self.validator = validator
        self.logger = logger
        self.now = now
        self.afterBackup = afterBackup
    }

    /// Run the complete `write-xmp --from-json` workflow.
    public func runFromJSON(
        fromJSONPath: String,
        configuration: ResolvedXMPExportConfiguration,
        interruptionMonitor: InterruptionMonitor? = nil
    ) throws -> XMPExportPipelineResult {
        let batch = try RawJSONSidecarInputResolver(fileManager: fileManager).resolve(
            fromJSONPath: fromJSONPath,
            configuration: configuration
        )
        return try runResolvedInputs(
            batch,
            inputPath: absolutePath(for: fromJSONPath),
            configuration: configuration,
            writesBatchArtifacts: isDirectory(path: absolutePath(for: fromJSONPath)),
            interruptionMonitor: interruptionMonitor
        )
    }

    /// Run export from already resolved raw sidecar inputs.
    ///
    /// Analyze-and-write uses this path after Phase 1 has produced successful
    /// raw sidecars, avoiding a second source-resolution policy.
    public func runResolvedInputs(
        _ batch: RawJSONSidecarInputBatch,
        inputPath: String,
        configuration: ResolvedXMPExportConfiguration,
        writesBatchArtifacts: Bool,
        interruptionMonitor: InterruptionMonitor? = nil
    ) throws -> XMPExportPipelineResult {
        let startedAt = now()
        let extractionResults = CandidateExtractor().extract(from: batch.inputs, configuration: configuration)
        var changePlan = XMPChangePlanner().plan(
            inputBatch: batch,
            extractionResults: extractionResults,
            configuration: configuration
        )

        let context = try engine.prepare(configuration: configuration)
        defer {
            try? engine.shutdown()
        }

        if configuration.dryRun {
            changePlan = previewedChangePlan(changePlan)
            return XMPExportPipelineResult(
                changePlan: changePlan,
                report: nil,
                progressLogPath: nil,
                reportPath: nil,
                summaryPath: nil,
                interrupted: false
            )
        }

        let artifacts = writesBatchArtifacts
            ? artifactPaths(inputPath: inputPath, outputDir: configuration.outputDir, startedAt: startedAt)
            : nil
        let progressLog = try artifacts.map { try XMPExportProgressLog(path: $0.progressPath, fileManager: fileManager) }
        defer {
            try? progressLog?.close()
        }

        var targetReports: [XMPExportTargetReport] = []
        var interrupted = false
        for plan in changePlan.targetPlans {
            if interruptionMonitor?.isInterrupted == true {
                interrupted = true
                break
            }

            let targetReport = executeTarget(plan, interruptionMonitor: interruptionMonitor)
            targetReports.append(targetReport)
            try progressLog?.append(progressRecord(for: targetReport))
            try logger.log(logRecord(for: targetReport))

            if targetReport.status == .interrupted {
                interrupted = true
                break
            }
        }

        if interruptionMonitor?.isInterrupted == true {
            interrupted = true
        }

        var inputFailures = changePlan.inputFailures
        if interrupted {
            inputFailures.append(
                XMPChangePlanInputFailure(
                    sidecarPath: inputPath,
                    relativePath: nil,
                    error: SidecarError(
                        code: .interrupted,
                        stage: .write,
                        message: "XMP export interrupted before all target sidecars completed.",
                        recoverable: true
                    )
                )
            )
        }

        let report = XMPExportReport(
            createdAt: now(),
            inputPath: inputPath,
            reportDirectory: artifacts?.directory,
            dryRun: false,
            configuration: configuration,
            engine: context,
            targetReports: targetReports,
            inputFailures: inputFailures
        )

        if let artifacts {
            try XMPExportReportWriter(fileManager: fileManager).write(report, to: artifacts.reportPath)
            try XMPExportSummaryWriter(fileManager: fileManager).write(report, to: artifacts.summaryPath)
        }

        return XMPExportPipelineResult(
            changePlan: changePlan,
            report: report,
            progressLogPath: artifacts?.progressPath,
            reportPath: artifacts?.reportPath,
            summaryPath: artifacts?.summaryPath,
            interrupted: interrupted
        )
    }

    private func previewedChangePlan(_ document: XMPChangePlanDocument) -> XMPChangePlanDocument {
        var plans: [XMPChangePlan] = []
        for var plan in document.targetPlans {
            guard plan.status == .planned, plan.failures.isEmpty else {
                plans.append(plan)
                continue
            }
            if plan.existingPolicy == .fail, fileManager.fileExists(atPath: plan.targetXMPPath) {
                plan.status = .failed
                plan.failures.append(existingSidecarError(path: plan.targetXMPPath))
                plans.append(plan)
                continue
            }
            do {
                let preview = try engine.preview(XMPWriteRequest(plan: plan))
                plan.preview = preview
                if !preview.errors.isEmpty {
                    plan.status = .failed
                    plan.failures.append(contentsOf: preview.errors)
                }
            } catch {
                plan.status = .failed
                plan.failures.append(sidecarWriteError(from: error, targetPath: plan.targetXMPPath))
            }
            plans.append(plan)
        }
        var result = document
        result.targetPlans = plans
        return result
    }

    private func executeTarget(
        _ plan: XMPChangePlan,
        interruptionMonitor: InterruptionMonitor?
    ) -> XMPExportTargetReport {
        let startedAt = now()
        guard plan.status == .planned, plan.failures.isEmpty else {
            return targetReport(
                plan: plan,
                status: .failed,
                errors: plan.failures,
                startedAt: startedAt
            )
        }

        let targetExists = fileManager.fileExists(atPath: plan.targetXMPPath)
        if targetExists, plan.existingPolicy == .fail {
            return targetReport(
                plan: plan,
                status: .failed,
                errors: [existingSidecarError(path: plan.targetXMPPath)],
                startedAt: startedAt
            )
        }

        let preview: XMPWritePreview?
        do {
            preview = try engine.preview(XMPWriteRequest(plan: plan))
            if let preview, !preview.errors.isEmpty {
                return targetReport(
                    plan: plan,
                    status: .failed,
                    preview: preview,
                    errors: preview.errors,
                    startedAt: startedAt
                )
            }
        } catch {
            return targetReport(
                plan: plan,
                status: .failed,
                errors: [sidecarWriteError(from: error, targetPath: plan.targetXMPPath)],
                startedAt: startedAt
            )
        }

        var backup: XMPBackupRecord?
        if targetExists, plan.backupPlan.backupSidecars {
            do {
                backup = try backupManager.backupExistingSidecar(at: plan.targetXMPPath)
                afterBackup()
            } catch {
                return targetReport(
                    plan: plan,
                    status: .failed,
                    preview: preview,
                    errors: [sidecarWriteError(from: error, targetPath: plan.targetXMPPath)],
                    startedAt: startedAt
                )
            }
        }

        if interruptionMonitor?.isInterrupted == true {
            let restored = restoreBackupIfNeeded(backup)
            return targetReport(
                plan: plan,
                status: .interrupted,
                preview: preview,
                backup: restored.backup,
                errors: [interruptedError(targetPath: plan.targetXMPPath)] + restored.errors,
                startedAt: startedAt
            )
        }

        let beforeHashes = sourceHashesBeforeWrite(for: plan)
        do {
            let writeResult = try engine.apply(XMPWriteRequest(plan: plan))
            let postSnapshot = try engine.validateReadable(at: plan.targetXMPPath)
            let validation = validator.validate(
                plan: plan,
                preWriteSnapshot: writeResult.preWriteSnapshot,
                postWriteSnapshot: postSnapshot
            )
            let hashOutcome = sourceHashChecks(afterWriteFor: beforeHashes)
            let validationErrors = validation.errors + hashOutcome.errors
            guard validationErrors.isEmpty else {
                let restored = restoreAfterValidationFailure(writeResult: writeResult, backup: backup)
                return targetReport(
                    plan: plan,
                    status: .failed,
                    preview: preview,
                    writeResult: writeResult,
                    validation: validation,
                    backup: restored.backup ?? backup,
                    sourceHashChecks: hashOutcome.checks,
                    errors: validationErrors + restored.errors,
                    startedAt: startedAt
                )
            }

            return targetReport(
                plan: plan,
                status: writeStatus(for: writeResult),
                preview: preview,
                writeResult: writeResult,
                validation: validation,
                backup: backup,
                sourceHashChecks: hashOutcome.checks,
                errors: writeResult.errors,
                startedAt: startedAt
            )
        } catch {
            let restored = restoreBackupIfNeeded(backup)
            return targetReport(
                plan: plan,
                status: .failed,
                preview: preview,
                backup: restored.backup ?? backup,
                sourceHashChecks: sourceHashChecks(afterWriteFor: beforeHashes).checks,
                errors: [sidecarWriteError(from: error, targetPath: plan.targetXMPPath)] + restored.errors,
                startedAt: startedAt
            )
        }
    }

    private func sourceHashesBeforeWrite(for plan: XMPChangePlan) -> [String: String] {
        var hashes: [String: String] = [:]
        for path in selectedSourcePaths(for: plan) {
            hashes[path] = try? SourceIdentityCalculator.compute(
                for: URL(fileURLWithPath: path),
                policy: .sha256,
                fileManager: fileManager
            ).sha256
        }
        return hashes
    }

    private func sourceHashChecks(afterWriteFor before: [String: String]) -> (checks: [XMPSourceHashCheck], errors: [SidecarError]) {
        var checks: [XMPSourceHashCheck] = []
        var errors: [SidecarError] = []
        for path in before.keys.sorted(by: comparePaths) {
            let beforeHash = before[path]
            do {
                let afterHash = try SourceIdentityCalculator.compute(
                    for: URL(fileURLWithPath: path),
                    policy: .sha256,
                    fileManager: fileManager
                ).sha256
                let unchanged = beforeHash == afterHash
                if !unchanged {
                    errors.append(sourceHashChangedError(path: path))
                }
                checks.append(
                    XMPSourceHashCheck(
                        sourcePath: path,
                        beforeSHA256: beforeHash,
                        afterSHA256: afterHash,
                        unchanged: unchanged
                    )
                )
            } catch {
                let sidecarError = SidecarError(
                    code: .validationFailed,
                    stage: .write,
                    message: "Unable to verify source image hash after XMP export for \(path): \(error.localizedDescription)",
                    recoverable: true
                )
                errors.append(sidecarError)
                checks.append(
                    XMPSourceHashCheck(
                        sourcePath: path,
                        beforeSHA256: beforeHash,
                        afterSHA256: nil,
                        unchanged: false,
                        error: sidecarError
                    )
                )
            }
        }
        return (checks, errors)
    }

    private func selectedSourcePaths(for plan: XMPChangePlan) -> [String] {
        Array(Set(plan.sourceMembers.filter(\.selected).compactMap(\.sourcePath))).sorted(by: comparePaths)
    }

    private func restoreAfterValidationFailure(
        writeResult: XMPWriteResult,
        backup: XMPBackupRecord?
    ) -> (backup: XMPBackupRecord?, errors: [SidecarError]) {
        if let backup {
            return restoreBackupIfNeeded(backup)
        }
        guard writeResult.created else {
            return (nil, [])
        }
        do {
            let targetURL = URL(fileURLWithPath: writeResult.targetXMPPath)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            return (nil, [])
        } catch {
            return (nil, [SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to remove invalid new XMP sidecar \(writeResult.targetXMPPath): \(error.localizedDescription)",
                recoverable: true
            )])
        }
    }

    private func restoreBackupIfNeeded(_ backup: XMPBackupRecord?) -> (backup: XMPBackupRecord?, errors: [SidecarError]) {
        guard let backup else {
            return (nil, [])
        }
        do {
            return (try backupManager.restore(backup), [])
        } catch {
            return (backup, [sidecarWriteError(from: error, targetPath: backup.targetXMPPath)])
        }
    }

    private func targetReport(
        plan: XMPChangePlan,
        status: XMPExportTargetStatus,
        preview: XMPWritePreview? = nil,
        writeResult: XMPWriteResult? = nil,
        validation: XMPMergeValidationResult? = nil,
        backup: XMPBackupRecord? = nil,
        sourceHashChecks: [XMPSourceHashCheck] = [],
        errors: [SidecarError] = [],
        startedAt: Date
    ) -> XMPExportTargetReport {
        XMPExportTargetReport(
            plan: plan,
            status: status,
            preview: preview,
            writeResult: writeResult,
            validation: validation,
            backup: backup,
            sourceHashChecks: sourceHashChecks,
            errors: errors,
            durationMs: durationMs(from: startedAt, to: now())
        )
    }

    private func progressRecord(for report: XMPExportTargetReport) -> XMPExportProgressRecord {
        XMPExportProgressRecord(
            timestamp: now(),
            targetXMPPath: report.plan.targetXMPPath,
            targetRelativePath: report.plan.targetRelativePath,
            status: report.status,
            sourceMembers: report.plan.sourceMembers,
            addedFlatKeywords: report.writeResult?.addedFlatKeywords ?? report.preview?.flatKeywordsToAdd ?? [],
            addedHierarchicalKeywords: report.writeResult?.addedHierarchicalKeywords
                ?? report.preview?.hierarchicalKeywordsToAdd
                ?? [],
            backup: report.backup,
            validation: report.validation,
            errors: report.errors,
            durationMs: report.durationMs
        )
    }

    private func logRecord(for report: XMPExportTargetReport) -> LogRecord {
        let level: LogLevel = report.status == .failed || report.status == .interrupted ? .error : .info
        return LogRecord(
            timestamp: now(),
            level: level,
            event: "write_xmp.\(report.status.rawValue)",
            message: logMessage(for: report),
            sourcePath: report.plan.sourceMembers.first?.sourcePath,
            sidecarPath: report.plan.targetXMPPath,
            status: report.status.rawValue,
            errors: report.errors
        )
    }

    private func logMessage(for report: XMPExportTargetReport) -> String {
        switch report.status {
        case .created:
            return "Created XMP sidecar."
        case .written:
            return "Updated XMP sidecar."
        case .unchanged:
            return "XMP sidecar already contained planned keywords."
        case .failed:
            return report.errors.first?.message ?? "XMP export failed."
        case .dryRun:
            return "Planned XMP sidecar."
        case .interrupted:
            return "XMP export interrupted."
        }
    }

    private func writeStatus(for result: XMPWriteResult) -> XMPExportTargetStatus {
        if result.created {
            return .created
        }
        if result.modified {
            return .written
        }
        return .unchanged
    }

    private func artifactPaths(inputPath: String, outputDir: String?, startedAt: Date) -> ExportArtifactPaths {
        let directory: String
        if let outputDir {
            directory = absolutePath(for: outputDir)
        } else if isDirectory(path: inputPath) {
            directory = inputPath
        } else {
            directory = URL(fileURLWithPath: inputPath).deletingLastPathComponent().standardizedFileURL.path
        }

        let timestamp = timestampString(for: startedAt)
        return ExportArtifactPaths(
            directory: directory,
            progressPath: "\(directory)/xmp-export-progress-\(timestamp).jsonl",
            reportPath: "\(directory)/xmp-export-report-\(timestamp).json",
            summaryPath: "\(directory)/xmp-export-summary-\(timestamp).md"
        )
    }

    private func absolutePath(for path: String) -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expandedPath)
            .standardizedFileURL
            .path
    }

    private func isDirectory(path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func timestampString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func durationMs(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }

    private func existingSidecarError(path: String) -> SidecarError {
        SidecarError(
            code: .sidecarExists,
            stage: .write,
            message: "XMP sidecar already exists: \(path)",
            recoverable: true
        )
    }

    private func interruptedError(targetPath: String) -> SidecarError {
        SidecarError(
            code: .interrupted,
            stage: .write,
            message: "XMP export interrupted before replacing \(targetPath).",
            recoverable: true
        )
    }

    private func sourceHashChangedError(path: String) -> SidecarError {
        SidecarError(
            code: .validationFailed,
            stage: .write,
            message: "Source image hash changed during XMP export: \(path)",
            recoverable: true
        )
    }

    private func sidecarWriteError(from error: Error, targetPath: String) -> SidecarError {
        if let sidecarError = error as? SidecarError {
            return sidecarError
        }
        return SidecarError(
            code: .writeFailed,
            stage: .write,
            message: "Unable to write XMP sidecar \(targetPath): \(error.localizedDescription)",
            recoverable: true
        )
    }
}

private struct ExportArtifactPaths {
    var directory: String
    var progressPath: String
    var reportPath: String
    var summaryPath: String
}

private func comparePaths(_ lhs: String, _ rhs: String) -> Bool {
    let lowerLHS = lhs.lowercased()
    let lowerRHS = rhs.lowercased()
    if lowerLHS == lowerRHS {
        return lhs < rhs
    }
    return lowerLHS < lowerRHS
}
