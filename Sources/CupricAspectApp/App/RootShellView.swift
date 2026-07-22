import SwiftUI

/// Persisted appearance and shell preferences (FR4-041/042).
/// Key names match the design prototype's localStorage keys.
enum PreferenceKeys {
    static let nonlinear = "cupricaspect.nonlinear"
    static let theme = "cupricaspect.theme"
    static let accent = "cupricaspect.accent"
    static let logSizeCapMB = "cupricaspect.logSizeCapMB"
}

/// Root of the window: applies the theme override, resolves design tokens for
/// the effective color scheme, and switches between the Wizard and Studio
/// shells (FR4-040). Both shells bind to the same persisted state, so
/// switching loses nothing.
struct RootShellView: View {
    @State private var flow = WizardFlowModel()
    @AppStorage(PreferenceKeys.theme) private var themeChoice: ThemeChoice = .light
    @AppStorage(PreferenceKeys.accent) private var accentChoice: AccentChoice = .copper
    @AppStorage(PreferenceKeys.nonlinear) private var nonlinear = false

    var body: some View {
        // Wizard-first MVP (FR4-040 v0.6 scoping): the Studio shell and the
        // `cupricaspect.nonlinear` preference stay gated behind
        // FeatureFlags.studioUI until milestone M9 lands. With the flag off the
        // preference is never consulted, so the window is always the Wizard.
        ThemedContainer(accent: accentChoice) {
            if FeatureFlags.studioUI, nonlinear {
                StudioShellView(flow: flow)
            } else {
                WizardShellView(flow: flow)
            }
        }
        .preferredColorScheme(themeChoice.preferredColorScheme)
        .frame(minWidth: 1040, minHeight: 720)
        .task {
            await flow.activate()
        }
        .onChange(of: flow.runModel.phase) { _, phase in
            flow.handleRunPhase(phase)
        }
        .onChange(of: flow.normalizationModel.phase) { _, phase in
            flow.handleNormalizationPhase(phase)
        }
        .onChange(of: flow.exportModel.phase) { _, phase in
            flow.handleExportPhase(phase)
        }
        .onChange(of: flow.reviewModel.session?.session.sessionID) { _, _ in
            flow.handleReviewSessionChange()
        }
        .onChange(of: flow.importModel.sourceFolder?.path) { oldPath, newPath in
            flow.handleSourcePathChange(oldPath: oldPath, newPath: newPath)
        }
    }
}

/// Resolves the token set for the effective color scheme (which already
/// reflects the theme override or, under `auto`, the live system appearance)
/// and injects it as `\.cvTheme`.
private struct ThemedContainer<Content: View>: View {
    let accent: AccentChoice
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .environment(\.cvTheme, Theme.resolve(colorScheme: colorScheme, accent: accent))
    }
}
