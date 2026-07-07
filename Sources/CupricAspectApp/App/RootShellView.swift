import SwiftUI

/// Persisted appearance and shell preferences (FR4-041/042).
/// Key names match the design prototype's localStorage keys.
enum PreferenceKeys {
    static let nonlinear = "cupricaspect.nonlinear"
    static let theme = "cupricaspect.theme"
    static let accent = "cupricaspect.accent"
}

/// Root of the window: applies the theme override, resolves design tokens for
/// the effective color scheme, and switches between the Wizard and Studio
/// shells (FR4-040). Both shells bind to the same persisted state, so
/// switching loses nothing.
struct RootShellView: View {
    @AppStorage(PreferenceKeys.nonlinear) private var nonlinear = false
    @AppStorage(PreferenceKeys.theme) private var themeChoice: ThemeChoice = .light
    @AppStorage(PreferenceKeys.accent) private var accentChoice: AccentChoice = .copper

    var body: some View {
        ThemedContainer(accent: accentChoice) {
            Group {
                if nonlinear {
                    StudioShellView()
                } else {
                    WizardShellView()
                }
            }
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
