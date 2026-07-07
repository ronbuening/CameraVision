import AppKit
import SwiftUI

/// FR4-058 banner: shown under the step rail when Ollama is unreachable or
/// has no vision-capable model. Everything except analysis works without
/// Ollama by design, so this guides rather than blocks.
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
                        Text("Ollama isn't reachable at \(guidance.endpointDisplay)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text("Analysis needs Ollama running locally. If it's installed, open the Ollama app (or run `ollama serve` in Terminal). If not, download it first — reviewing and exporting already-analyzed photos works without it.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textDim)
                        HStack(spacing: 12) {
                            Button("Download Ollama") {
                                if let url = URL(string: RuntimeGuidanceModel.downloadURL) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(theme.accent.accent)
                            recheckButton
                        }
                    case .noVisionModels:
                        Text("Ollama is running, but no installed model supports vision")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text("Analysis needs a vision-capable model. Install the starter model in Terminal, then re-check:")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textDim)
                        HStack(spacing: 10) {
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
