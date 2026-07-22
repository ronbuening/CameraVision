import SwiftUI

/// Shared visual building blocks for Settings sections.
struct SettingsControls {
    let theme: Theme

    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(theme.textFaint)
    }

    func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    func settingRow<Control: View>(
        _ title: String,
        caption: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textFaint)
                }
            }
            Spacer()
            control()
        }
    }

    func settingsStepButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
