import AppKit
import SwiftUI

/// FR4-058 banner: backend-provided remediation guides without blocking non-analysis work.
struct RuntimeGuidanceBanner: View {
    @Bindable var guidance: RuntimeGuidanceModel

    @Environment(\.cvTheme) private var theme

    var body: some View {
        if guidance.needsAttention {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.danger)
                VStack(alignment: .leading, spacing: 4) {
                    switch guidance.status {
                    case .unreachable:
                        Text("\(guidance.backendDisplayName) isn't reachable at \(guidance.endpointDisplay)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text(guidance.backendGuidance.runtimeUnavailableMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textDim)
                        HStack(spacing: 12) {
                            if let title = guidance.backendGuidance.downloadButtonTitle,
                                let url = guidance.downloadURL
                            {
                                Button(title) {
                                    NSWorkspace.shared.open(url)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(theme.accent.accent)
                            }
                            recheckButton
                        }
                    case .noVisionModels:
                        Text("\(guidance.backendDisplayName) is running, but no installed model supports vision")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text(
                            guidance.backendGuidance.noModelsMessage
                                ?? "Analysis needs a vision-capable model before it can start."
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textDim)
                        HStack(spacing: 10) {
                            if !guidance.pullCommand.isEmpty {
                                Text(guidance.pullCommand)
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(theme.text)
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 8)
                                    .background(theme.panel2)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(guidance.pullCommand, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.textDim)
                                }
                                .buttonStyle(.plain)
                                .help("Copy pull command")
                            }
                            recheckButton
                        }
                    case .unknown, .checking, .ready:
                        EmptyView()
                    }
                }
                Spacer()
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.danger.opacity(0.08))
        }
    }

    private var recheckButton: some View {
        Button {
            guidance.check()
        } label: {
            HStack(spacing: 4) {
                if guidance.status == .checking {
                    ProgressView().controlSize(.mini)
                }
                Text("Re-check")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(theme.accent.accent)
    }
}
