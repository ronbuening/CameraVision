import AISidecarCore
import SwiftUI

struct SettingsQualityGradingSection: View {
    @Bindable var settings: SettingsModel

    @Environment(\.cvTheme) private var theme

    private var controls: SettingsControls { SettingsControls(theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Quality grading defaults")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text("EXPERIMENTAL")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.4)
                    .foregroundStyle(theme.accent.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(theme.accent.soft)
                    .clipShape(Capsule())
            }
            Text("Default metadata channels and confidence threshold used when quality grading is enabled for a run.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textFaint)

            controls.settingRow("Minimum confidence") {
                CVSegmentedControl(
                    options: [
                        QualityAssessmentRecord.Confidence.low,
                        .medium,
                        .high,
                    ],
                    selection: Binding(
                        get: { settings.qualityMinimumConfidence },
                        set: { settings.setQualityMinimumConfidence($0) }
                    ),
                    label: { $0.rawValue.capitalized }
                )
            }

            Text("Metadata channels")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textDim)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    qualityChannelToggle(
                        "Labels",
                        value: Binding(
                            get: { settings.qualityWriteLabel },
                            set: { settings.setQualityWriteLabel($0) }
                        )
                    )
                    qualityChannelToggle(
                        "Urgency",
                        value: Binding(
                            get: { settings.qualityWriteUrgency },
                            set: { settings.setQualityWriteUrgency($0) }
                        )
                    )
                }
                GridRow {
                    qualityChannelToggle(
                        "Pick flags",
                        value: Binding(
                            get: { settings.qualityWriteFlag },
                            set: { settings.setQualityWriteFlag($0) }
                        )
                    )
                    qualityChannelToggle(
                        "Keywords",
                        value: Binding(
                            get: { settings.qualityWriteKeywords },
                            set: { settings.setQualityWriteKeywords($0) }
                        )
                    )
                }
                GridRow {
                    qualityChannelToggle(
                        "Star ratings",
                        value: Binding(
                            get: { settings.qualityWriteRating },
                            set: { settings.setQualityWriteRating($0) }
                        )
                    )
                    Text("Opt in to keep your stars untouched by default.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textFaint)
                }
            }
        }
    }

    private func qualityChannelToggle(
        _ title: String,
        value: Binding<Bool>
    ) -> some View {
        Toggle(title, isOn: value)
            .toggleStyle(.checkbox)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(theme.text)
            .frame(minWidth: 150, alignment: .leading)
    }
}
