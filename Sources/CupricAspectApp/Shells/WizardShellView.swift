import SwiftUI

/// Wizard shell (design doc Section 6): 46px title bar, content area, footer
/// nav bar. M0 renders the chrome with the About placeholder as content; the
/// step rail and step screens arrive with the feature milestones.
struct WizardShellView: View {
    @Environment(\.cvTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(theme.border)

            AboutView()

            Divider().overlay(theme.border)
            footerBar
        }
        .background(theme.winBg)
    }

    private var titleBar: some View {
        HStack(spacing: 9) {
            ApertureView(size: 20)
            Text("CupricAspect")
                .font(.system(size: 13, weight: .bold))
                .kerning(-0.1)
                .foregroundStyle(theme.text)
            Spacer()
        }
        .padding(.leading, 84) // clear the native traffic lights under .hiddenTitleBar
        .padding(.trailing, 14)
        .frame(height: 46)
        .background(theme.titlebar)
    }

    private var footerBar: some View {
        HStack(spacing: 14) {
            Text("Wizard shell — the guided flow arrives with milestone M2.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textFaint)
            Spacer()
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 13)
        .background(theme.titlebar)
    }
}
