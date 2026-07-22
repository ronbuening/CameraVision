import SwiftUI

/// The Settings sheet (design doc §6 Settings, FR4-056/057): model picker,
/// shared run defaults, cache controls, appearance, and version information.
struct SettingsSheet: View {
    @State private var settings: SettingsModel
    @AppStorage(PreferenceKeys.theme) private var themeChoice: ThemeChoice = .light
    @AppStorage(PreferenceKeys.accent) private var accentChoice: AccentChoice = .copper
    @AppStorage(PreferenceKeys.logSizeCapMB) private var logSizeCapMB = GUILog.defaultSizeCapMB
    @AppStorage(PreferenceKeys.nonlinear) private var nonlinear = false

    @Environment(\.cvTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var purgedCount: Int?
    @State private var confirmPurge = false

    init(visionTagsModel: VisionTagsModel) {
        _settings = State(initialValue: SettingsModel(visionTagsModel: visionTagsModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.textDim)
            }
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 12, trailing: 18))
            .background(theme.titlebar)

            Divider().overlay(theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = settings.loadError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.danger)
                    }
                    SettingsModelSection(settings: settings)
                    SettingsConfigurationSection(
                        settings: settings,
                        purgedCount: $purgedCount,
                        confirmPurge: $confirmPurge
                    )
                    SettingsAppearanceSection(themeChoice: $themeChoice, accentChoice: $accentChoice)
                    SettingsInterfaceSection(nonlinear: $nonlinear)
                    SettingsAboutSection(logSizeCapMB: $logSizeCapMB)
                }
                .padding(18)
            }
        }
        .frame(width: 560, height: 700)
        .background(theme.winBg)
        .task { await settings.loadVisionTagsIfNeeded() }
        .confirmationDialog(
            "Purge the derivative cache?",
            isPresented: $confirmPurge
        ) {
            Button("Purge", role: .destructive) {
                purgedCount = settings.purgeDerivativeCache()
            }
        } message: {
            Text("Cached render derivatives are re-created on the next run. Shared with the CLI.")
        }
    }
}
