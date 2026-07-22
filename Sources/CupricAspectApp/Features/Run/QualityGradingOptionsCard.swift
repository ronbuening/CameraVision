import AISidecarCore
import SwiftUI

struct QualityGradingOptionsCard: View {
    @Bindable var options: AnalysisOptions
    let availability: Step3OptionsView.QualityGradingAvailability

    @Environment(\.cvTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("QUALITY")
            if !availability.controlsEnabled {
                Text(Step3OptionsView.gradingRequiresAssessmentExplanation)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.accent.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Quality grading", isOn: $options.qualityGradingEnabled)
                    .toggleStyle(.switch)
                    .tint(theme.accent.accent)

                Divider().overlay(theme.border)

                Toggle("Write star ratings", isOn: $options.qualityWriteRating)
                    .toggleStyle(.checkbox)
                Text(Step3OptionsView.ratingOptInRationale)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textFaint)

                HStack(spacing: 12) {
                    Text("Existing culling metadata")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Spacer()
                    qualityConflictPolicyPicker
                }
            }
            .disabled(!availability.controlsEnabled)
            .opacity(availability.controlsEnabled ? 1 : 0.5)
        }
        .padding(EdgeInsets(top: 15, leading: 17, bottom: 15, trailing: 17))
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    private var qualityConflictPolicyPicker: some View {
        Picker("", selection: $options.qualityConflictPolicy) {
            Text(ScalarConflictPolicy.preserve.wizardLabel).tag(ScalarConflictPolicy.preserve)
            Text(ScalarConflictPolicy.refresh.wizardLabel).tag(ScalarConflictPolicy.refresh)
            Text(ScalarConflictPolicy.overwrite.wizardLabel).tag(ScalarConflictPolicy.overwrite)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(theme.textFaint)
    }
}
