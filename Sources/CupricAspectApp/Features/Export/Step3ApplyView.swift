import AISidecarCore
import AppKit
import SwiftUI

/// Wizard Step 3 for the Apply action (design doc §7 Apply): pick a saved
/// normalization session and show its recorded facts. No model runs, no
/// re-analysis — the frozen-session writer does the rest (FR4-012b).
struct Step3ApplyView: View {
    @Binding var session: NormalizationSessionDocument?
    @Binding var sessionPath: String?

    @Environment(\.cvTheme) private var theme
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Apply Prior Session")
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(theme.text)
            Text("Re-apply a saved normalization session — no model runs, no re-analysis.")
                .font(.system(size: 14))
                .foregroundStyle(theme.textDim)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 9) {
                Text("SESSION FILE")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(theme.textFaint)
                HStack(spacing: 10) {
                    Text(sessionPath.map { ($0 as NSString).lastPathComponent } ?? "No session selected")
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(sessionPath == nil ? theme.textFaint : theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { pickSession() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent.accent)
                }
                if let session {
                    Divider().overlay(theme.border)
                    HStack(spacing: 22) {
                        stat("\(session.sourceAssets.count) images")
                        stat("\(session.perAssetDecisions.count) keyword decisions")
                        stat("\(session.perAssetDecisions.count { $0.status == .accepted }) accepted")
                        stat("vocabulary \(String(session.vocabulary.sha256.prefix(8)))…")
                    }
                }
                if let loadError {
                    Text(loadError)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.danger)
                }
            }
            .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
            .background(theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border))
            .padding(.top, 22)

            Text("The write is fronted by a dry-run change plan; sources are verified against the identities recorded in the session.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textFaint)
                .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 26, leading: 34, bottom: 40, trailing: 34))
    }

    private func stat(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.textDim)
    }

    private func pickSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                session = try NormalizationSessionReader().read(from: url.path)
                sessionPath = url.path
                loadError = nil
            } catch {
                loadError = (error as? SidecarError)?.message ?? error.localizedDescription
            }
        }
    }
}
