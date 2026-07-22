import SwiftUI

struct SettingsAppearanceSection: View {
    @Binding var themeChoice: ThemeChoice
    @Binding var accentChoice: AccentChoice

    @Environment(\.cvTheme) private var theme

    private var controls: SettingsControls { SettingsControls(theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controls.sectionLabel("APPEARANCE")
            controls.card {
                controls.settingRow("Theme", caption: "Auto follows your macOS appearance.") {
                    CVSegmentedControl(
                        options: ThemeChoice.allCases,
                        selection: $themeChoice,
                        label: { $0.rawValue.capitalized }
                    )
                }
                Divider().overlay(theme.border)
                controls.settingRow("Accent color", caption: "Pulled from the CupricAspect palette.") {
                    HStack(spacing: 12) {
                        ForEach(AccentChoice.allCases, id: \.self) { choice in
                            Button {
                                accentChoice = choice
                            } label: {
                                Circle()
                                    .fill(choice.swatch)
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle().strokeBorder(
                                            accentChoice == choice ? theme.text : .clear,
                                            lineWidth: 2
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(choice.displayName)
                        }
                    }
                }
            }
        }
    }
}

struct SettingsInterfaceSection: View {
    @Binding var nonlinear: Bool

    @Environment(\.cvTheme) private var theme

    private var controls: SettingsControls { SettingsControls(theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controls.sectionLabel("INTERFACE")
            controls.card {
                controls.settingRow(
                    "Nonlinear UI",
                    caption: FeatureFlags.studioUI
                        ? "Switch between the Wizard and Studio layouts." : "Studio layout — coming soon."
                ) {
                    Toggle("", isOn: FeatureFlags.studioUI ? $nonlinear : .constant(false))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!FeatureFlags.studioUI)
                }
            }
        }
    }
}
