import AISidecarCore
import Foundation
import Observation

/// Shell-independent owner of the Wizard feature models and workflow state.
///
/// RootShellView keeps one instance alive across shell changes. Shells render
/// the state and forward user intents; Core work remains in the feature models.
@MainActor
@Observable
final class WizardFlowModel {
    /// Injectable effect boundary for deterministic routing tests.
    @MainActor
    struct Effects {
        var checkRuntime: (RuntimeGuidanceModel, [String: String]) -> Void
        var registerTerminationFlush: (ReviewModel) -> Void
        var scheduleRescan: (FolderImportModel) -> Void
        var startAnalysis: (AnalysisRunModel, AnalysisOptions, String, Bool, String?, Int) -> Void
        var runNormalization: (NormalizationModel, String, String, QualityGradingConfigurationOverrides) -> Void
        var buildReview: (ReviewModel, String, String, QualityGradingConfigurationOverrides) -> Void
        var planExport:
            (
                ExportModel, NormalizationSessionDocument, String, String?, Bool,
                XMPConflictPolicy, QualityGradingConfigurationOverrides
            ) -> Void
        var sleep: (Duration) async -> Void
        var reportAssertion: (String) -> Void

        static let live = Effects(
            checkRuntime: { model, environment in
                model.loadIfNeeded(environment: environment)
            },
            registerTerminationFlush: { reviewModel in
                TerminationFlush.register(id: "review") { [weak reviewModel] in
                    reviewModel?.autosaveNow()
                }
            },
            scheduleRescan: { importModel in
                Task { await importModel.rescan() }
            },
            startAnalysis: { runModel, options, inputPath, recursive, outputDir, expectedTotal in
                runModel.start(
                    options: options,
                    inputPath: inputPath,
                    recursive: recursive,
                    outputDir: outputDir,
                    expectedTotal: expectedTotal
                )
            },
            runNormalization: { model, jsonRoot, sourceRoot, qualityGrading in
                model.run(
                    jsonRoot: jsonRoot,
                    sourceRoot: sourceRoot,
                    qualityGrading: qualityGrading
                )
            },
            buildReview: { model, jsonRoot, sourceRoot, qualityGrading in
                model.buildSession(
                    jsonRoot: jsonRoot,
                    sourceRoot: sourceRoot,
                    qualityGrading: qualityGrading
                )
            },
            planExport: {
                model, session, sourceRoot, outputDir, recursive, conflictPolicy, qualityGrading in
                model.plan(
                    session: session,
                    sourceRoot: sourceRoot,
                    outputDir: outputDir,
                    recursive: recursive,
                    xmpConflictPolicy: conflictPolicy,
                    qualityGrading: qualityGrading
                )
            },
            sleep: { duration in
                try? await Task.sleep(for: duration)
            },
            reportAssertion: { message in
                assertionFailure(message)
            }
        )
    }

    let importModel: FolderImportModel
    let options: AnalysisOptions
    let runModel: AnalysisRunModel
    let runtimeGuidance: RuntimeGuidanceModel
    let reviewModel: ReviewModel
    let normalizationModel: NormalizationModel
    let exportModel: ExportModel

    var visionTagsModel: VisionTagsModel { runtimeGuidance.visionTagsModel }

    var applySession: NormalizationSessionDocument?
    var applySessionPath: String?
    var showPlanSheet = false
    var selectedAction: WizardAction?
    var step = 1
    var showSettings = false
    var showRerunConfirmation = false
    var showDiscardRestoredReviewConfirmation = false

    @ObservationIgnored private let effects: Effects
    @ObservationIgnored private var activated = false

    init(
        importModel: FolderImportModel = FolderImportModel(),
        options: AnalysisOptions = AnalysisOptions(),
        runModel: AnalysisRunModel = AnalysisRunModel(),
        runtimeGuidance: RuntimeGuidanceModel = RuntimeGuidanceModel(),
        reviewModel: ReviewModel = ReviewModel(),
        normalizationModel: NormalizationModel = NormalizationModel(),
        exportModel: ExportModel = ExportModel(),
        effects: Effects = .live
    ) {
        self.importModel = importModel
        self.options = options
        self.runModel = runModel
        self.runtimeGuidance = runtimeGuidance
        self.reviewModel = reviewModel
        self.normalizationModel = normalizationModel
        self.exportModel = exportModel
        self.effects = effects
    }

    /// Perform the former shell startup work once for this flow instance.
    func activate(environment: [String: String] = ProcessInfo.processInfo.environment) async {
        guard !activated else { return }
        activated = true

        effects.checkRuntime(runtimeGuidance, environment)
        runModel.onRecord = { [weak importModel] record in
            importModel?.apply(record)
        }
        effects.registerTerminationFlush(reviewModel)

        if let path = environment["CUPRIC_IMPORT_PATH"] {
            importModel.chooseSource(URL(fileURLWithPath: path, isDirectory: true))
        }
        if let rawStep = environment["CUPRIC_DEBUG_STEP"],
            let debugStep = Int(rawStep),
            (1...5).contains(debugStep)
        {
            selectedAction = .analyze
            step = debugStep
        }
        if environment["CUPRIC_DEBUG_SETTINGS"] == "1" {
            showSettings = true
        }
        if reviewModel.recoveryAvailable {
            selectedAction = .write
            step = 5
        }
        if environment["CUPRIC_DEBUG_AUTORUN"] == "1" {
            selectedAction = environment["CUPRIC_DEBUG_ACTION"].flatMap(WizardAction.init(rawValue:)) ?? .analyze
            while importModel.scanning || importModel.assets.isEmpty {
                guard !Task.isCancelled else { return }
                await effects.sleep(.milliseconds(200))
            }
            guard !Task.isCancelled else { return }
            step = 3
            await effects.sleep(.seconds(2))
            guard !Task.isCancelled else { return }
            primaryAction()
        }
    }

    func handleRunPhase(_ phase: AnalysisRunModel.Phase) {
        switch phase {
        case .finished(let outcome):
            if outcome.interrupted {
                runModel.reset()
                step = 3
            } else if selectedAction == .normalize {
                if let source = importModel.sourceFolder {
                    effects.runNormalization(
                        normalizationModel,
                        importModel.outputFolder?.path ?? source.path,
                        source.path,
                        effectiveQualityGradingOverrides
                    )
                }
            } else {
                step = 5
                if let source = importModel.sourceFolder {
                    effects.buildReview(
                        reviewModel,
                        importModel.outputFolder?.path ?? source.path,
                        source.path,
                        effectiveQualityGradingOverrides
                    )
                }
            }
            effects.scheduleRescan(importModel)
        case .failed:
            step = 3
        case .idle, .running, .cancelling:
            break
        }
    }

    func handleNormalizationPhase(_ phase: NormalizationModel.Phase) {
        switch phase {
        case .ready where step == 4:
            step = 5
        case .failed where step == 4:
            step = 3
        case .idle, .running, .ready, .failed:
            break
        }
    }

    func handleExportPhase(_ phase: ExportModel.Phase) {
        switch phase {
        case .planReady:
            showPlanSheet = true
        case .written:
            step = 5
            effects.scheduleRescan(importModel)
        case .idle, .planning, .writing, .failed:
            break
        }
    }

    func handleReviewSessionChange() {
        rehydrateImportContextFromReviewSession()
    }

    func handleSourcePathChange(oldPath: String?, newPath: String?) {
        guard newPath != nil, newPath != oldPath else { return }
        options.resetToResolvedDefaults()
        setQualityAssessmentEnabled(options.assessQuality)
        options.modelOverride = nil
    }

    var effectiveQualityGradingOverrides: QualityGradingConfigurationOverrides {
        let controlsEnabled =
            (selectedAction == .write || selectedAction == .normalize)
            && options.assessQuality
        return options.qualityGradingOverrides(controlsEnabled: controlsEnabled)
    }

    var finishedOutcome: RunOutcome? {
        if case .finished(let outcome) = runModel.phase { return outcome }
        return nil
    }

    var backEnabled: Bool {
        WizardNavigation.backTarget(from: step, phase: runModel.phase) != nil
    }

    var primaryEnabled: Bool {
        switch step {
        case 1: importModel.sourceFolder != nil
        case 2: selectedAction != nil
        case 3 where selectedAction == .apply: applySession != nil && exportModel.phase != .planning
        case 3: importModel.sourceFolder != nil && !runModel.isRunning
        case 4: false
        case 5 where step5WriteAvailable: exportModel.phase != .planning && exportModel.phase != .writing
        default: true
        }
    }

    var step5WriteAvailable: Bool {
        guard exportModel.phase != .written else { return false }
        guard importModel.sourceFolder != nil else { return false }
        switch selectedAction {
        case .write: return reviewModel.session != nil
        case .normalize: return normalizationModel.session != nil
        default: return false
        }
    }

    var primaryLabel: String {
        switch step {
        case 3 where selectedAction == .apply: "Apply session"
        case 3: "Start"
        case 4: "Working…"
        case 5 where step5WriteAvailable:
            selectedAction == .normalize ? "Write normalized XMP" : "Write XMP"
        case 5: "Done"
        default: "Continue"
        }
    }

    var footerHint: String {
        switch step {
        case 1:
            return importModel.sourceFolder == nil ? "Choose a folder to continue" : importModel.summary
        case 2:
            return selectedAction.map { "\($0.title) selected" } ?? "Pick an action"
        case 3:
            return "\(selectedAction?.title ?? "") · \(importModel.assets.count) images"
        case 4:
            return "Processing locally"
        default:
            if selectedAction == .normalize {
                return "\(normalizationModel.acceptedTotal) accepted · Done clears the session"
            }
            return "\(reviewModel.approvedCount) approved · Done clears the review"
        }
    }

    var rerunConfirmationTitle: String {
        selectedAction == .normalize ? "Re-run normalization?" : "Re-run the analysis?"
    }

    var rerunConfirmationMessage: String {
        if selectedAction == .normalize {
            return "This discards the current normalization session and Inspector outcomes."
        }
        return "This discards the current results and \(reviewModel.verdicts.count) review decisions."
    }

    /// Until I7 moves grading to the Step 5 write boundary, opting into an
    /// assessment also supplies the Step 3 grading default for this run.
    func setQualityAssessmentEnabled(_ enabled: Bool) {
        options.assessQuality = enabled
        if enabled {
            options.qualityGradingEnabled = true
        }
    }

    func selectApplySessionAction() {
        selectedAction = .apply
        step = 3
    }

    func goBack() {
        if let target = WizardNavigation.backTarget(from: step, phase: runModel.phase) {
            step = target
        }
    }

    func primaryAction() {
        switch step {
        case 1, 2:
            step += 1
        case 3 where selectedAction == .apply:
            startExport()
        case 3:
            if WizardNavigation.needsRerunConfirmation(
                phase: runModel.phase,
                hasReview: reviewModel.session != nil,
                hasNormalizationSession: normalizationModel.session != nil
            ) {
                showRerunConfirmation = true
            } else {
                startRun()
            }
        case 5 where step5WriteAvailable:
            startExport()
        case 5:
            requestFinish()
        default:
            break
        }
    }

    func startRun() {
        guard let source = importModel.sourceFolder else { return }
        effects.startAnalysis(
            runModel,
            options,
            source.path,
            importModel.recursive,
            importModel.outputFolder?.path,
            importModel.assets.count
        )
        step = 4
    }

    /// Route every write through the dry-run plan gate before XMP changes.
    func startExport() {
        guard let source = importModel.sourceFolder else {
            let error = exportReadinessError("No source folder is loaded; choose a folder before writing XMP.")
            reportStartExportError(error)
            effects.reportAssertion(error.message)
            return
        }
        let session: NormalizationSessionDocument? =
            switch selectedAction {
            case .normalize: normalizationModel.session
            case .apply: applySession
            default: reviewModel.reviewedSession
            }
        guard let session else {
            let error = exportReadinessError(missingExportSessionMessage)
            reportStartExportError(error)
            effects.reportAssertion(error.message)
            return
        }
        effects.planExport(
            exportModel,
            session,
            source.path,
            importModel.outputFolder?.path,
            importModel.recursive,
            options.xmpConflictPolicy,
            selectedAction == .apply
                ? exportModel.applyQualityGradingOverrides : effectiveQualityGradingOverrides
        )
    }

    func requestFinish() {
        if WizardNavigation.doneNeedsConfirmation(
            hasSession: reviewModel.session != nil,
            restoredRecoveryDirty: reviewModel.restoredRecoveryDirty,
            exported: exportModel.phase == .written
        ) {
            showDiscardRestoredReviewConfirmation = true
        } else {
            finishCleanly()
        }
    }

    func finishCleanly() {
        reviewModel.completeCleanly()
        normalizationModel.reset()
        exportModel.reset()
        applySession = nil
        applySessionPath = nil
        runModel.reset()
        options.modelOverride = nil
        selectedAction = nil
        step = 1
    }

    func saveRestoredReviewSession(to url: URL) throws {
        try reviewModel.saveSession(to: url)
        reviewModel.clearFileError()
        finishCleanly()
    }

    private var missingExportSessionMessage: String {
        switch selectedAction {
        case .normalize:
            "No normalization session is loaded; nothing to write."
        case .apply:
            "No apply-session document is loaded; nothing to write."
        default:
            "No review session is loaded; nothing to write."
        }
    }

    private func exportReadinessError(_ message: String) -> SidecarError {
        SidecarError(
            code: .validationFailed,
            stage: .write,
            message: message,
            recoverable: true
        )
    }

    private func reportStartExportError(_ error: SidecarError) {
        switch selectedAction {
        case .normalize:
            normalizationModel.reportFileError("Write normalized XMP", error)
        case .apply:
            exportModel.reportValidationFailure(error)
        default:
            reviewModel.reportFileError("Write XMP", error)
        }
    }

    private func rehydrateImportContextFromReviewSession() {
        guard reviewModel.restoredFromRecovery || selectedAction == .write else {
            return
        }
        guard let root = reviewModel.session?.session.sourceRoot,
            FileManager.default.fileExists(atPath: root)
        else {
            return
        }
        if reviewModel.restoredFromRecovery {
            selectedAction = .write
        }
        guard importModel.sourceFolder?.path != root else { return }
        importModel.chooseSource(URL(fileURLWithPath: root, isDirectory: true))
    }
}
