import AppKit
import SwiftUI

struct SettingsModelSection: View {
    @Bindable var settings: SettingsModel

    @Environment(\.cvTheme) private var theme

    private var controls: SettingsControls { SettingsControls(theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controls.sectionLabel("MODEL")
            controls.card {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vision backend")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text("Choose the local runtime used for image analysis.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textFaint)
                    }
                    Spacer()
                    backendPicker
                }
                Divider().overlay(theme.border)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vision model tag")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text(
                            settings.selectedBackendID == .ollama
                                ? "Installed Ollama models with the vision capability."
                                : "Models available through \(settings.selectedBackendDisplayName)."
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textFaint)
                    }
                    Spacer()
                    modelPicker
                }
                if settings.configuredModelUnavailable, !settings.visionTags.isEmpty {
                    Text(configuredModelUnavailableMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.danger)
                }
                emptyModelGuidance
                if settings.usesEndpoint {
                    Divider().overlay(theme.border)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(settings.selectedBackendDisplayName) endpoint")
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
    }

    private var configuredModelUnavailableMessage: String {
        if settings.selectedBackendID == .ollama {
            return
                "The configured model isn't installed (or isn't vision-capable) at this endpoint — pick another or `ollama pull` it."
        }
        return "The configured model isn't available (or isn't vision-capable) through this backend — pick another."
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
                    Text(
                        settings.selectedBackendGuidance?.pullCommand(for: settings.model)
                            ?? "Install the configured model"
                    )
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(theme.panel2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            settings.selectedBackendGuidance?.pullCommand(for: settings.model)
                                ?? "Install the configured model",
                            forType: .string
                        )
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

    private var backendPicker: some View {
        Menu {
            ForEach(settings.backendOptions) { option in
                Button {
                    settings.setModelBackend(option.id)
                } label: {
                    let label = "\(option.displayName) — \(option.availabilityText)"
                    if option.id == settings.modelBackend {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(settings.selectedBackendDisplayName)
                    .font(.system(size: 12, weight: .semibold))
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
}
