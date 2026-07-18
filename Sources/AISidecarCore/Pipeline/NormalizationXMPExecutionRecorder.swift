import Foundation

/// Updates Phase 3 normalization artifacts after executing normalized XMP plans.
struct NormalizationXMPExecutionRecorder {
    private let fileManager: FileManager
    private let reportWriter: NormalizationReportWriter
    private let summaryWriter: NormalizationSummaryWriter

    init(
        fileManager: FileManager = .default,
        reportWriter: NormalizationReportWriter? = nil,
        summaryWriter: NormalizationSummaryWriter? = nil
    ) {
        self.fileManager = fileManager
        self.reportWriter = reportWriter ?? NormalizationReportWriter(fileManager: fileManager)
        self.summaryWriter = summaryWriter ?? NormalizationSummaryWriter(fileManager: fileManager)
    }

    /// Merge Phase 2 execution results into the already-written Phase 3 report artifacts.
    func recordExecution(
        normalizeResult: NormalizePipelineResult,
        exportResult: XMPExportPipelineResult,
        progressMessage: String
    ) throws -> NormalizePipelineResult {
        var report = normalizeResult.report
        report.xmpExportReport = exportResult.report
        report.xmpWriter = exportResult.report?.engine ?? report.xmpWriter
        report.xmpWritePlans = mergeExecutedPlans(
            report.xmpWritePlans,
            executedPlans: exportResult.changePlan.targetPlans
        )

        let executionErrors = errors(from: exportResult.report)
        report.errors = mergedErrors(report.errors, executionErrors)
        report.inputSummary.failureCount = report.errors.count

        try reportWriter.write(report, to: report.artifacts.reportPath)
        try summaryWriter.write(report, to: report.artifacts.summaryPath)
        try appendExecutionProgress(report: report, exportReport: exportResult.report, message: progressMessage)

        return NormalizePipelineResult(
            session: normalizeResult.session,
            report: report,
            changePlan: exportResult.changePlan
        )
    }

    private func appendExecutionProgress(
        report: NormalizationReport,
        exportReport: XMPExportReport?,
        message: String
    ) throws {
        guard let exportReport else {
            return
        }
        let progressLog = try NormalizationProgressLog(path: report.artifacts.progressPath, fileManager: fileManager)
        defer {
            try? progressLog.close()
        }
        for target in exportReport.targetReports {
            try progressLog.append(
                NormalizationProgressRecord(
                    timestamp: exportReport.createdAt,
                    stage: .xmpTarget,
                    status: progressStatus(for: target.status),
                    message: message,
                    xmpWritePlanCount: 1,
                    targetXMPPath: target.plan.targetXMPPath,
                    targetRelativePath: target.plan.targetRelativePath,
                    plannedFlatKeywords: target.writeResult?.addedFlatKeywords
                        ?? target.preview?.flatKeywordsToAdd
                        ?? target.plan.flatKeywordsToAdd.map(\.term),
                    plannedHierarchicalKeywords: target.writeResult?.addedHierarchicalKeywords
                        ?? target.preview?.hierarchicalKeywordsToAdd
                        ?? target.plan.hierarchicalKeywordsToAdd.map(\.term),
                    ratingWrite: target.plan.ratingWrite,
                    labelWrite: target.plan.labelWrite,
                    urgencyWrite: target.plan.urgencyWrite,
                    pickWrite: target.plan.pickWrite,
                    goodWrite: target.plan.goodWrite,
                    qualityTier: target.plan.qualityTier,
                    qualityExplanation: target.plan.qualityExplanation,
                    errors: target.errors
                )
            )
        }
        // Phase 2 reports interruption-before-target as an input failure; mirror it
        // into the Phase 3 progress log so normalized writes identify the stop stage.
        for failure in exportReport.inputFailures {
            try progressLog.append(
                NormalizationProgressRecord(
                    timestamp: exportReport.createdAt,
                    stage: .xmpTarget,
                    status: .failed,
                    message: "XMP export did not process all targets.",
                    xmpWritePlanCount: 0,
                    targetRelativePath: failure.relativePath,
                    errors: [failure.error]
                )
            )
        }
        try progressLog.close()
    }

    private func mergeExecutedPlans(
        _ writePlans: [NormalizedXMPWritePlan],
        executedPlans: [XMPChangePlan]
    ) -> [NormalizedXMPWritePlan] {
        writePlans.enumerated().map { index, writePlan in
            var updated = writePlan
            if executedPlans.indices.contains(index) {
                updated.xmpChangePlan = executedPlans[index]
            }
            return updated
        }
    }

    private func errors(from report: XMPExportReport?) -> [SidecarError] {
        guard let report else {
            return []
        }
        return report.targetReports.flatMap(\.errors) + report.inputFailures.map(\.error)
    }

    private func mergedErrors(_ existing: [SidecarError], _ additional: [SidecarError]) -> [SidecarError] {
        var merged = existing
        for error in additional where !merged.contains(error) {
            merged.append(error)
        }
        return merged
    }

    private func progressStatus(for status: XMPExportTargetStatus) -> NormalizationProgressStatus {
        switch status {
        case .dryRun:
            return .planned
        case .created, .written, .unchanged:
            return .completed
        case .failed, .interrupted:
            return .failed
        }
    }
}
