import AISidecarCore
import Foundation
import XCTest

@testable import CupricAspectApp

/// C14: the shell-independent coordinator preserves the Wizard state machine
/// while keeping every test effect deterministic and offline.
final class WizardFlowModelTests: XCTestCase {
    @MainActor
    private final class EffectRecorder {
        struct AnalysisCall {
            var inputPath: String
            var recursive: Bool
            var outputDir: String?
            var expectedTotal: Int
        }

        struct ExportCall {
            var sessionID: String
            var sourceRoot: String
            var outputDir: String?
            var recursive: Bool
            var conflictPolicy: XMPConflictPolicy
            var qualityGrading: QualityGradingConfigurationOverrides
        }

        struct SleepCall {
            var duration: Duration
            var selectedAction: WizardAction?
            var step: Int?
        }

        var events: [String] = []
        var runtimeEnvironments: [[String: String]] = []
        var registeredReviewModels: [ReviewModel] = []
        var rescannedImportModels: [FolderImportModel] = []
        var analysisCalls: [AnalysisCall] = []
        var normalizationSessionRoots: [(jsonRoot: String, sourceRoot: String)] = []
        var reviewSessionRoots: [(jsonRoot: String, sourceRoot: String)] = []
        var exportCalls: [ExportCall] = []
        var sleepCalls: [SleepCall] = []
        var assertionMessages: [String] = []
    }

    @MainActor
    private final class FlowHolder {
        weak var flow: WizardFlowModel?
    }

    private var root: URL!
    private var defaultsSuites: [String] = []

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wizard-flow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for suite in defaultsSuites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testInitializerKeepsOneSharedIdentityForEveryFeatureModel() {
        let recorder = EffectRecorder()
        let importModel = makeImportModel()
        let options = makeOptions()
        let runModel = AnalysisRunModel()
        let runtimeGuidance = makeRuntimeGuidance()
        let reviewModel = makeReviewModel()
        let normalizationModel = makeNormalizationModel()
        let exportModel = makeExportModel()

        let flow = WizardFlowModel(
            importModel: importModel,
            options: options,
            runModel: runModel,
            runtimeGuidance: runtimeGuidance,
            reviewModel: reviewModel,
            normalizationModel: normalizationModel,
            exportModel: exportModel,
            effects: effects(recording: recorder)
        )

        XCTAssertTrue(flow.importModel === importModel)
        XCTAssertTrue(flow.options === options)
        XCTAssertTrue(flow.runModel === runModel)
        XCTAssertTrue(flow.runtimeGuidance === runtimeGuidance)
        XCTAssertTrue(flow.reviewModel === reviewModel)
        XCTAssertTrue(flow.normalizationModel === normalizationModel)
        XCTAssertTrue(flow.exportModel === exportModel)
    }

    @MainActor
    func testActivationRunsStartupEffectsAndDebugHooksExactlyOnce() async {
        let recorder = EffectRecorder()
        let flow = makeFlow(recorder: recorder)
        let firstEnvironment = [
            "CUPRIC_DEBUG_STEP": "4",
            "CUPRIC_DEBUG_SETTINGS": "1",
        ]

        await flow.activate(environment: firstEnvironment)
        await flow.activate(environment: ["CUPRIC_DEBUG_STEP": "2"])

        XCTAssertEqual(recorder.events, ["runtime", "register"])
        XCTAssertEqual(recorder.runtimeEnvironments, [firstEnvironment])
        XCTAssertEqual(recorder.registeredReviewModels.count, 1)
        XCTAssertTrue(recorder.registeredReviewModels[0] === flow.reviewModel)
        XCTAssertNotNil(flow.runModel.onRecord)
        XCTAssertEqual(flow.selectedAction, .analyze)
        XCTAssertEqual(flow.step, 4)
        XCTAssertTrue(flow.showSettings)
    }

    @MainActor
    func testActivationAppliesImportRecoveryAndAutorunPrecedenceWithoutPollingForever() async throws {
        let source = root.appendingPathComponent("autorun-source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let image = source.appendingPathComponent("A.JPG")
        let recoveryDirectory = root.appendingPathComponent("autorun-recovery", isDirectory: true)
        let recoveryWriter = makeReviewModel(stateDirectory: recoveryDirectory)
        recoveryWriter.adopt(session: makeSession(id: "recovery", sourceRoot: source.path))
        recoveryWriter.autosaveNow()
        let recoveryModel = makeReviewModel(stateDirectory: recoveryDirectory)
        XCTAssertTrue(recoveryModel.recoveryAvailable)

        let importModel = makeImportModel()
        importModel.inventoryProvider = { inputPath, recursive in
            ScanInventory(
                inputPath: inputPath,
                scanRoot: inputPath,
                recursive: recursive,
                entries: [
                    ScanInventoryEntry(
                        path: image.path,
                        relativePath: "A.JPG",
                        fileName: "A.JPG",
                        fileExtension: "jpg",
                        fileSize: 10,
                        modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        detectedType: .jpg
                    )
                ],
                errors: []
            )
        }
        let recorder = EffectRecorder()
        let holder = FlowHolder()
        let flow = WizardFlowModel(
            importModel: importModel,
            options: makeOptions(),
            runModel: AnalysisRunModel(),
            runtimeGuidance: makeRuntimeGuidance(),
            reviewModel: recoveryModel,
            normalizationModel: makeNormalizationModel(),
            exportModel: makeExportModel(),
            effects: effects(recording: recorder, observing: holder, yieldsDuringSleep: true)
        )
        holder.flow = flow
        let environment = [
            "CUPRIC_IMPORT_PATH": source.path,
            "CUPRIC_DEBUG_AUTORUN": "1",
            "CUPRIC_DEBUG_ACTION": WizardAction.normalize.rawValue,
        ]

        await flow.activate(environment: environment)

        let pollingSleeps = recorder.sleepCalls.filter { $0.duration == .milliseconds(200) }
        XCTAssertFalse(pollingSleeps.isEmpty, "the import must be awaited before autorun starts")
        XCTAssertTrue(
            pollingSleeps.allSatisfy { $0.selectedAction == .normalize && $0.step == 5 },
            "recovery first selects Step 5, then autorun overrides only the action while import is pending"
        )
        let preflightPause = try XCTUnwrap(recorder.sleepCalls.last { $0.duration == .seconds(2) })
        XCTAssertEqual(preflightPause.selectedAction, .normalize)
        XCTAssertEqual(preflightPause.step, 3)
        XCTAssertEqual(recorder.events.prefix(2), ["runtime", "register"])
        XCTAssertEqual(recorder.events.last, "analysis", "primaryAction runs after the autorun waits")
        XCTAssertEqual(recorder.analysisCalls.count, 1)
        XCTAssertEqual(recorder.analysisCalls[0].inputPath, source.path)
        XCTAssertEqual(recorder.analysisCalls[0].expectedTotal, 1)
        XCTAssertEqual(flow.importModel.sourceFolder?.path, source.path)
        XCTAssertEqual(flow.importModel.assets.map(\.fileName), ["A.JPG"])
        XCTAssertEqual(flow.selectedAction, .normalize)
        XCTAssertEqual(flow.step, 4)
    }

    @MainActor
    func testEffectiveQualityGradingMatchesOptionsAvailabilityForEveryActionAndAssessmentState() {
        let flow = makeFlow(recorder: EffectRecorder())
        flow.options.qualityGradingEnabled = true
        flow.options.qualityWriteRating = true
        flow.options.qualityConflictPolicy = .overwrite

        for action in WizardAction.allCases {
            for assessQuality in [false, true] {
                flow.selectedAction = action
                flow.options.assessQuality = assessQuality
                let availability = Step3OptionsView.qualityGradingAvailability(
                    action: action,
                    assessQuality: assessQuality
                )
                let expectedVisible = action == .write || action == .normalize
                let expectedControlsEnabled = expectedVisible && assessQuality
                let overrides = flow.effectiveQualityGradingOverrides
                let context = "action=\(action.rawValue), assessQuality=\(assessQuality)"

                XCTAssertEqual(availability.isVisible, expectedVisible, context)
                XCTAssertEqual(availability.controlsEnabled, expectedControlsEnabled, context)
                XCTAssertEqual(overrides.enabled, expectedControlsEnabled, context)
                XCTAssertEqual(overrides.writeRating, expectedControlsEnabled ? true : nil, context)
                XCTAssertEqual(overrides.conflictPolicy, expectedControlsEnabled ? .overwrite : nil, context)
            }
        }
    }

    @MainActor
    func testRunPhaseRoutesInterruptedFailedAnalyzeAndNormalizeOutcomes() {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)

        do {
            let recorder = EffectRecorder()
            let flow = makeFlow(recorder: recorder)
            flow.step = 4
            flow.runModel.applyProgressForTesting(done: 3, total: 3)

            flow.handleRunPhase(.finished(RunOutcome(interrupted: true)))

            XCTAssertEqual(flow.step, 3)
            XCTAssertEqual(flow.runModel.done, 0)
            XCTAssertEqual(flow.runModel.total, 0)
            XCTAssertEqual(recorder.rescannedImportModels.count, 1)
            XCTAssertTrue(recorder.reviewSessionRoots.isEmpty)
            XCTAssertTrue(recorder.normalizationSessionRoots.isEmpty)
        }

        do {
            let recorder = EffectRecorder()
            let flow = makeFlow(recorder: recorder)
            flow.step = 4

            flow.handleRunPhase(.failed(message: "failed"))

            XCTAssertEqual(flow.step, 3)
            XCTAssertTrue(recorder.rescannedImportModels.isEmpty)
        }

        do {
            let recorder = EffectRecorder()
            let flow = makeFlow(recorder: recorder)
            flow.importModel.sourceFolder = source
            flow.importModel.outputFolder = output
            flow.selectedAction = .analyze
            flow.step = 4

            flow.handleRunPhase(.finished(RunOutcome()))

            XCTAssertEqual(flow.step, 5)
            XCTAssertEqual(recorder.reviewSessionRoots.count, 1)
            XCTAssertEqual(recorder.reviewSessionRoots[0].jsonRoot, output.path)
            XCTAssertEqual(recorder.reviewSessionRoots[0].sourceRoot, source.path)
            XCTAssertEqual(recorder.rescannedImportModels.count, 1)
            XCTAssertTrue(recorder.normalizationSessionRoots.isEmpty)
        }

        do {
            let recorder = EffectRecorder()
            let flow = makeFlow(recorder: recorder)
            flow.importModel.sourceFolder = source
            flow.importModel.outputFolder = output
            flow.selectedAction = .normalize
            flow.step = 4

            flow.handleRunPhase(.finished(RunOutcome()))

            XCTAssertEqual(flow.step, 4, "normalization owns the next transition")
            XCTAssertEqual(recorder.normalizationSessionRoots.count, 1)
            XCTAssertEqual(recorder.normalizationSessionRoots[0].jsonRoot, output.path)
            XCTAssertEqual(recorder.normalizationSessionRoots[0].sourceRoot, source.path)
            XCTAssertEqual(recorder.rescannedImportModels.count, 1)
            XCTAssertTrue(recorder.reviewSessionRoots.isEmpty)
        }
    }

    @MainActor
    func testNormalizationPhaseRoutesOnlyFromWorkingStep() {
        let flow = makeFlow(recorder: EffectRecorder())

        flow.step = 4
        flow.handleNormalizationPhase(.ready)
        XCTAssertEqual(flow.step, 5)

        flow.step = 4
        flow.handleNormalizationPhase(.failed(message: "failed"))
        XCTAssertEqual(flow.step, 3)

        flow.step = 2
        flow.handleNormalizationPhase(.ready)
        XCTAssertEqual(flow.step, 2)

        flow.step = 5
        flow.handleNormalizationPhase(.failed(message: "stale"))
        XCTAssertEqual(flow.step, 5)
    }

    @MainActor
    func testExportPhaseOpensPlanAndWrittenReturnsToReviewAndRescans() {
        let recorder = EffectRecorder()
        let flow = makeFlow(recorder: recorder)
        flow.step = 3

        flow.handleExportPhase(.planReady)
        XCTAssertTrue(flow.showPlanSheet)
        XCTAssertEqual(flow.step, 3)

        flow.handleExportPhase(.written)
        XCTAssertEqual(flow.step, 5)
        XCTAssertEqual(recorder.rescannedImportModels.count, 1)

        flow.handleExportPhase(.failed(message: "failed"))
        XCTAssertEqual(flow.step, 5)
        XCTAssertEqual(recorder.rescannedImportModels.count, 1)
    }

    @MainActor
    func testBackAndPrimaryIntentsPreserveNavigationAndRerunGuards() {
        let recorder = EffectRecorder()
        let flow = makeFlow(recorder: recorder)

        flow.step = 5
        flow.goBack()
        XCTAssertEqual(flow.step, 3)

        flow.step = 4
        flow.goBack()
        XCTAssertEqual(flow.step, 4)

        flow.step = 1
        flow.primaryAction()
        XCTAssertEqual(flow.step, 2)
        flow.primaryAction()
        XCTAssertEqual(flow.step, 3)

        flow.importModel.sourceFolder = root
        flow.primaryAction()
        XCTAssertEqual(flow.step, 4)
        XCTAssertEqual(recorder.analysisCalls.count, 1)

        flow.step = 4
        flow.primaryAction()
        XCTAssertEqual(recorder.analysisCalls.count, 1)

        let session = makeSession(id: "prior-review", sourceRoot: root.path)
        flow.reviewModel.adopt(session: session)
        flow.step = 3
        flow.primaryAction()

        XCTAssertTrue(flow.showRerunConfirmation)
        XCTAssertEqual(flow.step, 3)
        XCTAssertEqual(recorder.analysisCalls.count, 1)
    }

    @MainActor
    func testPrimaryIntentRoutesApplyWriteAndDoneBranches() {
        let source = root.appendingPathComponent("source", isDirectory: true)

        do {
            let recorder = EffectRecorder()
            let flow = makeFlow(recorder: recorder)
            flow.importModel.sourceFolder = source
            flow.applySession = makeSession(id: "apply", sourceRoot: source.path)

            flow.selectApplySessionAction()
            flow.primaryAction()

            XCTAssertEqual(flow.selectedAction, .apply)
            XCTAssertEqual(flow.step, 3)
            XCTAssertEqual(recorder.exportCalls.map(\.sessionID), ["apply"])
        }

        do {
            let recorder = EffectRecorder()
            let flow = makeFlow(recorder: recorder)
            flow.importModel.sourceFolder = source
            flow.reviewModel.adopt(session: makeSession(id: "write", sourceRoot: source.path))
            flow.selectedAction = .write
            flow.step = 5

            flow.primaryAction()

            XCTAssertEqual(flow.step, 5)
            XCTAssertEqual(recorder.exportCalls.map(\.sessionID), ["write"])
        }

        do {
            let flow = makeFlow(recorder: EffectRecorder())
            flow.selectedAction = .analyze
            flow.step = 5

            flow.primaryAction()

            XCTAssertEqual(flow.step, 1)
            XCTAssertNil(flow.selectedAction)
        }
    }

    @MainActor
    func testStartRunForwardsImportContextAndMovesToWorking() async {
        let recorder = EffectRecorder()
        let flow = makeFlow(recorder: recorder)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        let image = source.appendingPathComponent("A.JPG")
        flow.importModel.sourceFolder = source
        flow.importModel.outputFolder = output
        flow.importModel.recursive = false
        flow.importModel.inventoryProvider = { inputPath, recursive in
            ScanInventory(
                inputPath: inputPath,
                scanRoot: inputPath,
                recursive: recursive,
                entries: [
                    ScanInventoryEntry(
                        path: image.path,
                        relativePath: "A.JPG",
                        fileName: "A.JPG",
                        fileExtension: "jpg",
                        fileSize: 10,
                        modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        detectedType: .jpg
                    )
                ],
                errors: []
            )
        }
        await flow.importModel.rescan()

        flow.startRun()

        XCTAssertEqual(flow.step, 4)
        XCTAssertEqual(recorder.analysisCalls.count, 1)
        XCTAssertEqual(recorder.analysisCalls[0].inputPath, source.path)
        XCTAssertFalse(recorder.analysisCalls[0].recursive)
        XCTAssertEqual(recorder.analysisCalls[0].outputDir, output.path)
        XCTAssertEqual(recorder.analysisCalls[0].expectedTotal, 1)
    }

    @MainActor
    func testStartExportSelectsActionSessionAndForwardsConfiguration() {
        let recorder = EffectRecorder()
        let flow = makeFlow(recorder: recorder)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        flow.importModel.sourceFolder = source
        flow.importModel.outputFolder = output
        flow.importModel.recursive = false
        flow.options.xmpConflictPolicy = .fail
        flow.options.assessQuality = true
        flow.options.qualityGradingEnabled = true
        flow.options.qualityWriteRating = true
        flow.options.qualityConflictPolicy = .overwrite

        flow.reviewModel.adopt(session: makeSession(id: "review", sourceRoot: source.path))
        flow.normalizationModel.adopt(session: makeSession(id: "normalize", sourceRoot: source.path))
        flow.applySession = makeSession(id: "apply", sourceRoot: source.path)

        flow.selectedAction = .write
        flow.startExport()
        flow.selectedAction = .normalize
        flow.startExport()
        flow.selectedAction = .apply
        flow.startExport()

        XCTAssertEqual(recorder.exportCalls.map(\.sessionID), ["review", "normalize", "apply"])
        XCTAssertTrue(recorder.exportCalls.allSatisfy { $0.sourceRoot == source.path })
        XCTAssertTrue(recorder.exportCalls.allSatisfy { $0.outputDir == output.path })
        XCTAssertTrue(recorder.exportCalls.allSatisfy { !$0.recursive })
        XCTAssertTrue(recorder.exportCalls.allSatisfy { $0.conflictPolicy == .fail })
        XCTAssertEqual(recorder.exportCalls[0].qualityGrading.enabled, true)
        XCTAssertEqual(recorder.exportCalls[0].qualityGrading.writeRating, true)
        XCTAssertEqual(recorder.exportCalls[0].qualityGrading.conflictPolicy, .overwrite)
        XCTAssertEqual(
            recorder.exportCalls[2].qualityGrading,
            flow.exportModel.applyQualityGradingOverrides,
            "apply owns its distinct grading controls"
        )
    }

    @MainActor
    func testStartExportRoutesExactReadinessFailuresByAction() {
        do {
            let recorder = EffectRecorder()
            let flow = makeFlow(recorder: recorder)
            flow.selectedAction = .normalize

            flow.startExport()

            XCTAssertEqual(
                flow.normalizationModel.fileError,
                "Write normalized XMP failed: No source folder is loaded; choose a folder before writing XMP."
            )
            XCTAssertEqual(
                recorder.assertionMessages,
                ["No source folder is loaded; choose a folder before writing XMP."]
            )
            XCTAssertTrue(recorder.exportCalls.isEmpty)
        }

        do {
            let recorder = EffectRecorder()
            let flow = makeFlow(recorder: recorder)
            flow.importModel.sourceFolder = root
            flow.selectedAction = .apply

            flow.startExport()

            XCTAssertEqual(
                flow.exportModel.phase, .failed(message: "No apply-session document is loaded; nothing to write."))
            XCTAssertEqual(recorder.assertionMessages, ["No apply-session document is loaded; nothing to write."])
            XCTAssertTrue(recorder.exportCalls.isEmpty)
        }

        do {
            let recorder = EffectRecorder()
            let flow = makeFlow(recorder: recorder)
            flow.importModel.sourceFolder = root
            flow.selectedAction = .write

            flow.startExport()

            XCTAssertEqual(
                flow.reviewModel.fileError,
                "Write XMP failed: No review session is loaded; nothing to write."
            )
            XCTAssertEqual(recorder.assertionMessages, ["No review session is loaded; nothing to write."])
            XCTAssertTrue(recorder.exportCalls.isEmpty)
        }
    }

    @MainActor
    func testReviewRehydrationHonorsActionRecoveryAndSourceGuards() throws {
        let source = root.appendingPathComponent("rehydrated", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        do {
            let flow = makeFlow(recorder: EffectRecorder())
            flow.reviewModel.adopt(session: makeSession(id: "write", sourceRoot: source.path))
            flow.selectedAction = .analyze

            flow.handleReviewSessionChange()
            XCTAssertNil(flow.importModel.sourceFolder)

            flow.selectedAction = .write
            flow.handleReviewSessionChange()
            XCTAssertEqual(flow.importModel.sourceFolder?.path, source.path)
        }

        do {
            let stateDirectory = root.appendingPathComponent("recovery-state", isDirectory: true)
            let writer = makeReviewModel(stateDirectory: stateDirectory)
            writer.adopt(session: makeSession(id: "recovery", sourceRoot: source.path))
            writer.autosaveNow()

            let restored = makeReviewModel(stateDirectory: stateDirectory)
            try restored.restoreFromRecovery()
            let flow = makeFlow(recorder: EffectRecorder(), reviewModel: restored)
            flow.selectedAction = .analyze

            flow.handleReviewSessionChange()

            XCTAssertEqual(flow.selectedAction, .write)
            XCTAssertEqual(flow.importModel.sourceFolder?.path, source.path)
        }

        do {
            let flow = makeFlow(recorder: EffectRecorder())
            let missing = root.appendingPathComponent("missing").path
            flow.reviewModel.adopt(session: makeSession(id: "missing", sourceRoot: missing))
            flow.selectedAction = .write

            flow.handleReviewSessionChange()

            XCTAssertNil(flow.importModel.sourceFolder)
        }
    }

    @MainActor
    func testSourceChangeReseedsOptionsOnlyForANewNonNilPath() throws {
        let config = root.appendingPathComponent("config.json")
        try Data(#"{"existing":"fail","model":"configured:model"}"#.utf8).write(to: config)
        let options = AnalysisOptions(environment: [:], defaultConfigPath: config.path)
        options.loadResolvedDefaults()
        options.existing = .overwrite
        options.modelOverride = "one-run:model"
        let flow = makeFlow(recorder: EffectRecorder(), options: options)

        flow.handleSourcePathChange(oldPath: nil, newPath: "/photos")
        XCTAssertEqual(flow.options.existing, .fail)
        XCTAssertNil(flow.options.modelOverride)

        flow.options.existing = .overwrite
        flow.options.modelOverride = "keep:model"
        flow.handleSourcePathChange(oldPath: "/photos", newPath: "/photos")
        XCTAssertEqual(flow.options.existing, .overwrite)
        XCTAssertEqual(flow.options.modelOverride, "keep:model")

        flow.handleSourcePathChange(oldPath: "/photos", newPath: nil)
        XCTAssertEqual(flow.options.existing, .overwrite)
        XCTAssertEqual(flow.options.modelOverride, "keep:model")
    }

    @MainActor
    func testRequestFinishGuardsDirtyRecoveryAndCleanFinishPreservesRunInputs() async throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        let image = source.appendingPathComponent("A.JPG")
        let stateDirectory = root.appendingPathComponent("finish-state", isDirectory: true)
        let writer = makeReviewModel(stateDirectory: stateDirectory)
        writer.adopt(session: makeSession(id: "finish", sourceRoot: source.path))
        writer.autosaveNow()
        let restored = makeReviewModel(stateDirectory: stateDirectory)
        try restored.restoreFromRecovery()

        let flow = makeFlow(recorder: EffectRecorder(), reviewModel: restored)
        flow.importModel.sourceFolder = source
        flow.importModel.outputFolder = output
        flow.importModel.recursive = false
        flow.importModel.inventoryProvider = { inputPath, recursive in
            ScanInventory(
                inputPath: inputPath,
                scanRoot: inputPath,
                recursive: recursive,
                entries: [
                    ScanInventoryEntry(
                        path: image.path,
                        relativePath: "A.JPG",
                        fileName: "A.JPG",
                        fileExtension: "jpg",
                        fileSize: 10,
                        modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        detectedType: .jpg
                    )
                ],
                errors: []
            )
        }
        await flow.importModel.rescan()
        flow.options.existing = .overwrite
        flow.options.assessQuality = true
        flow.options.modelOverride = "one-run:model"
        flow.normalizationModel.subject = "Leopard"
        flow.normalizationModel.adopt(session: makeSession(id: "normalization", sourceRoot: source.path))
        flow.exportModel.reportValidationFailure(
            SidecarError(
                code: .validationFailed,
                stage: .write,
                message: "old failure",
                recoverable: true
            )
        )
        flow.applySession = makeSession(id: "apply", sourceRoot: source.path)
        flow.applySessionPath = "/sessions/apply.json"
        flow.runModel.applyProgressForTesting(done: 2, total: 3)
        flow.selectedAction = .write
        flow.step = 5

        flow.requestFinish()

        XCTAssertTrue(flow.showDiscardRestoredReviewConfirmation)
        XCTAssertEqual(flow.step, 5)
        XCTAssertNotNil(flow.reviewModel.session)

        flow.finishCleanly()

        XCTAssertEqual(flow.step, 1)
        XCTAssertNil(flow.selectedAction)
        XCTAssertNil(flow.applySession)
        XCTAssertNil(flow.applySessionPath)
        XCTAssertNil(flow.reviewModel.session)
        XCTAssertNil(flow.normalizationModel.session)
        XCTAssertEqual(flow.normalizationModel.phase, .idle)
        XCTAssertEqual(flow.exportModel.phase, .idle)
        XCTAssertEqual(flow.runModel.phase, .idle)
        XCTAssertEqual(flow.runModel.done, 0)
        XCTAssertNil(flow.options.modelOverride)

        XCTAssertEqual(flow.importModel.sourceFolder?.path, source.path)
        XCTAssertEqual(flow.importModel.outputFolder?.path, output.path)
        XCTAssertFalse(flow.importModel.recursive)
        XCTAssertEqual(flow.importModel.assets.count, 1)
        XCTAssertEqual(flow.options.existing, .overwrite)
        XCTAssertTrue(flow.options.assessQuality)
        XCTAssertEqual(flow.normalizationModel.subject, "Leopard")
    }

    @MainActor
    private func makeFlow(
        recorder: EffectRecorder,
        options: AnalysisOptions? = nil,
        reviewModel: ReviewModel? = nil
    ) -> WizardFlowModel {
        WizardFlowModel(
            importModel: makeImportModel(),
            options: options ?? makeOptions(),
            runModel: AnalysisRunModel(),
            runtimeGuidance: makeRuntimeGuidance(),
            reviewModel: reviewModel ?? makeReviewModel(),
            normalizationModel: makeNormalizationModel(),
            exportModel: makeExportModel(),
            effects: effects(recording: recorder)
        )
    }

    @MainActor
    private func makeImportModel() -> FolderImportModel {
        let suite = "WizardFlowModelTests.\(UUID().uuidString)"
        defaultsSuites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = FolderImportModel(defaults: defaults)
        model.inventoryProvider = { inputPath, recursive in
            ScanInventory(
                inputPath: inputPath,
                scanRoot: inputPath,
                recursive: recursive,
                entries: [],
                errors: []
            )
        }
        return model
    }

    @MainActor
    private func makeOptions() -> AnalysisOptions {
        AnalysisOptions(
            environment: [:],
            defaultConfigPath: root.appendingPathComponent("missing-config.json").path
        )
    }

    @MainActor
    private func makeRuntimeGuidance() -> RuntimeGuidanceModel {
        RuntimeGuidanceModel(
            configPath: root.appendingPathComponent("missing-config.json").path,
            listVisionTags: { _ in
                XCTFail("the injected startup effect must keep this offline")
                return []
            }
        )
    }

    @MainActor
    private func makeReviewModel(stateDirectory: URL? = nil) -> ReviewModel {
        ReviewModel(
            stateDirectory: stateDirectory
                ?? root.appendingPathComponent("review-\(UUID().uuidString)", isDirectory: true),
            environment: [:],
            defaultConfigPath: root.appendingPathComponent("missing-config.json").path,
            loadReviewQuality: { _ in ReviewQualityLoadResult(presentationByAssetID: [:], diagnostics: []) }
        )
    }

    @MainActor
    private func makeNormalizationModel() -> NormalizationModel {
        NormalizationModel(
            stateDirectory: root.appendingPathComponent("normalize-\(UUID().uuidString)", isDirectory: true),
            environment: [:],
            defaultConfigPath: root.appendingPathComponent("missing-config.json").path
        )
    }

    @MainActor
    private func makeExportModel() -> ExportModel {
        ExportModel(
            stateDirectory: root.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true),
            environment: [:],
            defaultConfigPath: root.appendingPathComponent("missing-config.json").path
        )
    }

    @MainActor
    private func effects(
        recording recorder: EffectRecorder,
        observing holder: FlowHolder? = nil,
        yieldsDuringSleep: Bool = false
    ) -> WizardFlowModel.Effects {
        WizardFlowModel.Effects(
            checkRuntime: { _, environment in
                recorder.events.append("runtime")
                recorder.runtimeEnvironments.append(environment)
            },
            registerTerminationFlush: { reviewModel in
                recorder.events.append("register")
                recorder.registeredReviewModels.append(reviewModel)
            },
            scheduleRescan: { importModel in
                recorder.events.append("rescan")
                recorder.rescannedImportModels.append(importModel)
            },
            startAnalysis: { _, _, inputPath, recursive, outputDir, expectedTotal in
                recorder.events.append("analysis")
                recorder.analysisCalls.append(
                    EffectRecorder.AnalysisCall(
                        inputPath: inputPath,
                        recursive: recursive,
                        outputDir: outputDir,
                        expectedTotal: expectedTotal
                    )
                )
            },
            runNormalization: { _, jsonRoot, sourceRoot, _ in
                recorder.events.append("normalize")
                recorder.normalizationSessionRoots.append((jsonRoot, sourceRoot))
            },
            buildReview: { _, jsonRoot, sourceRoot, _ in
                recorder.events.append("review")
                recorder.reviewSessionRoots.append((jsonRoot, sourceRoot))
            },
            planExport: { _, session, sourceRoot, outputDir, recursive, conflictPolicy, qualityGrading in
                recorder.events.append("export")
                recorder.exportCalls.append(
                    EffectRecorder.ExportCall(
                        sessionID: session.session.sessionID,
                        sourceRoot: sourceRoot,
                        outputDir: outputDir,
                        recursive: recursive,
                        conflictPolicy: conflictPolicy,
                        qualityGrading: qualityGrading
                    )
                )
            },
            sleep: { duration in
                recorder.events.append("sleep")
                recorder.sleepCalls.append(
                    EffectRecorder.SleepCall(
                        duration: duration,
                        selectedAction: holder?.flow?.selectedAction,
                        step: holder?.flow?.step
                    )
                )
                if yieldsDuringSleep {
                    try? await Task.sleep(for: .milliseconds(1))
                }
            },
            reportAssertion: { message in recorder.assertionMessages.append(message) }
        )
    }

    private func makeSession(id: String, sourceRoot: String?) -> NormalizationSessionDocument {
        NormalizationSessionDocument(
            session: NormalizationSessionMetadata(
                sessionID: id,
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                workflow: .fromJSON,
                inputPath: "/sidecars",
                normalizationMode: .singleImage,
                scanRoot: nil,
                sourceRoot: sourceRoot,
                outputDir: nil
            ),
            vocabulary: VocabularyIdentity(
                path: "observed-tags://session",
                sha256: String(repeating: "d", count: 64),
                schemaVersion: "observed-tags/1.0",
                mode: .observedTags,
                entryCount: 0
            ),
            resolvedConfiguration: .builtInDefaults,
            sessionContext: [],
            privacy: NormalizationPrivacyRecord(privacyMode: .standard),
            xmpWriter: MetadataWriteEngineContext(
                engineName: OwnedXMPSidecarEngine.engineName,
                engineVersion: OwnedXMPSidecarEngine.engineVersion,
                writerRecipeVersion: OwnedXMPSidecarEngine.writerRecipeVersion
            ),
            sourceAISidecars: [],
            sourceAssets: [],
            sameBaseNameGroups: [],
            affinity: NormalizationAffinityRecord(
                mode: .off,
                profile: .balanced,
                minAffinityForConsensus: 0.55,
                nodes: []
            ),
            artifacts: NormalizationArtifactPlan(
                sessionPath: nil,
                reportPath: "/artifacts/report.json",
                summaryPath: "/artifacts/summary.md",
                progressPath: "/artifacts/progress.jsonl",
                xmpTargetRoot: nil
            ),
            deterministicPolicy: NormalizationDeterministicPolicyRecord(exactAffinityInputsPersisted: false),
            warnings: [],
            errors: []
        )
    }
}
