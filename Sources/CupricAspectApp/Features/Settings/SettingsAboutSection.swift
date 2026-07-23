import AISidecarCore
import AppKit
import SwiftUI

struct SettingsAboutSection: View {
    @Binding var logSizeCapMB: Int

    @Environment(\.cvTheme) private var theme

    private var controls: SettingsControls { SettingsControls(theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controls.sectionLabel("ABOUT")
            controls.card {
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
}
