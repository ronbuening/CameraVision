import AISidecarCore
import SwiftUI

/// App and engine version constants surfaced in the UI (plan M0).
/// The app version becomes single-sourced with the CLI's in packaging WI
/// D5; until then it mirrors `AISidecarCommand`'s placeholder.
enum AppInfo {
    static let version = "0.0.0 (dev)"
}

/// M0 placeholder content shared by both shells: branding, version info,
/// and working appearance/shell controls. Feature milestones (M1+) replace
/// this as the shells' real content arrives.
struct AboutView: View {
    var showsCloseButton = false

    @AppStorage(PreferenceKeys.theme) private var themeChoice: ThemeChoice = .light
    @AppStorage(PreferenceKeys.accent) private var accentChoice: AccentChoice = .copper
    @Environment(\.cvTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var apertureRunning = false

    var body: some View {
        VStack(spacing: 0) {
            if showsCloseButton {
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.textDim)
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16))
            }
            Spacer()

            ApertureView(size: 96, running: apertureRunning, spin: true)
                .onTapGesture { apertureRunning.toggle() }
                .help("Click to preview the working animation")

            Text("CupricAspect")
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(theme.text)
                .padding(.top, 20)
            Text("AI photo tagging")
                .font(.system(size: 12))
                .foregroundStyle(theme.textFaint)
                .padding(.top, 2)

            versionCard
                .padding(.top, 24)

            appearanceControls
                .padding(.top, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.winBg)
    }

    private var versionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            versionRow("App", AppInfo.version)
            versionRow("XMP engine", OwnedXMPSidecarEngine.engineVersion)
            versionRow("Writer recipe", OwnedXMPSidecarEngine.writerRecipeVersion)
        }
        .padding(16)
        .frame(width: 360)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border))
    }

    private func versionRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(theme.textFaint)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textDim)
        }
    }

    private var appearanceControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Text("Theme")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                CVSegmentedControl(
                    options: ThemeChoice.allCases,
                    selection: $themeChoice,
                    label: { $0.rawValue.capitalized }
                )
            }
            Divider().overlay(theme.border)
            HStack(spacing: 10) {
                Text("Accent")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
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
            Divider().overlay(theme.border)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nonlinear UI")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text("Studio layout — coming soon.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textFaint)
                }
                Spacer()
                // Studio ships in milestone M9 (FR4-040 v0.6 MVP scoping);
                // until then the preference is inert and the switch disabled.
                Toggle("", isOn: .constant(false))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(true)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border))
    }
}

/// Design-system segmented control: panel-2 track, accent-filled selected
/// segment (design doc Section 3.5). Native pickers don't match the design.
struct CVSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    @Environment(\.cvTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(selected ? .white : theme.textDim)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(selected ? theme.accent.accent : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(theme.panel2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
    }
}
