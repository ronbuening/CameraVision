import AISidecarCore
import SwiftUI

/// Wizard Step 3 — "Review & options" (design doc §6 Step 3). RAW+JPEG pair
/// scope is export-only and arrives with M7's export options.
struct Step3OptionsView: View {
    struct QualityGradingAvailability: Equatable {
        var isVisible: Bool
        var controlsEnabled: Bool
    }

    let action: WizardAction
    @Bindable var options: AnalysisOptions
    @Bindable var runModel: AnalysisRunModel
    var importModel: FolderImportModel
    var normalizationModel: NormalizationModel?
    @Bindable var visionTagsModel: VisionTagsModel

    @Environment(\.cvTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Review & options")
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(theme.text)
            Text(action.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(theme.textDim)
                .padding(.top, 5)

            summaryCard
                .padding(.top, 20)

            HStack(spacing: 14) {
                renderModeCard
                RunModelPickerCard(
                    options: options,
                    runModel: runModel,
                    importModel: importModel,
                    visionTagsModel: visionTagsModel
                )
            }
            .padding(.top, 14)

            let gradingAvailability = Self.qualityGradingAvailability(
                action: action,
                assessQuality: options.assessQuality
            )
            if gradingAvailability.isVisible {
                QualityGradingOptionsCard(options: options, availability: gradingAvailability)
                    .padding(.top, 14)
            }

            AdvancedOptionsCard(options: options)
                .padding(.top, 14)

            if action == .normalize, let normalizationModel {
                SessionContextPanel(model: normalizationModel)
                    .padding(.top, 14)
            }
        }
        .padding(EdgeInsets(top: 26, leading: 34, bottom: 40, trailing: 34))
        .onAppear {
            options.loadResolvedDefaults()
            Task { await loadVisionTagsIfNeeded() }
            runPreflight()
        }
    }

    /// D-G3: the disabled state also pauses a config/environment grading
    /// default — say so, or config owners see their default silently ignored.
    nonisolated static let gradingRequiresAssessmentExplanation =
        "Assess image quality in Step 2 before this Wizard run can grade. "
        + "While assessment is off, grading stays off for this run — even when your configuration enables it by default."

    /// Mirrors the CLI docs' rationale for the opt-in rating channel.
    nonisolated static let ratingOptInRationale = "stars stay yours unless you opt in"

    /// Trade-off wording for the quality scan mode, shared with the Settings
    /// sheet caption so the two surfaces cannot drift.
    nonisolated static let qualityScanFootnote =
        "Quality scan (when Step 2 assesses quality): Normal assesses in the same model call; "
        + "High quality runs a second pass per image — slower, but keywords stay identical to a run without assessment."

    nonisolated static func qualityGradingAvailability(
        action: WizardAction,
        assessQuality: Bool
    ) -> QualityGradingAvailability {
        switch action {
        case .write, .normalize:
            QualityGradingAvailability(isVisible: true, controlsEnabled: assessQuality)
        case .analyze, .apply:
            QualityGradingAvailability(isVisible: false, controlsEnabled: false)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            summaryRow("from", importModel.sourceFolder?.path ?? "—")
            summaryRow("to", importModel.outputFolder?.path ?? "\(importModel.sourceFolder?.path ?? "—") (in place)")
            summaryRow("", "\(importModel.assets.count) images detected")
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label.isEmpty ? "    " : label)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textFaint)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(label.isEmpty ? theme.textFaint : theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var renderModeCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("RENDER MODE")
            CVSegmentedControl(
                options: AnalysisMode.allCases,
                selection: $options.mode,
                label: { mode in
                    switch mode {
                    case .whole: "Whole Image"
                    case .subject: "Subject Only"
                    case .both: "Both"
                    }
                }
            )
        }
        .padding(EdgeInsets(top: 15, leading: 17, bottom: 15, trailing: 17))
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(theme.textFaint)
    }

    private func runPreflight() {
        runModel.checkPreflight(
            options: options,
            recursive: importModel.recursive,
            outputDir: importModel.outputFolder?.path
        )
    }

    private func loadVisionTagsIfNeeded() async {
        guard let endpoint = URL(string: options.resolvedEndpoint) else {
            visionTagsModel.fail(message: "Invalid model endpoint.")
            return
        }
        await visionTagsModel.loadIfNeeded(endpoint: endpoint)
    }

}
