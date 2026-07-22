import AISidecarCore
import SwiftUI

struct AdvancedOptionsCard: View {
    @Bindable var options: AnalysisOptions

    @Environment(\.cvTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                options.advancedOpen.toggle()
            } label: {
                HStack(spacing: 9) {
                    Text("▶")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textDim)
                        .rotationEffect(.degrees(options.advancedOpen ? 90 : 0))
                    Text("Advanced flags")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text(
                        "gps · existing .ai.json · existing xmp · concurrency · image size · context window · quality scan"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textFaint)
                    Spacer()
                }
                .padding(EdgeInsets(top: 13, leading: 17, bottom: 13, trailing: 17))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if options.advancedOpen {
                Divider().overlay(theme.border)
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 16) {
                    GridRow {
                        advancedGroup("GPS CONTEXT") {
                            CVSegmentedControl(
                                options: GPSContextMode.allCases,
                                selection: $options.gps,
                                label: { $0.rawValue.capitalized }
                            )
                        }
                        advancedGroup("EXISTING .AI.JSON SIDECARS") {
                            CVSegmentedControl(
                                options: ExistingPolicy.allCases,
                                selection: $options.existing,
                                label: { $0.rawValue.capitalized }
                            )
                        }
                    }
                    GridRow {
                        advancedGroup("EXISTING XMP") {
                            CVSegmentedControl(
                                options: XMPConflictPolicy.allCases,
                                selection: $options.xmpConflictPolicy,
                                label: xmpPolicyLabel
                            )
                        }
                        advancedGroup("CONCURRENCY") {
                            HStack(spacing: 0) {
                                stepButton("−") { options.concurrency = max(1, options.concurrency - 1) }
                                Text("\(options.concurrency)")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .frame(width: 32)
                                stepButton("+") { options.concurrency = min(8, options.concurrency + 1) }
                            }
                            .background(theme.panel2)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
                        }
                    }
                    GridRow {
                        advancedGroup("MODEL IMAGE SIZE") {
                            CVSegmentedControl(
                                options: ModelTuning.profileNamesBySize,
                                selection: $options.profile,
                                label: { ModelTuning.imageSizeLabel(forProfileNamed: $0) }
                            )
                        }
                        advancedGroup("MODEL CONTEXT WINDOW") {
                            contextWindowMenu
                        }
                    }
                    GridRow {
                        advancedGroup("QUALITY SCAN") {
                            CVSegmentedControl(
                                options: QualityScanMode.allCases,
                                selection: $options.qualityScanMode,
                                label: { $0.wizardLabel }
                            )
                            .disabled(!options.assessQuality)
                            .opacity(options.assessQuality ? 1 : 0.5)
                        }
                    }
                }
                .padding(EdgeInsets(top: 14, leading: 17, bottom: 18, trailing: 17))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Existing .ai.json: the tool's own analysis files, not your .xmp.")
                    Text("Merge keeps keywords already in your .xmp; Backup & Merge writes a .xmp.bak first.")
                    Text(
                        "Image size: longest edge of the render sent to the model — smaller is faster, larger keeps fine detail."
                    )
                    Text(
                        "Context window: Ollama num_ctx tokens per call — match it to what the model supports; Default lets Ollama decide."
                    )
                    Text(Step3OptionsView.qualityScanFootnote)
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.textFaint)
                .padding(EdgeInsets(top: 0, leading: 17, bottom: 16, trailing: 17))
            }
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    private func advancedGroup(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
            content()
        }
    }

    private var contextWindowMenu: some View {
        Menu {
            ForEach(ModelTuning.contextWindowChoices, id: \.self) { tokens in
                Button {
                    options.contextWindow = tokens
                } label: {
                    if tokens == options.contextWindow {
                        Label(ModelTuning.contextWindowLabel(tokens), systemImage: "checkmark")
                    } else {
                        Text(ModelTuning.contextWindowLabel(tokens))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(ModelTuning.contextWindowLabel(options.contextWindow))
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(theme.textFaint)
    }

    private func xmpPolicyLabel(_ policy: XMPConflictPolicy) -> String {
        switch policy {
        case .fail: "Fail"
        case .merge: "Merge"
        case .backupAndMerge: "Backup & Merge"
        }
    }

    private func stepButton(_ glyph: String, action: @escaping () -> Void) -> some View {
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
