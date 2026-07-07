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
    @AppStorage(PreferenceKeys.theme) private var themeChoice: ThemeChoice = .light
    @AppStorage(PreferenceKeys.accent) private var accentChoice: AccentChoice = .copper

    var body: some View {
        // Wizard-first MVP (FR4-040 v0.6 scoping): the Studio shell and the
        // `cupricaspect.nonlinear` preference activate in milestone M9.
        ThemedContainer(accent: accentChoice) {
            WizardShellView()
        }
        .preferredColorScheme(themeChoice.preferredColorScheme)
        .frame(minWidth: 1040, minHeight: 720)
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
