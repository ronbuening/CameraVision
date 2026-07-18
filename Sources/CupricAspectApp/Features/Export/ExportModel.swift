import AISidecarCore
import Foundation
import Observation

/// The unified GUI export surface (M7): dry-run change plan first (FR4-029),
/// then the real write through the frozen-session writer — the same
/// `ApplySessionPipeline` + `XMPExportPipeline` chain the CLI uses, with
/// backups, source-hash checks, post-write validation, and restore-on-failure
/// (FR4-028/035). Used by the write, normalize, and apply flows alike.
@MainActor
@Observable
final class ExportModel {
    struct QualityScalarPresentation: Identifiable, Equatable {
        var field: String
        var plannedValue: String
        var plannedExistingValue: String?
        var action: PlannedScalarWrite.Action
        var resultExistingValue: String?
        var resultResultingValue: String?
        var id: String { field }
    }

    struct QualityTargetPresentation: Equatable {
        var tier: QualityTier?
        var ungradedReason: String?
        var explanations: [String]
        var scalars: [QualityScalarPresentation]
    }

    struct QualityExportSummary: Equatable {
        var gradedTargetCount: Int
        var ungradedTargetCount: Int
        var writtenScalarCount: Int
        var skippedScalarCount: Int

        var isEmpty: Bool {
            gradedTargetCount == 0
                && ungradedTargetCount == 0
                && writtenScalarCount == 0
                && skippedScalarCount == 0
        }
    }

    enum Phase: Equatable {
        case idle
        case planning
        case planReady
        case writing
        case written
        case failed(message: String)
    }

    private(set) var phase: Phase = .idle
    private(set) var changePlan: XMPChangePlanDocument?
    private(set) var exportReport: XMPExportReport?
    private(set) var cleanupRemovedCount: Int?
    private(set) var cleanupWarning: String?
    var cleanupAfterWrite = false
    var applyQualityGradingEnabled = ResolvedQualityGradingConfiguration.builtInDefaults.enabled
    var applyQualityConflictPolicy = ResolvedQualityGradingConfiguration.builtInDefaults.conflictPolicy

    private var pendingSessionPath: String?
    private var pendingSourceRoot: String?
    private var pendingOutputDir: String?
    /// The full resolved configuration the reviewed dry run used, frozen on plan
    /// success and replayed by `confirmWrite()` with only `dryRun` flipped —
    /// config-file edits between plan and confirm cannot change the committed write.
    private(set) var pendingConfiguration: ResolvedApplySessionConfiguration?
    private(set) var pendingQualityGrading = QualityGradingConfigurationOverrides()
    private var pendingCleanupRecursive = false
    private let stateDirectory: URL
    private let environment: [String: String]
    private let defaultConfigPath: String?

    init(
        stateDirectory: URL = ReviewModel.defaultStateDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultConfigPath: String? = nil
    ) {
        self.stateDirectory = stateDirectory
        self.environment = environment
        self.defaultConfigPath = defaultConfigPath
        resetApplyQualityDefaults()
    }

    var plannedTargets: [XMPChangePlan] { changePlan?.targetPlans ?? [] }
    var planFailures: [XMPChangePlanInputFailure] { changePlan?.inputFailures ?? [] }

    /// Targets whose plans failed (e.g. malformed existing XMP — FR4-035a):
    /// they are excluded from the write and shown with their error codes.
    var failedTargets: [XMPChangePlan] {
        plannedTargets.filter { !$0.failures.isEmpty }
    }

    var writableTargets: [XMPChangePlan] {
        plannedTargets.filter(\.failures.isEmpty)
    }

    /// Targets whose dry-run preview shows an existing XMP being merged into
    /// (the default backup-and-merge policy) rather than a new file created.
    var mergeTargets: [XMPChangePlan] {
        writableTargets.filter { $0.preview?.wouldCreate == false }
    }

    /// Existing keywords the merge preserves across all merge targets.
    var preservedKeywordCount: Int {
        mergeTargets.reduce(0) {
            $0 + ($1.preview.map { $0.existingFlatKeywords.count + $0.existingHierarchicalKeywords.count } ?? 0)
        }
    }

    var applyQualityGradingOverrides: QualityGradingConfigurationOverrides {
        QualityGradingConfigurationOverrides(
            enabled: applyQualityGradingEnabled,
            conflictPolicy: applyQualityConflictPolicy
        )
    }

    /// A display-only projection of Core's retained grading decisions. The app never recalculates actions or tiers.
    nonisolated static func qualityPresentation(for plan: XMPChangePlan) -> QualityTargetPresentation? {
        qualityPresentation(plan: plan, writeResult: nil)
    }

    nonisolated static func qualityPresentation(
        for target: XMPExportTargetReport
    ) -> QualityTargetPresentation? {
        qualityPresentation(plan: target.plan, writeResult: target.writeResult)
    }

    /// Counts completed scalar actions from retained target reports rather than progress-log artifacts.
    nonisolated static func qualitySummary(for report: XMPExportReport) -> QualityExportSummary {
        var summary = QualityExportSummary(
            gradedTargetCount: 0,
            ungradedTargetCount: 0,
            writtenScalarCount: 0,
            skippedScalarCount: 0
        )
        for target in report.targetReports {
            guard let presentation = qualityPresentation(for: target) else { continue }
            if presentation.tier != nil {
                summary.gradedTargetCount += 1
            } else if presentation.ungradedReason != nil {
                summary.ungradedTargetCount += 1
            }
            guard target.writeResult != nil else { continue }
            switch target.status {
            case .failed, .interrupted, .dryRun:
                continue
            case .written, .created, .unchanged:
                break
            }
            for scalar in presentation.scalars {
                if scalar.action == .skipExisting {
                    summary.skippedScalarCount += 1
                } else {
                    summary.writtenScalarCount += 1
                }
            }
        }
        return summary
    }

    private nonisolated static func qualityPresentation(
        plan: XMPChangePlan,
        writeResult: XMPWriteResult?
    ) -> QualityTargetPresentation? {
        let scalarSources: [(PlannedScalarWrite?, String?, String?)] = [
            (plan.ratingWrite, writeResult?.existingRating, writeResult?.resultingRating),
            (plan.labelWrite, writeResult?.existingLabel, writeResult?.resultingLabel),
            (plan.urgencyWrite, writeResult?.existingUrgency, writeResult?.resultingUrgency),
            (plan.pickWrite, writeResult?.existingPick, writeResult?.resultingPick),
            (plan.goodWrite, writeResult?.existingGood, writeResult?.resultingGood),
        ]
        let scalars = scalarSources.compactMap { write, resultExisting, resultResulting in
            write.map {
                QualityScalarPresentation(
                    field: $0.field,
                    plannedValue: $0.plannedValue,
                    plannedExistingValue: $0.existingValue,
                    action: $0.action,
                    resultExistingValue: resultExisting,
                    resultResultingValue: resultResulting
                )
            }
        }
        let explanations = plan.qualityExplanation ?? []
        let ungradedReason = plan.ungradedReasonExplanation
        guard plan.qualityTier != nil || ungradedReason != nil || !explanations.isEmpty || !scalars.isEmpty else {
            return nil
        }
        return QualityTargetPresentation(
            tier: plan.qualityTier,
            ungradedReason: ungradedReason,
            explanations: explanations,
            scalars: scalars
        )
    }

    func reportValidationFailure(_ error: SidecarError) {
        phase = .failed(message: error.message)
    }

    nonisolated static func applyConfiguration(
        sourceRoot: String,
        outputDir: String?,
        dryRun: Bool,
        xmpConflictPolicy: XMPConflictPolicy,
        qualityGrading: QualityGradingConfigurationOverrides,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultConfigPath: String? = nil
    ) throws -> ResolvedApplySessionConfiguration {
        try ConfigurationResolver.resolveApplySession(
            cli: ApplySessionConfigurationOverrides(
                outputDir: outputDir,
                dryRun: dryRun,
                sourceRoot: sourceRoot,
                backupSidecars: true,
                xmpConflictPolicy: xmpConflictPolicy,
                qualityGrading: qualityGrading
            ),
            environment: environment,
            defaultConfigPath: defaultConfigPath
        )
    }

    /// FR4-029: dry-run the session and hold the change plan for review.
    func plan(
        session: NormalizationSessionDocument,
        sourceRoot: String,
        outputDir: String?,
        recursive: Bool = false,
        xmpConflictPolicy: XMPConflictPolicy = ResolvedApplySessionConfiguration.builtInDefaults.xmpConflictPolicy,
        qualityGrading: QualityGradingConfigurationOverrides
    ) {
        guard phase != .planning, phase != .writing else { return }
        phase = .planning
        changePlan = nil
        exportReport = nil
        cleanupAfterWrite = false
        cleanupRemovedCount = nil
        cleanupWarning = nil

        let sessionDir = stateDirectory.appendingPathComponent("export-sessions", isDirectory: true)
        let environment = environment
        let defaultConfigPath = defaultConfigPath
        Task {
            do {
                let (plan, sessionPath, configuration) = try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
                    let sessionPath = sessionDir.appendingPathComponent("export-\(UUID().uuidString).json").path
                    try NormalizationSessionWriter().write(session, to: sessionPath)
                    let configuration = try ExportModel.applyConfiguration(
                        sourceRoot: sourceRoot,
                        outputDir: outputDir,
                        dryRun: true,
                        xmpConflictPolicy: xmpConflictPolicy,
                        qualityGrading: qualityGrading,
                        environment: environment,
                        defaultConfigPath: defaultConfigPath
                    )
                    let result = try ApplySessionPipeline(
                        xmpPipeline: XMPExportPipeline(logger: GUILog.shared.makeLogger())
                    ).run(sessionPath: sessionPath, configuration: configuration)
                    return (result.changePlan, sessionPath, configuration)
                }.value
                changePlan = plan
                pendingSessionPath = sessionPath
                pendingSourceRoot = sourceRoot
                pendingOutputDir = outputDir
                pendingConfiguration = configuration
                pendingQualityGrading = qualityGrading
                pendingCleanupRecursive = recursive
                phase = .planReady
            } catch {
                phase = .failed(message: (error as? SidecarError)?.message ?? error.localizedDescription)
            }
        }
    }

    /// Execute the reviewed plan (writes only the plannable targets; the
    /// engine re-reads current sidecars and semantically merges).
    func confirmWrite() {
        guard phase == .planReady,
            let sessionPath = pendingSessionPath,
            let sourceRoot = pendingSourceRoot,
            let frozenConfiguration = pendingConfiguration
        else {
            return
        }
        phase = .writing
        let outputDir = pendingOutputDir
        let cleanupAfterWrite = cleanupAfterWrite
        let cleanupRoot = outputDir ?? sourceRoot
        let cleanupRecursive = pendingCleanupRecursive
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    var configuration = frozenConfiguration
                    configuration.dryRun = false
                    return try ApplySessionPipeline(
                        xmpPipeline: XMPExportPipeline(logger: GUILog.shared.makeLogger())
                    ).run(sessionPath: sessionPath, configuration: configuration)
                }.value
                exportReport = result.exportReport
                phase = .written
                if cleanupAfterWrite,
                    let report = result.exportReport,
                    report.failedCount == 0
                {
                    await runCleanup(rootPath: cleanupRoot, recursive: cleanupRecursive)
                }
            } catch {
                phase = .failed(message: (error as? SidecarError)?.message ?? error.localizedDescription)
            }
        }
    }

    private func runCleanup(rootPath: String, recursive: Bool) async {
        do {
            let report = try await Task.detached(priority: .utility) {
                try ArtifactCleanup().run(rootPath: rootPath, recursive: recursive, dryRun: false)
            }.value
            cleanupRemovedCount = report.removedCount
            if report.failedCount > 0 {
                cleanupWarning =
                    "\(report.failedCount) intermediate file\(report.failedCount == 1 ? "" : "s") could not be removed."
            }
        } catch {
            let message = (error as? SidecarError)?.message ?? error.localizedDescription
            cleanupWarning = "Cleanup failed: \(message)"
        }
    }

    func cancelPlan() {
        guard phase == .planReady else { return }
        phase = .idle
        changePlan = nil
        cleanupAfterWrite = false
        cleanupRemovedCount = nil
        cleanupWarning = nil
        pendingConfiguration = nil
        pendingQualityGrading = QualityGradingConfigurationOverrides()
    }

    func reset() {
        phase = .idle
        changePlan = nil
        exportReport = nil
        cleanupAfterWrite = false
        cleanupRemovedCount = nil
        cleanupWarning = nil
        pendingSessionPath = nil
        pendingConfiguration = nil
        pendingQualityGrading = QualityGradingConfigurationOverrides()
        pendingCleanupRecursive = false
        resetApplyQualityDefaults()
    }

    /// Seeds the apply-flow grading controls from the effective resolver once
    /// per init/`reset()` — deliberately not re-read mid-session, so the
    /// controls always show exactly what the next plan will use even if
    /// config.json changes underneath. A committed write is additionally
    /// pinned by the frozen `pendingConfiguration`.
    private func resetApplyQualityDefaults() {
        guard
            let resolved = try? ConfigurationResolver.resolveApplySession(
                environment: environment,
                defaultConfigPath: defaultConfigPath
            )
        else {
            applyQualityGradingEnabled = ResolvedQualityGradingConfiguration.builtInDefaults.enabled
            applyQualityConflictPolicy = ResolvedQualityGradingConfiguration.builtInDefaults.conflictPolicy
            return
        }
        applyQualityGradingEnabled = resolved.qualityGrading.enabled
        applyQualityConflictPolicy = resolved.qualityGrading.conflictPolicy
    }
}
