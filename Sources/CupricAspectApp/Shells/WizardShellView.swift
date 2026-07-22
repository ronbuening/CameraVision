import AppKit
import SwiftUI

/// Wizard shell (design doc Section 6): 46px title bar, step rail, content
/// area, footer nav. M1 implements Step 1 (Photos) for real; Steps 2–5 are
/// labeled placeholders that arrive with their milestones (M2 · M4 · M6 · M7).
struct WizardShellView: View {
    @Environment(\.cvTheme) private var theme
    @Bindable var flow: WizardFlowModel
    @AppStorage(PreferenceKeys.theme) private var themeChoice: ThemeChoice = .light
    @Environment(\.colorScheme) private var colorScheme

    private static let stepLabels = ["Photos", "What to do", "Options", "Working", "Review"]

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(theme.border)
            stepRail
            RuntimeGuidanceBanner(guidance: flow.runtimeGuidance)
            ScrollView {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.winBg)
            Divider().overlay(theme.border)
            footerBar
        }
        .background(theme.winBg)
        .sheet(isPresented: $flow.showSettings) {
            SettingsSheet(visionTagsModel: flow.visionTagsModel)
        }
        .sheet(isPresented: $flow.showPlanSheet) {
            ChangePlanSheet(export: flow.exportModel)
        }
        .confirmationDialog(
            flow.rerunConfirmationTitle,
            isPresented: $flow.showRerunConfirmation,
            titleVisibility: .visible
        ) {
            Button("Re-run", role: .destructive) {
                flow.startRun()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(flow.rerunConfirmationMessage)
        }
        .confirmationDialog(
            "Discard the restored review?",
            isPresented: $flow.showDiscardRestoredReviewConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save session first...") {
                saveRestoredReviewSessionThenFinish()
            }
            Button("Discard review", role: .destructive) {
                flow.finishCleanly()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Discard the restored review? \(flow.reviewModel.verdicts.count) decisions will be lost.")
        }
    }

    // MARK: - Chrome

    private var titleBar: some View {
        HStack(spacing: 9) {
            ApertureView(size: 20, running: flow.importModel.scanning || flow.runModel.isRunning, spin: true)
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
                flow.showSettings = true
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
        .padding(.leading, 34)  // align the brand with the content column
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
        let done = flow.step > index
        let current = flow.step == index
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
        switch flow.step {
        case 1:
            Step1PhotosView(model: flow.importModel)
        case 2:
            Step2ActionView(
                selection: $flow.selectedAction,
                assessQuality: Binding(
                    get: { flow.options.assessQuality },
                    set: { flow.options.assessQuality = $0 }
                ),
                onApplySession: {
                    flow.selectApplySessionAction()
                })
        case 3:
            VStack(spacing: 0) {
                if case .failed(let message) = flow.runModel.phase {
                    failureBanner(message)
                }
                if case .failed(let message) = flow.exportModel.phase {
                    failureBanner(message)
                }
                if case .failed(let message) = flow.normalizationModel.phase {
                    failureBanner(message)
                }
                if flow.selectedAction == .apply {
                    Step3ApplyView(
                        session: $flow.applySession,
                        sessionPath: $flow.applySessionPath,
                        qualityGradingEnabled: Binding(
                            get: { flow.exportModel.applyQualityGradingEnabled },
                            set: { flow.exportModel.applyQualityGradingEnabled = $0 }
                        ),
                        qualityConflictPolicy: Binding(
                            get: { flow.exportModel.applyQualityConflictPolicy },
                            set: { flow.exportModel.applyQualityConflictPolicy = $0 }
                        )
                    )
                } else {
                    Step3OptionsView(
                        action: flow.selectedAction ?? .analyze,
                        options: flow.options,
                        runModel: flow.runModel,
                        importModel: flow.importModel,
                        normalizationModel: flow.normalizationModel,
                        visionTagsModel: flow.visionTagsModel
                    )
                }
            }
        case 4:
            Step4WorkingView(action: flow.selectedAction ?? .analyze, runModel: flow.runModel)
        default:
            VStack(spacing: 0) {
                if case .finished(let outcome) = flow.runModel.phase, outcome.failed > 0 {
                    Step5SummaryView(outcome: outcome)
                }
                if case .failed(let message) = flow.exportModel.phase {
                    failureBanner(message)
                }
                if let warning = flow.exportModel.cleanupWarning {
                    failureBanner(warning)
                }
                if flow.exportModel.phase == .written, let report = flow.exportModel.exportReport {
                    writtenBanner(
                        WizardNavigation.writtenBanner(
                            written: report.writtenCount,
                            failed: report.failedCount,
                            cleanupRemoved: flow.exportModel.cleanupRemovedCount
                        ))
                    ExportReportView(report: report)
                        .padding(EdgeInsets(top: 12, leading: 34, bottom: 0, trailing: 34))
                }
                switch flow.selectedAction {
                case .normalize:
                    NormalizationInspectorView(model: flow.normalizationModel) {
                        flow.startExport()
                    }
                case .apply:
                    EmptyView()
                default:
                    Step5ReviewView(review: flow.reviewModel, runOutcome: flow.finishedOutcome)
                }
            }
        }
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

    private func saveRestoredReviewSessionThenFinish() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "review-session.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try flow.saveRestoredReviewSession(to: url)
            } catch {
                flow.reviewModel.reportFileError("Save session", error)
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 14) {
            Button {
                flow.goBack()
            } label: {
                Text("‹ Back")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 16)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.borderStrong))
            }
            .buttonStyle(.plain)
            .opacity(flow.backEnabled ? 1 : 0.35)
            .disabled(!flow.backEnabled)

            if flow.step == 5 {
                Button(action: flow.requestFinish) {
                    Text("↺ Restart")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 16)
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.borderStrong))
                }
                .buttonStyle(.plain)
                .help("Discard this run and start over from Step 1")
            }

            Text(flow.footerHint)
                .font(.system(size: 12))
                .foregroundStyle(theme.textFaint)

            Spacer()

            Button(action: flow.primaryAction) {
                Text(flow.primaryLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 22)
                    .background(theme.accent.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .opacity(flow.primaryEnabled ? 1 : 0.4)
            .disabled(!flow.primaryEnabled)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 13)
        .background(theme.titlebar)
    }
}
