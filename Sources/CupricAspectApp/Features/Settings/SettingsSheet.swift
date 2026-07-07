import AISidecarCore
import SwiftUI

/// The Settings sheet (design doc §6 Settings, FR4-056/057): model picker
/// from installed vision-capable Ollama tags, endpoint, run defaults written
/// through to the shared config.json, cache purge, appearance, and the app
/// version card.
struct SettingsSheet: View {
    @State private var settings = SettingsModel()
    @AppStorage(PreferenceKeys.theme) private var themeChoice: ThemeChoice = .light
    @AppStorage(PreferenceKeys.accent) private var accentChoice: AccentChoice = .copper

    @Environment(\.cvTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var purgedCount: Int?
    @State private var confirmPurge = false

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
                    modelSection
                    configurationSection
                    appearanceSection
                    interfaceSection
                    aboutSection
                }
                .padding(18)
            }
        }
        .frame(width: 560, height: 700)
        .background(theme.winBg)
        .task { settings.refreshVisionTags() }
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

    // MARK: - Sections

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(theme.textFaint)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MODEL")
            card {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vision model tag")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text("Installed Ollama models with the vision capability.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textFaint)
                    }
                    Spacer()
                    modelPicker
                }
                if settings.configuredModelUnavailable {
                    Text("The configured model isn't installed (or isn't vision-capable) at this endpoint — pick another or `ollama pull` it.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.danger)
                }
                Divider().overlay(theme.border)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ollama endpoint")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                    }
                    Spacer()
                    TextField("http://localhost:11434", text: $settings.endpointDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .frame(width: 220)
                        .background(theme.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.border))
                        .onSubmit { settings.applyEndpoint() }
                    Button("Apply") { settings.applyEndpoint() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.accent.accent)
                    connectionBadge
                }
            }
        }
    }

    private var modelPicker: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(settings.visionTags, id: \.self) { tag in
                    Button {
                        settings.setModel(tag)
                    } label: {
                        if tag == settings.model {
                            Label(tag, systemImage: "checkmark")
                        } else {
                            Text(tag)
                        }
                    }
                }
                if settings.visionTags.isEmpty {
                    Button("No vision models found") {}.disabled(true)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(settings.model)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("▾").font(.system(size: 9))
                }
                .foregroundStyle(theme.text)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(theme.panel2)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.border))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button {
                settings.refreshVisionTags()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textDim)
            }
            .buttonStyle(.plain)
            .help("Refresh installed models")
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch settings.visionTagState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView().controlSize(.small)
        case .loaded:
            HStack(spacing: 5) {
                Circle().fill(theme.green).frame(width: 7, height: 7)
                Text("connected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.green)
            }
        case .failed(let message):
            HStack(spacing: 5) {
                Circle().fill(theme.danger).frame(width: 7, height: 7)
                Text("unreachable")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.danger)
            }
            .help(message)
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionLabel("CONFIGURATION")
                Text("— defaults saved to config.json, shared with the CLI")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textFaint)
            }
            card {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active config file")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text(settings.configPathDisplay)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Reveal") { settings.revealConfigInFinder() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.textDim)
                }
                if !settings.environmentOverrides.isEmpty {
                    Text("Environment overrides active: \(settings.environmentOverrides.joined(separator: ", ")) — these take precedence over the file.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.accent.accent)
                }
                Divider().overlay(theme.border)
                settingRow("Default render mode") {
                    CVSegmentedControl(
                        options: AnalysisMode.allCases,
                        selection: Binding(get: { settings.mode }, set: { settings.setMode($0) }),
                        label: { $0 == .whole ? "Whole" : $0 == .subject ? "Subject" : "Both" }
                    )
                }
                Divider().overlay(theme.border)
                settingRow("Default GPS context") {
                    CVSegmentedControl(
                        options: GPSContextMode.allCases,
                        selection: Binding(get: { settings.gps }, set: { settings.setGPS($0) }),
                        label: { $0.rawValue.capitalized }
                    )
                }
                Divider().overlay(theme.border)
                settingRow("Existing sidecars") {
                    CVSegmentedControl(
                        options: ExistingPolicy.allCases,
                        selection: Binding(get: { settings.existing }, set: { settings.setExisting($0) }),
                        label: { $0.rawValue.capitalized }
                    )
                }
                Divider().overlay(theme.border)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Derivative cache")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text(settings.derivativeCachePath + (purgedCount.map { " — purged \($0) files" } ?? ""))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Purge…") { confirmPurge = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.danger)
                }
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("APPEARANCE")
            card {
                settingRow("Theme", caption: "Auto follows your macOS appearance.") {
                    CVSegmentedControl(
                        options: ThemeChoice.allCases,
                        selection: $themeChoice,
                        label: { $0.rawValue.capitalized }
                    )
                }
                Divider().overlay(theme.border)
                settingRow("Accent color", caption: "Pulled from the CupricAspect palette.") {
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

    private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("INTERFACE")
            card {
                settingRow("Nonlinear UI", caption: "Studio layout — coming soon.") {
                    Toggle("", isOn: .constant(false))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(true)
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ABOUT")
            card {
                HStack(spacing: 12) {
                    ApertureView(size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CupricAspect \(AppInfo.version)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text("XMP engine \(OwnedXMPSidecarEngine.engineVersion) · recipe \(OwnedXMPSidecarEngine.writerRecipeVersion)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textDim)
                    }
                    Spacer()
                }
            }
        }
    }

    private func settingRow(
        _ title: String,
        caption: String? = nil,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textFaint)
                }
            }
            Spacer()
            control()
        }
    }
}
