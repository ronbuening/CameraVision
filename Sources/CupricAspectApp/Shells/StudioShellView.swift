import SwiftUI

/// Studio shell (design doc Section 7): 46px title bar with centered window
/// title, 214px sidebar with workflow navigation, scrolling main area. M0
/// renders the chrome with static nav items and the About placeholder; the
/// views behind the nav arrive with the feature milestones.
struct StudioShellView: View {
    @Environment(\.cvTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(theme.border)
            HStack(spacing: 0) {
                sidebar
                Divider().overlay(theme.border)
                AboutView()
            }
        }
        .background(theme.winBg)
    }

    private var titleBar: some View {
        ZStack {
            Text("CupricAspect — About")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(theme.titlebar)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                ApertureView(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CupricAspect")
                        .font(.system(size: 14, weight: .bold))
                        .kerning(-0.1)
                        .foregroundStyle(theme.text)
                    Text("AI photo tagging")
                        .font(.system(size: 10.5, weight: .medium))
                        .kerning(0.2)
                        .foregroundStyle(theme.textFaint)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 16)

            Text("WORKFLOW")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.9)
                .foregroundStyle(theme.textFaint)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            navItem("Analyze", systemImage: "camera.aperture", active: true)
            navItem("Normalize", systemImage: "line.3.horizontal.decrease", active: false)
            navItem("Write XMP", systemImage: "tag", active: false)
            navItem("Apply Prior Session", systemImage: "arrow.clockwise", active: false)

            Spacer()
            Divider().overlay(theme.border).padding(.horizontal, 6).padding(.vertical, 8)
            navItem("Settings", systemImage: "slider.horizontal.3", active: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(width: 214)
        .background(theme.sidebar)
    }

    private func navItem(_ label: String, systemImage: String, active: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .frame(width: 17)
            Text(label)
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .foregroundStyle(active ? theme.accent.accent : theme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(active ? theme.accent.soft : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
