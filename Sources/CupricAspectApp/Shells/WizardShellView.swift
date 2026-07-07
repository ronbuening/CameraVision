import SwiftUI

/// Wizard shell (design doc Section 6): 46px title bar, step rail, content
/// area, footer nav. M1 implements Step 1 (Photos) for real; Steps 2–5 are
/// labeled placeholders that arrive with their milestones (M2 · M4 · M6 · M7).
struct WizardShellView: View {
    @Environment(\.cvTheme) private var theme
    @State private var importModel = FolderImportModel()
    @State private var step = 1
    @State private var showAbout = false
    @AppStorage(PreferenceKeys.theme) private var themeChoice: ThemeChoice = .light
    @Environment(\.colorScheme) private var colorScheme

    private static let stepLabels = ["Photos", "What to do", "Options", "Working", "Review"]

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(theme.border)
            stepRail
            ScrollView {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.winBg)
            Divider().overlay(theme.border)
            footerBar
        }
        .background(theme.winBg)
        .sheet(isPresented: $showAbout) {
            AboutView(showsCloseButton: true)
                .frame(width: 440, height: 620)
        }
        .task {
            // Dev/UI-test hook: auto-import a folder passed via environment.
            // No effect in normal launches; not a shipped preference.
            if let path = ProcessInfo.processInfo.environment["CUPRIC_IMPORT_PATH"] {
                importModel.chooseSource(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
    }

    // MARK: - Chrome

    private var titleBar: some View {
        HStack(spacing: 9) {
            ApertureView(size: 20, running: importModel.scanning, spin: true)
            Text("CupricAspect")
                .font(.system(size: 13, weight: .bold))
                .kerning(-0.1)
                .foregroundStyle(theme.text)
            Spacer()
            Button {
                themeChoice = colorScheme == .dark ? .light : .dark
            } label: {
                Text(colorScheme == .dark ? "☀" : "☾")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textDim)
                    .frame(width: 30, height: 24)
                    .background(theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.border))
            }
            .buttonStyle(.plain)
            .help("Toggle appearance")
            Button {
                showAbout = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textDim)
                    .frame(width: 30, height: 24)
                    .background(theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.border))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.leading, 84) // clear the native traffic lights under .hiddenTitleBar
        .padding(.trailing, 14)
        .frame(height: 46)
        .background(theme.titlebar)
    }

    private var stepRail: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { index in
                railItem(index)
                if index < 5 {
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 34, bottom: 6, trailing: 34))
        .background(theme.winBg)
    }

    private func railItem(_ index: Int) -> some View {
        let done = step > index
        let current = step == index
        return HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(done ? theme.green : (current ? theme.accent.accent : theme.panel2))
                Text(done ? "✓" : String(index))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(done || current ? .white : theme.textFaint)
            }
            .frame(width: 24, height: 24)
            Text(Self.stepLabels[index - 1])
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(done ? theme.textDim : (current ? theme.text : theme.textFaint))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case 1:
            Step1PhotosView(model: importModel)
        default:
            placeholder(for: step)
        }
    }

    private func placeholder(for step: Int) -> some View {
        let milestone = ["", "", "M2", "M2", "M2", "M4"][step]
        return VStack(spacing: 14) {
            ApertureView(size: 64)
            Text(Self.stepLabels[step - 1])
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.text)
            Text("This step arrives with milestone \(milestone).")
                .font(.system(size: 13))
                .foregroundStyle(theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
    }

    // MARK: - Footer

    private var backEnabled: Bool { step > 1 && step != 4 }
    private var primaryEnabled: Bool { step == 1 && importModel.sourceFolder != nil }

    private var footerHint: String {
        if step == 1 {
            return importModel.sourceFolder == nil ? "Choose a folder to continue" : importModel.summary
        }
        return "This step arrives with a later milestone."
    }

    private var footerBar: some View {
        HStack(spacing: 14) {
            Button {
                if backEnabled { step -= 1 }
            } label: {
                Text("‹ Back")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 16)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.borderStrong))
            }
            .buttonStyle(.plain)
            .opacity(backEnabled ? 1 : 0.35)
            .disabled(!backEnabled)

            Text(footerHint)
                .font(.system(size: 12))
                .foregroundStyle(theme.textFaint)

            Spacer()

            Button {
                if primaryEnabled { step = min(5, step + 1) }
            } label: {
                Text("Continue")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 22)
                    .background(theme.accent.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .opacity(primaryEnabled ? 1 : 0.4)
            .disabled(!primaryEnabled)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 13)
        .background(theme.titlebar)
    }
}
