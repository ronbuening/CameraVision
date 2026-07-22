import AISidecarCore
import SwiftUI

struct RunModelPickerCard: View {
    @Bindable var options: AnalysisOptions
    @Bindable var runModel: AnalysisRunModel
    var importModel: FolderImportModel
    @Bindable var visionTagsModel: VisionTagsModel

    @Environment(\.cvTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Vision model")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                modelPicker
                Text("this run only — Settings sets the saved default")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textFaint)
                if let status = modelStatusText {
                    Text(status)
                        .font(.system(size: 10.5))
                        .foregroundStyle(modelStatusIsWarning ? theme.danger : theme.textFaint)
                        .lineLimit(2)
                }
            }
            Spacer()
            preflightBadge
        }
        .padding(EdgeInsets(top: 15, leading: 17, bottom: 15, trailing: 17))
        .frame(maxWidth: .infinity)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    private var modelPicker: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    selectModelOverride(nil)
                } label: {
                    let label =
                        options.resolvedModel.isEmpty
                        ? "Use Settings default" : "Use Settings default: \(options.resolvedModel)"
                    if options.modelOverride == nil {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
                Divider()
                ForEach(visionTagsModel.models) { model in
                    Button {
                        selectModelOverride(model.id)
                    } label: {
                        if model.id == options.effectiveModel {
                            Label(model.displayName, systemImage: "checkmark")
                        } else {
                            Text(model.displayName)
                        }
                    }
                }
                if visionTagsModel.tags.isEmpty {
                    Button("No vision models found") {}.disabled(true)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(options.effectiveModel.isEmpty ? "—" : options.effectiveModel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("▾").font(.system(size: 9))
                }
                .foregroundStyle(theme.text)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .frame(maxWidth: 280, alignment: .leading)
                .background(theme.panel2)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.border))
            }
            .menuStyle(.borderlessButton)

            Button {
                Task { await forceVisionTagRefresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textDim)
            }
            .buttonStyle(.plain)
            .help("Refresh installed models")
        }
    }

    private var modelStatusText: String? {
        switch visionTagsModel.state {
        case .idle:
            nil
        case .loading:
            "loading installed models…"
        case .loaded where visionTagsModel.tags.isEmpty:
            "No installed vision models found at this endpoint."
        case .loaded
        where !options.effectiveModel.isEmpty && !visionTagsModel.tags.contains(options.effectiveModel):
            "\(options.effectiveModel) is not installed or is not vision-capable at this endpoint."
        case .loaded:
            nil
        case .failed(let message):
            "Model list unavailable: \(message)"
        }
    }

    private var modelStatusIsWarning: Bool {
        switch visionTagsModel.state {
        case .loaded:
            !visionTagsModel.tags.isEmpty
                && !options.effectiveModel.isEmpty
                && !visionTagsModel.tags.contains(options.effectiveModel)
        case .failed:
            true
        default:
            false
        }
    }

    @ViewBuilder
    private var preflightBadge: some View {
        switch runModel.preflight {
        case .unknown, .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("checking…")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textDim)
            }
        case .ready(let backendID, let backendDisplayName, _, _, _):
            HStack(spacing: 5) {
                Circle().fill(theme.green).frame(width: 7, height: 7)
                Text(backendID == .ollama ? "ready" : "\(backendDisplayName) ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.green)
            }
        case .failed(let backendID, let backendDisplayName, let message):
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(theme.danger).frame(width: 7, height: 7)
                        Text(backendID == .ollama ? "unavailable" : "\(backendDisplayName) unavailable")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.danger)
                    }
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textDim)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 320)
                }
                Button("Retry") {
                    runPreflight()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.accent.accent)
            }
        }
    }

    private func selectModelOverride(_ tag: String?) {
        options.modelOverride = tag
        runPreflight()
    }

    private func runPreflight() {
        runModel.checkPreflight(
            options: options,
            recursive: importModel.recursive,
            outputDir: importModel.outputFolder?.path
        )
    }

    private func forceVisionTagRefresh() async {
        do {
            let configuration = try options.buildConfiguration(
                recursive: importModel.recursive,
                outputDir: importModel.outputFolder?.path
            )
            let descriptor = try await runModel.resolveBackend(for: configuration)
            await visionTagsModel.refresh(descriptor: descriptor, configuration: configuration)
        } catch {
            visionTagsModel.fail(message: (error as? SidecarError)?.message ?? error.localizedDescription)
        }
    }
}
