import Foundation

enum RawSidecarBatchHelpers {
    static func rawInputBatch(
        from analyzeResult: AnalyzeResult,
        failureContext: String,
        fileManager: FileManager
    ) -> RawJSONSidecarInputBatch {
        let reader = RawJSONSidecarReader(fileManager: fileManager)
        var inputs: [ResolvedRawSidecarInput] = []
        var failures: [RawJSONSidecarInputFailure] = []

        for record in analyzeResult.records {
            guard record.status == .written || record.status == .skippedExisting else {
                failures.append(rawInputFailure(from: record, context: failureContext))
                continue
            }
            guard let sidecarPath = record.sidecarPath else {
                failures.append(rawInputFailure(from: record, context: failureContext))
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

        // Sequential quality runs emit one record per pass. Grouping here keeps the
        // adapter path aligned with the disk-scan resolver used by standalone export.
        let grouped = RawJSONSidecarInputResolver(fileManager: fileManager).groupedSidecarInputs(inputs)
        return RawJSONSidecarInputBatch(inputs: grouped, failures: failures)
    }

    static func plannedRawSidecarPaths(
        inputPath: String,
        configuration: ResolvedRunConfiguration,
        fileManager: FileManager,
        preScanRawSidecars: (@Sendable (String, ResolvedRunConfiguration) throws -> Set<String>)?
    ) throws -> Set<String> {
        if let preScanRawSidecars {
            return try preScanRawSidecars(inputPath, configuration)
        }
        let scan = try ImageScanner(fileManager: fileManager).scan(
            inputPath: inputPath,
            recursive: configuration.recursive,
            identityPolicy: configuration.sourceIdentityPolicy
        )
        var planned = SidecarNaming.plan(for: scan.images, outputDir: configuration.outputDir)
            .entries
            .map(\.sidecarPath)
        if configuration.taskProfile == .taggingWithQuality, configuration.qualityScanMode == .sequential {
            // Sequential quality sidecars are equally subject to temporary-sidecar cleanup.
            planned += SidecarNaming.plan(for: scan.images, outputDir: configuration.outputDir, kind: .quality)
                .entries
                .map(\.sidecarPath)
        }
        return Set(planned.filter { fileManager.fileExists(atPath: $0) })
    }

    static func removeNewRawSidecars(
        from analyzeResult: AnalyzeResult,
        preexistingRawSidecars: Set<String>,
        fileManager: FileManager,
        logger: Logger
    ) {
        for record in analyzeResult.records where record.status == .written {
            guard let sidecarPath = record.sidecarPath, !preexistingRawSidecars.contains(sidecarPath) else {
                continue
            }
            do {
                try fileManager.removeItem(atPath: sidecarPath)
            } catch {
                logCleanupWarning(
                    "Unable to remove temporary raw sidecar: \(sidecarPath)",
                    error: error,
                    logger: logger
                )
            }
        }
    }

    static func logCleanupWarning(_ message: String, error: Error, logger: Logger) {
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

    static func analyzeSucceeded(_ result: AnalyzeResult) -> Bool {
        !result.interrupted && result.records.allSatisfy { $0.status != .failed }
    }

    static func exportSucceeded(_ result: XMPExportPipelineResult) -> Bool {
        guard !result.interrupted, let report = result.report else {
            return false
        }
        return report.failedCount == 0 && report.targetReports.allSatisfy { $0.status != .failed }
    }

    private static func rawInputFailure(from record: ProgressRecord, context: String) -> RawJSONSidecarInputFailure {
        let path = record.sidecarPath ?? record.sourcePath ?? "analyze-output"
        return RawJSONSidecarInputFailure(
            sidecarPath: URL(fileURLWithPath: path).standardizedFileURL,
            relativePath: record.relativePath,
            error: record.errors.first
                ?? SidecarError(
                    code: .validationFailed,
                    stage: .write,
                    message: "Analyze did not produce a successful raw sidecar for \(context).",
                    recoverable: true
                )
        )
    }
}
