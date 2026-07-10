import Foundation

/// Result of applying a frozen Phase 3 normalization session.
public struct ApplySessionPipelineResult: Sendable, Equatable {
    public var session: NormalizationSessionDocument
    public var report: NormalizationReport
    public var changePlan: XMPChangePlanDocument
    public var exportReport: XMPExportReport?
    public var interrupted: Bool

    public init(
        session: NormalizationSessionDocument,
        report: NormalizationReport,
        changePlan: XMPChangePlanDocument,
        exportReport: XMPExportReport?,
        interrupted: Bool = false
    ) {
        self.session = session
        self.report = report
        self.changePlan = changePlan
        self.exportReport = exportReport
        self.interrupted = interrupted
    }
}

/// Applies stored normalization decisions through the shared Phase 2 XMP writer.
public struct ApplySessionPipeline {
    private let fileManager: FileManager
    private let sessionReader: NormalizationSessionReader
    private let reportWriter: NormalizationReportWriter
    private let summaryWriter: NormalizationSummaryWriter
    private let xmpPipeline: XMPExportPipeline
    private let afterSourceResolution: @Sendable () -> Void

    /// Create an apply-session pipeline with injectable collaborators.
    ///
    /// `afterSourceResolution` fires after current source identity and staleness checks,
    /// but before the stored decisions are converted into a current XMP export run.
    public init(
        fileManager: FileManager = .default,
        sessionReader: NormalizationSessionReader? = nil,
        reportWriter: NormalizationReportWriter = NormalizationReportWriter(),
        summaryWriter: NormalizationSummaryWriter = NormalizationSummaryWriter(),
        xmpPipeline: XMPExportPipeline? = nil,
        afterSourceResolution: @escaping @Sendable () -> Void = {}
    ) {
        self.fileManager = fileManager
        self.sessionReader = sessionReader ?? NormalizationSessionReader(fileManager: fileManager)
        self.reportWriter = reportWriter
        self.summaryWriter = summaryWriter
        self.xmpPipeline = xmpPipeline ?? XMPExportPipeline(fileManager: fileManager)
        self.afterSourceResolution = afterSourceResolution
    }

    /// Read a saved normalization session and apply its stored decisions.
    public func run(
        sessionPath: String,
        configuration: ResolvedApplySessionConfiguration,
        timestamp: Date = Date(),
        interruptionMonitor: InterruptionMonitor? = nil
    ) throws -> ApplySessionPipelineResult {
        let absoluteSessionPath = absolutePath(for: sessionPath)
        let session = try sessionReader.read(from: absoluteSessionPath)
        let artifacts = NormalizationArtifactPlanner.planApplySession(
            sessionPath: absoluteSessionPath,
            outputDir: configuration.outputDir,
            writeReportPath: nil,
            timestamp: timestamp
        )

        let sourceResolution = resolveSources(
            in: session,
            sessionPath: absoluteSessionPath,
            configuration: configuration
        )
        afterSourceResolution()
        let planningConfiguration = normalizedPlanningConfiguration(
            session: session,
            applyConfiguration: configuration
        )
        let input = NormalizationResolvedInputBatch(
            workflow: session.session.workflow,
            inputPath: absoluteSessionPath,
            inputBasePath: URL(fileURLWithPath: absoluteSessionPath).deletingLastPathComponent().path,
            scanRoot: session.session.scanRoot,
            sourceAssets: sourceResolution.assets,
            sourceAISidecars: session.sourceAISidecars,
            sameBaseNameGroups: session.sameBaseNameGroups,
            warnings: sourceResolution.allWarnings,
            failures: []
        )
        let normalizedPlans = NormalizedXMPChangePlanner(fileManager: fileManager).plan(
            input: input,
            decisions: session.perAssetDecisions,
            candidateSkips: session.candidateSkips,
            configuration: planningConfiguration
        )
        let preparedWritePlans = annotateWritePlans(
            normalizedPlans.writePlans,
            storedWritePlans: session.xmpWritePlans,
            groups: session.sameBaseNameGroups,
            sourceResolution: sourceResolution
        )
        let preparedChangePlan = XMPChangePlanDocument(
            dryRun: configuration.dryRun,
            targetPlans: preparedWritePlans.map(\.xmpChangePlan),
            inputFailures: []
        )
        let exportResult = try xmpPipeline.runChangePlan(
            preparedChangePlan,
            inputPath: absoluteSessionPath,
            configuration: xmpConfiguration(from: session, applyConfiguration: configuration),
            interruptionMonitor: interruptionMonitor
        )
        let finalWritePlans = mergeExecutedPlans(
            preparedWritePlans,
            executedPlans: exportResult.changePlan.targetPlans
        )
        let report = makeReport(
            session: session,
            artifacts: artifacts,
            configuration: planningConfiguration,
            sourceAssets: sourceResolution.assets,
            writePlans: finalWritePlans,
            exportReport: exportResult.report,
            warnings: sourceResolution.allWarnings,
            timestamp: timestamp,
            sessionPath: absoluteSessionPath
        )

        let progressLog = try NormalizationProgressLog(path: artifacts.progressPath, fileManager: fileManager)
        defer {
            try? progressLog.close()
        }
        try appendProgress(
            to: progressLog,
            report: report,
            exportReport: exportResult.report,
            sourceAssetCount: sourceResolution.assets.count,
            timestamp: timestamp
        )
        try reportWriter.write(report, to: artifacts.reportPath)
        try summaryWriter.write(report, to: artifacts.summaryPath)
        try progressLog.append(
            NormalizationProgressRecord(
                timestamp: timestamp,
                stage: .artifactWrite,
                status: .completed,
                message: "Apply-session artifacts written.",
                sourceAssetCount: sourceResolution.assets.count,
                perAssetDecisionCount: session.perAssetDecisions.count,
                xmpWritePlanCount: finalWritePlans.count
            )
        )
        try progressLog.close()

        return ApplySessionPipelineResult(
            session: session,
            report: report,
            changePlan: exportResult.changePlan,
            exportReport: exportResult.report,
            interrupted: exportResult.interrupted
        )
    }

    private func resolveSources(
        in session: NormalizationSessionDocument,
        sessionPath: String,
        configuration: ResolvedApplySessionConfiguration
    ) -> ApplySessionSourceResolution {
        let selectedAssetIDs = Set(session.sameBaseNameGroups.flatMap(\.selectedAssetIDs))
        var assets: [NormalizationSourceAsset] = []
        var warningsByAssetID: [String: [SidecarError]] = [:]
        var failuresByAssetID: [String: [SidecarError]] = [:]

        for var asset in session.sourceAssets {
            let sourceURL = resolveSourceURL(asset: asset, sessionPath: sessionPath, configuration: configuration)
            asset.sourcePath = sourceURL?.path

            guard configuration.sourceVerification != .skip else {
                asset.sourceIdentityStatus = .skipped
                assets.append(asset)
                continue
            }

            guard let sourceURL else {
                let error = sourceMissingError(asset: asset)
                if selectedAssetIDs.contains(asset.assetID) {
                    failuresByAssetID[asset.assetID, default: []].append(error)
                } else {
                    warningsByAssetID[asset.assetID, default: []].append(error)
                }
                asset.sourceIdentityStatus = .mismatched
                assets.append(asset)
                continue
            }

            do {
                let currentIdentity = try SourceIdentityCalculator.compute(
                    for: sourceURL,
                    policy: asset.sourceIdentity.policy,
                    fileManager: fileManager
                )
                if currentIdentity == asset.sourceIdentity {
                    asset.sourceIdentityStatus = .matched
                } else {
                    let error = sessionStaleError(asset: asset, sourcePath: sourceURL.path)
                    asset.sourceIdentityStatus = .mismatched
                    if configuration.allowStale {
                        warningsByAssetID[asset.assetID, default: []].append(
                            staleOverrideWarning(asset: asset, sourcePath: sourceURL.path)
                        )
                    } else if selectedAssetIDs.contains(asset.assetID) {
                        failuresByAssetID[asset.assetID, default: []].append(error)
                    } else {
                        warningsByAssetID[asset.assetID, default: []].append(error)
                    }
                }
            } catch {
                let sidecarError = sessionStaleError(
                    asset: asset,
                    sourcePath: sourceURL.path,
                    detail: "Unable to compute source identity: \(error.localizedDescription)"
                )
                asset.sourceIdentityStatus = .mismatched
                if configuration.allowStale {
                    warningsByAssetID[asset.assetID, default: []].append(
                        staleOverrideWarning(asset: asset, sourcePath: sourceURL.path)
                    )
                } else if selectedAssetIDs.contains(asset.assetID) {
                    failuresByAssetID[asset.assetID, default: []].append(sidecarError)
                } else {
                    warningsByAssetID[asset.assetID, default: []].append(sidecarError)
                }
            }
            assets.append(asset)
        }

        return ApplySessionSourceResolution(
            assets: assets,
            warningsByAssetID: warningsByAssetID,
            failuresByAssetID: failuresByAssetID
        )
    }

    private func annotateWritePlans(
        _ writePlans: [NormalizedXMPWritePlan],
        storedWritePlans: [NormalizedXMPWritePlan],
        groups: [NormalizationSourceGroup],
        sourceResolution: ApplySessionSourceResolution
    ) -> [NormalizedXMPWritePlan] {
        let groupsByTarget = Dictionary(uniqueKeysWithValues: groups.map { ($0.targetRelativePath, $0) })
        let storedByTarget = Dictionary(uniqueKeysWithValues: storedWritePlans.map {
            ($0.xmpChangePlan.targetRelativePath, $0)
        })
        return writePlans.map { writePlan in
            var updated = writePlan
            var plan = updated.xmpChangePlan
            if let group = groupsByTarget[plan.targetRelativePath] {
                plan.sourceVerificationWarnings += group.memberAssetIDs.flatMap {
                    sourceResolution.warningsByAssetID[$0, default: []]
                }
                let failures = group.selectedAssetIDs.flatMap {
                    sourceResolution.failuresByAssetID[$0, default: []]
                }
                if !failures.isEmpty {
                    plan.failures += failures
                    plan.status = .failed
                }
            }
            if let storedPath = storedByTarget[plan.targetRelativePath]?.xmpChangePlan.targetXMPPath,
               storedPath != plan.targetXMPPath {
                plan.groupWarnings.append(recomputedTargetWarning(from: storedPath, to: plan.targetXMPPath))
            }
            updated.xmpChangePlan = plan
            return updated
        }
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

    private func makeReport(
        session: NormalizationSessionDocument,
        artifacts: NormalizationArtifactPlan,
        configuration: ResolvedNormalizationConfiguration,
        sourceAssets: [NormalizationSourceAsset],
        writePlans: [NormalizedXMPWritePlan],
        exportReport: XMPExportReport?,
        warnings: [SidecarError],
        timestamp: Date,
        sessionPath: String
    ) -> NormalizationReport {
        let targetErrors = exportReport?.targetReports.flatMap(\.errors) ?? []
        let inputErrors = exportReport?.inputFailures.map(\.error) ?? []
        return NormalizationReport(
            createdAt: timestamp,
            sessionPath: sessionPath,
            workflow: session.session.workflow,
            inputPath: sessionPath,
            configuration: configuration,
            vocabulary: session.vocabulary,
            xmpWriter: exportReport?.engine ?? session.xmpWriter,
            artifacts: artifacts,
            inputSummary: NormalizationInputSummary(
                sourceAssetCount: sourceAssets.count,
                sourceAISidecarCount: session.sourceAISidecars.count,
                sameBaseNameGroupCount: session.sameBaseNameGroups.count,
                candidateObservationCount: session.candidateObservations.count,
                candidateSkipCount: session.candidateSkips.count,
                batchCandidateCount: session.batchCandidates.count,
                perAssetDecisionCount: session.perAssetDecisions.count,
                xmpWritePlanCount: writePlans.count,
                warningCount: warnings.count,
                failureCount: targetErrors.count + inputErrors.count
            ),
            decisionSummary: NormalizationDecisionSummary(decisions: session.perAssetDecisions),
            sourceAssets: sourceAssets,
            sameBaseNameGroups: session.sameBaseNameGroups,
            affinity: session.affinity,
            candidateSkips: session.candidateSkips,
            batchCandidates: session.batchCandidates,
            localConsensus: session.localConsensus,
            perAssetDecisions: session.perAssetDecisions,
            xmpWritePlans: writePlans,
            xmpExportReport: exportReport,
            warnings: warnings,
            errors: targetErrors + inputErrors
        )
    }

    private func appendProgress(
        to progressLog: NormalizationProgressLog,
        report: NormalizationReport,
        exportReport: XMPExportReport?,
        sourceAssetCount: Int,
        timestamp: Date
    ) throws {
        try progressLog.append(
            NormalizationProgressRecord(
                timestamp: timestamp,
                stage: .inputResolution,
                status: .completed,
                message: "Apply-session sources resolved.",
                sourceAssetCount: sourceAssetCount
            )
        )
        try progressLog.append(
            NormalizationProgressRecord(
                timestamp: timestamp,
                stage: .xmpPlanning,
                status: report.xmpWritePlans.isEmpty ? .skipped : .completed,
                message: "Apply-session XMP plans rebuilt from stored decisions.",
                xmpWritePlanCount: report.xmpWritePlans.count
            )
        )
        for target in exportReport?.targetReports ?? [] {
            try progressLog.append(
                NormalizationProgressRecord(
                    timestamp: timestamp,
                    stage: .xmpTarget,
                    status: progressStatus(for: target.status),
                    message: "Apply-session XMP target processed.",
                    xmpWritePlanCount: 1,
                    targetXMPPath: target.plan.targetXMPPath,
                    targetRelativePath: target.plan.targetRelativePath,
                    plannedFlatKeywords: target.writeResult?.addedFlatKeywords
                        ?? target.preview?.flatKeywordsToAdd
                        ?? target.plan.flatKeywordsToAdd.map(\.term),
                    plannedHierarchicalKeywords: target.writeResult?.addedHierarchicalKeywords
                        ?? target.preview?.hierarchicalKeywordsToAdd
                        ?? target.plan.hierarchicalKeywordsToAdd.map(\.term),
                    errors: target.errors
                )
            )
        }
        // Phase 2 reports interruption-before-target as an input failure; mirror it
        // into the Phase 3 progress log so apply-session artifacts identify the stop stage.
        for failure in exportReport?.inputFailures ?? [] {
            try progressLog.append(
                NormalizationProgressRecord(
                    timestamp: timestamp,
                    stage: .xmpTarget,
                    status: .failed,
                    message: "Apply-session XMP export did not process all targets.",
                    xmpWritePlanCount: 0,
                    targetRelativePath: failure.relativePath,
                    errors: [failure.error]
                )
            )
        }
    }

    private func normalizedPlanningConfiguration(
        session: NormalizationSessionDocument,
        applyConfiguration: ResolvedApplySessionConfiguration
    ) -> ResolvedNormalizationConfiguration {
        var configuration = session.resolvedConfiguration
        configuration.outputDir = applyConfiguration.outputDir
        configuration.logLevel = applyConfiguration.logLevel
        configuration.logFormat = applyConfiguration.logFormat
        configuration.dryRun = applyConfiguration.dryRun
        configuration.sourceRoot = applyConfiguration.sourceRoot ?? configuration.sourceRoot
        configuration.sourceVerification = applyConfiguration.sourceVerification
        configuration.backupSidecars = applyConfiguration.backupSidecars
        configuration.xmpConflictPolicy = applyConfiguration.xmpConflictPolicy
        configuration.sessionOnly = false
        return configuration
    }

    private func xmpConfiguration(
        from session: NormalizationSessionDocument,
        applyConfiguration: ResolvedApplySessionConfiguration
    ) -> ResolvedXMPExportConfiguration {
        ResolvedXMPExportConfiguration(
            recursive: false,
            outputDir: applyConfiguration.outputDir,
            logLevel: applyConfiguration.logLevel,
            logFormat: applyConfiguration.logFormat,
            dryRun: applyConfiguration.dryRun,
            sourceRoot: applyConfiguration.sourceRoot,
            sourceVerification: applyConfiguration.sourceVerification,
            writeFlatKeywords: session.resolvedConfiguration.writeFlatKeywords,
            writeHierarchicalKeywords: session.resolvedConfiguration.writeHierarchicalKeywords,
            backupSidecars: applyConfiguration.backupSidecars,
            xmpConflictPolicy: applyConfiguration.xmpConflictPolicy,
            minConfidence: session.resolvedConfiguration.minConfidence,
            allowSpecificTags: session.resolvedConfiguration.allowSpecificTags,
            pairScope: session.resolvedConfiguration.pairScope,
            writeAIJSON: false
        )
    }

    private func resolveSourceURL(
        asset: NormalizationSourceAsset,
        sessionPath: String,
        configuration: ResolvedApplySessionConfiguration
    ) -> URL? {
        if let sourceRoot = configuration.sourceRoot {
            let candidate = relativeComponents(for: asset.sourceRelativePath).reduce(absoluteURL(for: sourceRoot)) {
                $0.appendingPathComponent($1)
            }.standardizedFileURL
            if isRegularFile(candidate) {
                return candidate
            }
        }
        if let sourcePath = asset.sourcePath {
            let candidate = absoluteURL(for: sourcePath)
            if isRegularFile(candidate) {
                return candidate
            }
        }
        let sessionSibling = relativeComponents(for: asset.sourceRelativePath)
            .reduce(URL(fileURLWithPath: sessionPath).deletingLastPathComponent()) {
                $0.appendingPathComponent($1)
            }
            .standardizedFileURL
        if isRegularFile(sessionSibling) {
            return sessionSibling
        }
        return nil
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

    private func sourceMissingError(asset: NormalizationSourceAsset) -> SidecarError {
        SidecarError(
            code: .sourceMissing,
            stage: .scan,
            message: "Unable to resolve source image for apply-session asset \(asset.assetID): \(asset.sourceRelativePath)",
            recoverable: true
        )
    }

    private func sessionStaleError(
        asset: NormalizationSourceAsset,
        sourcePath: String,
        detail: String? = nil
    ) -> SidecarError {
        let suffix = detail.map { " \($0)" } ?? ""
        return SidecarError(
            code: .sessionStale,
            stage: .write,
            message: "Source identity changed for apply-session asset \(asset.assetID) at \(sourcePath).\(suffix)",
            recoverable: true
        )
    }

    private func staleOverrideWarning(asset: NormalizationSourceAsset, sourcePath: String) -> SidecarError {
        SidecarError(
            code: .sessionStale,
            stage: .write,
            message: "--allow-stale permitted apply-session write for asset \(asset.assetID) at \(sourcePath).",
            recoverable: true
        )
    }

    private func recomputedTargetWarning(from storedPath: String, to currentPath: String) -> SidecarError {
        SidecarError(
            code: .validationFailed,
            stage: .write,
            message: "Apply-session recomputed XMP target from \(storedPath) to \(currentPath).",
            recoverable: true
        )
    }

    private func absolutePath(for path: String) -> String {
        absoluteURL(for: path).path
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

    private func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private func relativeComponents(for path: String) -> [String] {
        path.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
    }
}

private struct ApplySessionSourceResolution {
    var assets: [NormalizationSourceAsset]
    var warningsByAssetID: [String: [SidecarError]]
    var failuresByAssetID: [String: [SidecarError]]

    var allWarnings: [SidecarError] {
        warningsByAssetID.keys.sorted().flatMap { warningsByAssetID[$0, default: []] }
    }
}
