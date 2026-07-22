import AISidecarCore
import SwiftUI

struct SettingsConfigurationSection: View {
    @Bindable var settings: SettingsModel
    @Binding var purgedCount: Int?
    @Binding var confirmPurge: Bool

    @Environment(\.cvTheme) private var theme

    private var controls: SettingsControls { SettingsControls(theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading
            controls.card {
                configFileBlock
                runDefaults
                Divider().overlay(theme.border)
                SettingsQualityGradingSection(settings: settings)
                Divider().overlay(theme.border)
                modelDisplayDefaults
                Divider().overlay(theme.border)
                modelExecutionDefaults
                Divider().overlay(theme.border)
                cacheRow
            }
        }
    }

    private var sectionHeading: some View {
        HStack(spacing: 8) {
            controls.sectionLabel("CONFIGURATION")
            Text("— defaults saved to config.json, shared with the CLI")
                .font(.system(size: 11))
                .foregroundStyle(theme.textFaint)
        }
    }

    @ViewBuilder
    private var configFileBlock: some View {
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
            Text(
                "Environment overrides active: \(settings.environmentOverrides.joined(separator: ", ")) — these take precedence over the file."
            )
            .font(.system(size: 10.5))
            .foregroundStyle(theme.accent.accent)
        }
        Divider().overlay(theme.border)
    }

    @ViewBuilder
    private var runDefaults: some View {
        controls.settingRow("Default render mode") {
            CVSegmentedControl(
                options: AnalysisMode.allCases,
                selection: Binding(get: { settings.mode }, set: { settings.setMode($0) }),
                label: { $0 == .whole ? "Whole" : $0 == .subject ? "Subject" : "Both" }
            )
        }
        Divider().overlay(theme.border)
        controls.settingRow("Default GPS context") {
            CVSegmentedControl(
                options: GPSContextMode.allCases,
                selection: Binding(get: { settings.gps }, set: { settings.setGPS($0) }),
                label: { $0.rawValue.capitalized }
            )
        }
        Divider().overlay(theme.border)
        controls.settingRow(
            "Existing .ai.json sidecars",
            caption: "The tool's own .ai.json analysis files, not your .xmp."
        ) {
            CVSegmentedControl(
                options: ExistingPolicy.allCases,
                selection: Binding(get: { settings.existing }, set: { settings.setExisting($0) }),
                label: { $0.rawValue.capitalized }
            )
        }
        Divider().overlay(theme.border)
        controls.settingRow(
            "Existing XMP",
            caption: "Merge keeps keywords already in your .xmp; Backup & Merge writes a .xmp.bak first."
        ) {
            CVSegmentedControl(
                options: XMPConflictPolicy.allCases,
                selection: Binding(
                    get: { settings.xmpConflictPolicy },
                    set: { settings.setXMPConflictPolicy($0) }
                ),
                label: xmpPolicyLabel
            )
        }
        Divider().overlay(theme.border)
        controls.settingRow(
            "Quality scan",
            caption: Step3OptionsView.qualityScanFootnote
        ) {
            CVSegmentedControl(
                options: QualityScanMode.allCases,
                selection: Binding(
                    get: { settings.qualityScanMode },
                    set: { settings.setQualityScanMode($0) }
                ),
                label: { $0.wizardLabel }
            )
        }
    }

    @ViewBuilder
    private var modelDisplayDefaults: some View {
        controls.settingRow(
            "Model image size",
            caption: "Longest edge of the render sent to the model — smaller is faster, larger keeps fine detail."
        ) {
            CVSegmentedControl(
                options: ModelTuning.profileNamesBySize,
                selection: Binding(get: { settings.profile }, set: { settings.setProfile($0) }),
                label: { ModelTuning.imageSizeLabel(forProfileNamed: $0) }
            )
        }
        if settings.supportedTuningKnobs.contains(.contextWindow) {
            Divider().overlay(theme.border)
            controls.settingRow(
                "Model context window",
                caption: settings.selectedBackendID == .ollama
                    ? "Ollama num_ctx tokens per call — match it to what the model supports; Default lets Ollama decide."
                    : "Context-window tokens per call — Default lets the selected backend decide."
            ) {
                contextWindowMenu
            }
        }
    }

    @ViewBuilder
    private var modelExecutionDefaults: some View {
        if settings.supportedTuningKnobs.contains(.timeout) {
            controls.settingRow(
                "Model request timeout",
                caption: settings.selectedBackendID == .ollama
                    ? "Seconds allowed for each Ollama request; increase this for slower cold starts."
                    : "Seconds allowed for each backend request; increase this for slower cold starts."
            ) {
                HStack(spacing: 0) {
                    controls.settingsStepButton("−") {
                        settings.setModelTimeoutSeconds(max(1, settings.modelTimeoutSeconds - 30))
                    }
                    Text(modelTimeoutLabel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .frame(width: 62)
                    controls.settingsStepButton("+") {
                        settings.setModelTimeoutSeconds(settings.modelTimeoutSeconds + 30)
                    }
                }
                .background(theme.panel2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
            }
            Divider().overlay(theme.border)
        }
        if settings.supportedTuningKnobs.contains(.retryLimit) {
            controls.settingRow(
                "Model retry limit",
                caption: settings.selectedBackendID == .ollama
                    ? "Additional attempts for timeouts, transport errors, and HTTP 5xx responses."
                    : "Additional attempts for timeout and transient backend failures."
            ) {
                HStack(spacing: 0) {
                    controls.settingsStepButton("−") {
                        settings.setModelRetryLimit(max(0, settings.modelRetryLimit - 1))
                    }
                    Text("\(settings.modelRetryLimit)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .frame(width: 32)
                    controls.settingsStepButton("+") {
                        let (next, overflowed) = settings.modelRetryLimit.addingReportingOverflow(1)
                        if !overflowed {
                            settings.setModelRetryLimit(next)
                        }
                    }
                }
                .background(theme.panel2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
            }
            Divider().overlay(theme.border)
        }
        controls.settingRow("Concurrency", caption: "Lower = less memory pressure.") {
            HStack(spacing: 0) {
                controls.settingsStepButton("−") { settings.setConcurrency(settings.stageConcurrency - 1) }
                Text("\(settings.stageConcurrency)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .frame(width: 32)
                controls.settingsStepButton("+") { settings.setConcurrency(settings.stageConcurrency + 1) }
            }
            .background(theme.panel2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
        }
    }

    private var cacheRow: some View {
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

    private var contextWindowMenu: some View {
        Menu {
            ForEach(ModelTuning.contextWindowChoices, id: \.self) { tokens in
                Button {
                    settings.setModelContextWindow(tokens)
                } label: {
                    if tokens == settings.modelContextWindow {
                        Label(ModelTuning.contextWindowLabel(tokens), systemImage: "checkmark")
                    } else {
                        Text(ModelTuning.contextWindowLabel(tokens))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(ModelTuning.contextWindowLabel(settings.modelContextWindow))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
        .help(
            settings.selectedBackendID == .ollama
                ? "Ollama num_ctx tokens requested per model call"
                : "Context-window tokens requested per model call"
        )
    }

    private func xmpPolicyLabel(_ policy: XMPConflictPolicy) -> String {
        switch policy {
        case .fail: "Fail"
        case .merge: "Merge"
        case .backupAndMerge: "Backup & Merge"
        }
    }

    private var modelTimeoutLabel: String {
        "\(settings.modelTimeoutSeconds.formatted(.number.precision(.fractionLength(0...3)))) s"
    }
}
