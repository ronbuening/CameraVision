import SwiftUI

/// Wizard shell (design doc Section 6): 46px title bar, step rail, content
/// area, footer nav. M1 implements Step 1 (Photos) for real; Steps 2–5 are
/// labeled placeholders that arrive with their milestones (M2 · M4 · M6 · M7).
struct WizardShellView: View {
    @Environment(\.cvTheme) private var theme
    @State private var importModel = FolderImportModel()
    @State private var options = AnalysisOptions()
    @State private var runModel = AnalysisRunModel()
    @State private var reviewModel = ReviewModel()
    @State private var selectedAction: WizardAction?
    @State private var step = 1
    @State private var showAbout = false
    @AppStorage(PreferenceKeys.theme) private var themeChoice: ThemeChoice = .light
    @Environment(\.colorScheme) private var colorScheme

    private static let stepLabels = ["Photos", "What to do", "Options", "Working", "Review"]

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(theme.border)
            stepRail
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
            AboutView(showsCloseButton: true)
                .frame(width: 440, height: 620)
        }
        .task {
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
            // FR4-046a: offer recovery of an interrupted review on launch.
            if reviewModel.recoveryAvailable {
                selectedAction = .analyze
                step = 5
            }
            if env["CUPRIC_DEBUG_AUTORUN"] == "1" {
                selectedAction = .analyze
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
                Step3OptionsView(
                    action: selectedAction ?? .analyze,
                    options: options,
                    runModel: runModel,
                    importModel: importModel
                )
            }
        case 4:
            Step4WorkingView(action: selectedAction ?? .analyze, runModel: runModel)
        default:
            VStack(spacing: 0) {
                if case .finished(let outcome) = runModel.phase, outcome.failed > 0 {
                    Step5SummaryView(outcome: outcome)
                }
                Step5ReviewView(review: reviewModel, runOutcome: finishedOutcome)
            }
        }
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

    private var backEnabled: Bool { step > 1 && step != 4 }

    private var primaryEnabled: Bool {
        switch step {
        case 1: importModel.sourceFolder != nil
        case 2: selectedAction != nil
        case 3: importModel.sourceFolder != nil && !runModel.isRunning
        case 4: false
        default: true
        }
    }

    private var primaryLabel: String {
        switch step {
        case 3: "Start"
        case 4: "Working…"
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
            return "\(reviewModel.approvedCount) approved · Done clears the review"
        }
    }

    private func primaryAction() {
        switch step {
        case 1, 2:
            step += 1
        case 3:
            guard let source = importModel.sourceFolder else { return }
            runModel.start(
                options: options,
                inputPath: source.path,
                recursive: importModel.recursive,
                outputDir: importModel.outputFolder?.path,
                expectedTotal: importModel.assets.count
            )
            step = 4
        case 5:
            reviewModel.completeCleanly()
            runModel.reset()
            selectedAction = nil
            step = 1
        default:
            break
        }
    }

    private var footerBar: some View {
        HStack(spacing: 14) {
            Button {
                if backEnabled { step -= 1 }
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
