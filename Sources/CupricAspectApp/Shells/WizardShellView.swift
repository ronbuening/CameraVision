import AISidecarCore
import AppKit
import SwiftUI

/// Wizard shell (design doc Section 6): 46px title bar, step rail, content
/// area, footer nav. M1 implements Step 1 (Photos) for real; Steps 2–5 are
/// labeled placeholders that arrive with their milestones (M2 · M4 · M6 · M7).
struct WizardShellView: View {
    @Environment(\.cvTheme) private var theme
    @State private var importModel = FolderImportModel()
    @State private var options = AnalysisOptions()
    @State private var runModel = AnalysisRunModel()
    @State private var runtimeGuidance = RuntimeGuidanceModel()
    @State private var reviewModel = ReviewModel()
    @State private var normalizationModel = NormalizationModel()
    @State private var exportModel = ExportModel()
    @State private var applySession: NormalizationSessionDocument?
    @State private var applySessionPath: String?
    @State private var showPlanSheet = false
    @State private var selectedAction: WizardAction?
    @State private var step = 1
    @State private var showAbout = false
    @State private var showRerunConfirmation = false
    @State private var showDiscardRestoredReviewConfirmation = false
    @AppStorage(PreferenceKeys.theme) private var themeChoice: ThemeChoice = .light
    @Environment(\.colorScheme) private var colorScheme

    private static let stepLabels = ["Photos", "What to do", "Options", "Working", "Review"]

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(theme.border)
            stepRail
            RuntimeGuidanceBanner(guidance: runtimeGuidance)
            ScrollView {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.winBg)
            Divider().overlay(theme.border)
            footerBar
        }
        .background(theme.winBg)
        .sheet(isPresented: $showAbout) {
            SettingsSheet()
        }
        .task {
            // FR4-058: one launch-time runtime check (no polling — FR4-051).
            runtimeGuidance.check()
            runModel.onRecord = { [weak importModel] record in
                importModel?.apply(record)
            }
            // Dev/UI-test hooks: auto-import a folder / jump to a step via
            // environment. No effect in normal launches; not preferences.
            let env = ProcessInfo.processInfo.environment
            if let path = env["CUPRIC_IMPORT_PATH"] {
                importModel.chooseSource(URL(fileURLWithPath: path, isDirectory: true))
            }
            if let rawStep = env["CUPRIC_DEBUG_STEP"], let debugStep = Int(rawStep), (1...5).contains(debugStep) {
                selectedAction = .analyze
                step = debugStep
            }
            if env["CUPRIC_DEBUG_SETTINGS"] == "1" {
                showAbout = true
            }
            // FR4-046a: offer recovery of an interrupted review on launch.
            if reviewModel.recoveryAvailable {
                selectedAction = .write
                step = 5
            }
            if env["CUPRIC_DEBUG_AUTORUN"] == "1" {
                selectedAction = env["CUPRIC_DEBUG_ACTION"].flatMap(WizardAction.init(rawValue:)) ?? .analyze
                while importModel.scanning || importModel.assets.isEmpty {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                step = 3
                try? await Task.sleep(for: .seconds(2))
                primaryAction()
            }
        }
        .onChange(of: runModel.phase) { _, phase in
            switch phase {
            case .finished(let outcome):
                if outcome.interrupted {
                    // Design §6 Step 4: cancel returns to the options step.
                    runModel.reset()
                    step = 3
                } else if selectedAction == .normalize {
                    // Stay on the working step; the model-free normalization
                    // run advances to the Inspector when ready.
                    if let source = importModel.sourceFolder {
                        normalizationModel.run(
                            jsonRoot: importModel.outputFolder?.path ?? source.path,
                            sourceRoot: source.path
                        )
                    }
                } else {
                    step = 5
                    if let source = importModel.sourceFolder {
                        reviewModel.buildSession(
                            jsonRoot: importModel.outputFolder?.path ?? source.path,
                            sourceRoot: source.path
                        )
                    }
                }
                Task { await importModel.rescan() }
            case .failed:
                // Surface the failure on the options screen (banner there).
                step = 3
            default:
                break
            }
        }
        .onChange(of: normalizationModel.phase) { _, phase in
            switch phase {
            case .ready where step == 4:
                step = 5
            case .written:
                Task { await importModel.rescan() }
            case .failed where step == 4:
                step = 3
            default:
                break
            }
        }
        .onChange(of: exportModel.phase) { _, phase in
            switch phase {
            case .planReady:
                showPlanSheet = true
            case .written:
                step = 5
                Task { await importModel.rescan() }
            default:
                break
            }
        }
        .onChange(of: reviewModel.session?.session.sessionID) { _, _ in
            rehydrateImportContextFromReviewSession()
        }
        .sheet(isPresented: $showPlanSheet) {
            ChangePlanSheet(export: exportModel)
        }
        .confirmationDialog(
            rerunConfirmationTitle,
            isPresented: $showRerunConfirmation,
            titleVisibility: .visible
        ) {
            Button("Re-run", role: .destructive) {
                startRun()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(rerunConfirmationMessage)
        }
        .confirmationDialog(
            "Discard the restored review?",
            isPresented: $showDiscardRestoredReviewConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save session first...") {
                saveRestoredReviewSessionThenFinish()
            }
            Button("Discard review", role: .destructive) {
                finishCleanly()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Discard the restored review? \(reviewModel.verdicts.count) decisions will be lost.")
        }
    }

    // MARK: - Chrome

    private var titleBar: some View {
        HStack(spacing: 9) {
            ApertureView(size: 20, running: importModel.scanning || runModel.isRunning, spin: true)
            Text("CupricAspect")
                .font(.system(size: 13, weight: .bold))
                .kerning(-0.1)
                .foregroundStyle(theme.text)
            Spacer()
            Button {
                themeChoice = colorScheme == .dark ? .light : .dark
            } label: {
                Text(colorScheme == .dark ? "☀" : "☾")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textDim)
                    .frame(width: 30, height: 24)
                    .background(theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.border))
            }
            .buttonStyle(.plain)
            .help("Toggle appearance")
            Button {
                showAbout = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textDim)
                    .frame(width: 30, height: 24)
                    .background(theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.border))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.leading, 84) // clear the native traffic lights under .hiddenTitleBar
        .padding(.trailing, 14)
        .frame(height: 46)
        .background(theme.titlebar)
    }

    private var stepRail: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { index in
                railItem(index)
                if index < 5 {
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 34, bottom: 6, trailing: 34))
        .background(theme.winBg)
    }

    private func railItem(_ index: Int) -> some View {
        let done = step > index
        let current = step == index
        return HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(done ? theme.green : (current ? theme.accent.accent : theme.panel2))
                Text(done ? "✓" : String(index))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(done || current ? .white : theme.textFaint)
            }
            .frame(width: 24, height: 24)
            Text(Self.stepLabels[index - 1])
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(done ? theme.textDim : (current ? theme.text : theme.textFaint))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case 1:
            Step1PhotosView(model: importModel)
        case 2:
            Step2ActionView(selection: $selectedAction)
        case 3:
            VStack(spacing: 0) {
                if case .failed(let message) = runModel.phase {
                    failureBanner(message)
                }
                if case .failed(let message) = exportModel.phase {
                    failureBanner(message)
                }
                if case .failed(let message) = normalizationModel.phase {
                    failureBanner(message)
                }
                if selectedAction == .apply {
                    Step3ApplyView(session: $applySession, sessionPath: $applySessionPath)
                } else {
                    Step3OptionsView(
                        action: selectedAction ?? .analyze,
                        options: options,
                        runModel: runModel,
                        importModel: importModel,
                        normalizationModel: normalizationModel
                    )
                }
            }
        case 4:
            Step4WorkingView(action: selectedAction ?? .analyze, runModel: runModel)
        default:
            VStack(spacing: 0) {
                if case .finished(let outcome) = runModel.phase, outcome.failed > 0 {
                    Step5SummaryView(outcome: outcome)
                }
                if case .failed(let message) = exportModel.phase {
                    failureBanner(message)
                }
                if exportModel.phase == .written, let report = exportModel.exportReport {
                    writtenBanner(WizardNavigation.writtenBanner(
                        written: report.writtenCount,
                        failed: report.failedCount
                    ))
                    ExportReportView(report: report)
                        .padding(EdgeInsets(top: 12, leading: 34, bottom: 0, trailing: 34))
                }
                switch selectedAction {
                case .normalize:
                    NormalizationInspectorView(model: normalizationModel) {
                        startExport()
                    }
                case .apply:
                    EmptyView()
                default:
                    Step5ReviewView(review: reviewModel, runOutcome: finishedOutcome)
                }
            }
        }
    }

    /// Route every write through the FR4-029 dry-run gate (M7): the plan
    /// sheet opens when the dry run completes.
    private func startExport() {
        guard let source = importModel.sourceFolder else {
            let error = exportReadinessError("No source folder is loaded; choose a folder before writing XMP.")
            reportStartExportError(error)
            assertionFailure(error.message)
            return
        }
        let session: NormalizationSessionDocument? = switch selectedAction {
        case .normalize: normalizationModel.session
        case .apply: applySession
        default: reviewModel.reviewedSession
        }
        guard let session else {
            let error = exportReadinessError(missingExportSessionMessage)
            reportStartExportError(error)
            assertionFailure(error.message)
            return
        }
        exportModel.plan(
            session: session,
            sourceRoot: source.path,
            outputDir: importModel.outputFolder?.path
        )
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
              FileManager.default.fileExists(atPath: root) else {
            return
        }
        if reviewModel.restoredFromRecovery {
            selectedAction = .write
        }
        guard importModel.sourceFolder?.path != root else { return }
        importModel.chooseSource(URL(fileURLWithPath: root, isDirectory: true))
    }

    private func writtenBanner(_ content: WrittenBannerContent) -> some View {
        let tone = content.isWarning ? theme.danger : theme.green
        let fill = content.isWarning ? theme.danger.opacity(0.12) : theme.greenSoft
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(tone)
                Text(content.isWarning ? "!" : "✓")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
            Text(content.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer()
        }
        .padding(EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15))
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tone.opacity(0.5)))
        .padding(EdgeInsets(top: 20, leading: 34, bottom: 0, trailing: 34))
    }

    private var finishedOutcome: RunOutcome? {
        if case .finished(let outcome) = runModel.phase { return outcome }
        return nil
    }

    private func failureBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Text("!")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(theme.danger)
                .clipShape(Circle())
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.text)
            Spacer()
        }
        .padding(EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15))
        .background(theme.danger.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.danger.opacity(0.5)))
        .padding(EdgeInsets(top: 20, leading: 34, bottom: 0, trailing: 34))
    }

    // MARK: - Footer

    private var backEnabled: Bool {
        WizardNavigation.backTarget(from: step, phase: runModel.phase) != nil
    }

    private var primaryEnabled: Bool {
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

    /// True when Step 5's primary should be a write, not Done (M7).
    private var step5WriteAvailable: Bool {
        guard exportModel.phase != .written else { return false }
        guard importModel.sourceFolder != nil else { return false }
        switch selectedAction {
        case .write: return reviewModel.session != nil
        case .normalize: return normalizationModel.session != nil
        default: return false
        }
    }

    private var primaryLabel: String {
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

    private var footerHint: String {
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

    private func primaryAction() {
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
            if WizardNavigation.doneNeedsConfirmation(
                hasSession: reviewModel.session != nil,
                restoredRecoveryDirty: reviewModel.restoredRecoveryDirty,
                exported: exportModel.phase == .written
            ) {
                showDiscardRestoredReviewConfirmation = true
            } else {
                finishCleanly()
            }
        default:
            break
        }
    }

    private var rerunConfirmationTitle: String {
        selectedAction == .normalize ? "Re-run normalization?" : "Re-run the analysis?"
    }

    private var rerunConfirmationMessage: String {
        if selectedAction == .normalize {
            return "This discards the current normalization session and Inspector outcomes."
        }
        return "This discards the current results and \(reviewModel.verdicts.count) review decisions."
    }

    private func startRun() {
        guard let source = importModel.sourceFolder else { return }
        runModel.start(
            options: options,
            inputPath: source.path,
            recursive: importModel.recursive,
            outputDir: importModel.outputFolder?.path,
            expectedTotal: importModel.assets.count
        )
        step = 4
    }

    private func finishCleanly() {
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

    private func saveRestoredReviewSessionThenFinish() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "review-session.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try reviewModel.saveSession(to: url)
                reviewModel.clearFileError()
                finishCleanly()
            } catch {
                reviewModel.reportFileError("Save session", error)
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 14) {
            Button {
                if let target = WizardNavigation.backTarget(from: step, phase: runModel.phase) {
                    step = target
                }
            } label: {
                Text("‹ Back")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 16)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.borderStrong))
            }
            .buttonStyle(.plain)
            .opacity(backEnabled ? 1 : 0.35)
            .disabled(!backEnabled)

            Text(footerHint)
                .font(.system(size: 12))
                .foregroundStyle(theme.textFaint)

            Spacer()

            Button(action: primaryAction) {
                Text(primaryLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 22)
                    .background(theme.accent.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .opacity(primaryEnabled ? 1 : 0.4)
            .disabled(!primaryEnabled)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 13)
        .background(theme.titlebar)
    }
}
