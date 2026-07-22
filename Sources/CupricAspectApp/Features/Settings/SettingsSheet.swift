import AISidecarCore
import SwiftUI

/// The Settings sheet (design doc §6 Settings, FR4-056/057): model picker
/// from installed vision-capable Ollama tags, endpoint, run defaults written
/// through to the shared config.json, cache purge, appearance, and the app
/// version card.
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
                if settings.configuredModelUnavailable, !settings.visionTags.isEmpty {
                    Text(
                        "The configured model isn't installed (or isn't vision-capable) at this endpoint — pick another or `ollama pull` it."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(theme.danger)
                }
                emptyModelGuidance
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

    /// FR4-058/AC4-034: an empty vision-model list explains itself and names
    /// a starter model with its pull command instead of a bare empty picker.
    @ViewBuilder
    private var emptyModelGuidance: some View {
        if settings.visionTagState == .loaded, settings.visionTags.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("No installed model supports vision — analysis needs one.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.danger)
                HStack(spacing: 8) {
                    Text("ollama pull \(settings.model)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(theme.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("ollama pull \(settings.model)", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textDim)
                    }
                    .buttonStyle(.plain)
                    .help("Copy pull command")
                }
                Text("Run it in Terminal, then refresh the list.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textFaint)
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
                    Text(
                        "Environment overrides active: \(settings.environmentOverrides.joined(separator: ", ")) — these take precedence over the file."
                    )
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
                settingRow(
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
                settingRow(
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
                settingRow(
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
                Divider().overlay(theme.border)
                qualityGradingDefaults
                Divider().overlay(theme.border)
                settingRow(
                    "Model image size",
                    caption:
                        "Longest edge of the render sent to the model — smaller is faster, larger keeps fine detail."
                ) {
                    CVSegmentedControl(
                        options: ModelTuning.profileNamesBySize,
                        selection: Binding(get: { settings.profile }, set: { settings.setProfile($0) }),
                        label: { ModelTuning.imageSizeLabel(forProfileNamed: $0) }
                    )
                }
                Divider().overlay(theme.border)
                settingRow(
                    "Model context window",
                    caption:
                        "Ollama num_ctx tokens per call — match it to what the model supports; Default lets Ollama decide."
                ) {
                    contextWindowMenu
                }
                Divider().overlay(theme.border)
                settingRow(
                    "Model request timeout",
                    caption: "Seconds allowed for each Ollama request; increase this for slower cold starts."
                ) {
                    HStack(spacing: 0) {
                        settingsStepButton("−") {
                            settings.setModelTimeoutSeconds(max(1, settings.modelTimeoutSeconds - 30))
                        }
                        Text(modelTimeoutLabel)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.text)
                            .frame(width: 62)
                        settingsStepButton("+") {
                            settings.setModelTimeoutSeconds(settings.modelTimeoutSeconds + 30)
                        }
                    }
                    .background(theme.panel2)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
                }
                Divider().overlay(theme.border)
                settingRow(
                    "Model retry limit",
                    caption: "Additional attempts for timeouts, transport errors, and HTTP 5xx responses."
                ) {
                    HStack(spacing: 0) {
                        settingsStepButton("−") {
                            settings.setModelRetryLimit(max(0, settings.modelRetryLimit - 1))
                        }
                        Text("\(settings.modelRetryLimit)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.text)
                            .frame(width: 32)
                        settingsStepButton("+") {
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
                settingRow("Concurrency", caption: "Lower = less memory pressure.") {
                    HStack(spacing: 0) {
                        settingsStepButton("−") { settings.setConcurrency(settings.stageConcurrency - 1) }
                        Text("\(settings.stageConcurrency)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.text)
                            .frame(width: 32)
                        settingsStepButton("+") { settings.setConcurrency(settings.stageConcurrency + 1) }
                    }
                    .background(theme.panel2)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
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

    private var qualityGradingDefaults: some View {
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

            settingRow("Minimum confidence") {
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
                settingRow(
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
                        Text(
                            "XMP engine \(OwnedXMPSidecarEngine.engineVersion) · recipe \(OwnedXMPSidecarEngine.writerRecipeVersion)"
                        )
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textDim)
                    }
                    Spacer()
                }
                Divider().overlay(theme.border)
                // FR4-059: the diagnostic log location is visible, not buried.
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostic log")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text(GUILog.shared.logURL.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(theme.textFaint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("One previous generation is kept, so disk use stays under twice this size.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.textFaint)
                    }
                    Spacer()
                    Menu {
                        ForEach(GUILog.sizeCapChoicesMB, id: \.self) { capMB in
                            Button {
                                logSizeCapMB = capMB
                                GUILog.shared.updateSizeCap(bytes: capMB * 1_000_000)
                            } label: {
                                if capMB == logSizeCapMB {
                                    Label("\(capMB) MB", systemImage: "checkmark")
                                } else {
                                    Text("\(capMB) MB")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(logSizeCapMB) MB")
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
                    .help("Log file size cap; rotation applies on the next write")
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([GUILog.shared.logURL])
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.accent.accent)
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
        .help("Ollama num_ctx tokens requested per model call")
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

    private func settingsStepButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
