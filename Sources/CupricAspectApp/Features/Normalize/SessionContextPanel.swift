import AISidecarCore
import AppKit
import SwiftUI

/// The engine's only per-run human input (FR4-052, design doc §6/§7):
/// Subject / Habitat / Event with per-field propagation gates (off by
/// default), the unknown-context policy, and the vocabulary-file picker.
struct SessionContextPanel: View {
    @Bindable var model: NormalizationModel
    @Environment(\.cvTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SESSION CONTEXT")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(theme.textFaint)
            Text("Tell the batch what you know — applied only with explicit gates, never inferred. Conflicting photos are always protected.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textDim)

            contextField("SUBJECT", text: $model.subject, propagation: $model.allowSubjectPropagation)
            contextField("HABITAT", text: $model.habitat, propagation: $model.allowHabitatPropagation)
            contextField("EVENT", text: $model.event, propagation: $model.allowEventPropagation)

            // Vocabulary surface (custom-vocabulary picker + unknown-policy)
            // is gated until the vocabulary tooling ships; when hidden no file
            // can be chosen, so the run keeps the built-in defaults (the
            // observed-tags catalog and the built-in unknown policy).
            if FeatureFlags.vocabularyUI {
                Divider().overlay(theme.border)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("IF NOT IN VOCABULARY")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(theme.textFaint)
                        CVSegmentedControl(
                            options: UnknownSessionContextPolicy.allCases,
                            selection: $model.unknownPolicy,
                            label: { $0 == .reject ? "Reject" : "Write unnormalized" }
                        )
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("VOCABULARY")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(theme.textFaint)
                        HStack(spacing: 8) {
                            Text(model.vocabularyPath.map { ($0 as NSString).lastPathComponent } ?? "bundled starter vocabulary")
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(model.vocabularyPath == nil ? theme.textDim : theme.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if model.vocabularyPath != nil {
                                Button("Bundled") { model.vocabularyPath = nil }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(theme.textDim)
                            }
                            Button("Choose…") { pickVocabulary() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.accent.accent)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    private func contextField(_ label: String, text: Binding<String>, propagation: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(theme.textFaint)
                .frame(width: 58, alignment: .leading)
            TextField("", text: text, prompt: Text("optional").foregroundStyle(theme.textFaint))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.text)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(theme.panel2)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.border))
            Toggle("", isOn: propagation)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(theme.accent.accent)
                .disabled(text.wrappedValue.isEmpty)
            Text("apply to all non-conflicting photos")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textFaint)
        }
    }

    private func pickVocabulary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.vocabularyPath = url.path
        }
    }
}
