import SwiftUI

/// The four Wizard actions (design doc §6 Step 2). Only `analyze` is
/// available in M2; the rest enable as their milestones land (write/apply →
/// M7, normalize → M6) — visible but disabled per the design's card layout.
enum WizardAction: String, CaseIterable, Sendable {
    case analyze
    case write
    case normalize
    case apply

    var title: String {
        switch self {
        case .analyze: "Analyze only"
        case .write: "Analyze & write XMP"
        case .normalize: "Analyze, Normalize, and Write XMP"
        case .apply: "Apply a normalization session"
        }
    }

    var subtitle: String {
        switch self {
        case .analyze: "Write auditable .ai.json sidecars. No XMP is created — safest first pass."
        case .write: "Analyze, then export accepted keywords straight to .xmp for Lightroom Classic & Capture One."
        case .normalize: "The full pipeline — reconcile keywords batch-wide under your vocabulary and consensus rules, then write normalized XMP."
        case .apply: "Re-apply a saved normalization session — no model runs, no re-analysis."
        }
    }

    /// Milestone gating; a disabled card shows "arrives with <milestone>".
    var availableMilestone: String? {
        switch self {
        case .analyze, .normalize: nil
        case .write, .apply: "M7"
        }
    }

    var isAvailable: Bool { availableMilestone == nil }

    var workingTitle: String {
        switch self {
        case .analyze: "Analyzing images…"
        case .write: "Analyzing & preparing XMP…"
        case .normalize: "Analyzing & normalizing…"
        case .apply: "Applying session…"
        }
    }
}

/// Wizard Step 2 — "What should CupricAspect do?" (design doc §6 Step 2).
struct Step2ActionView: View {
    @Binding var selection: WizardAction?
    @Environment(\.cvTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What should CupricAspect do?")
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(theme.text)
            Text("Every path starts by analyzing your images with the local vision model.")
                .font(.system(size: 14))
                .foregroundStyle(theme.textDim)
                .padding(.top, 5)

            VStack(spacing: 12) {
                actionCard(.analyze, icon: analyzeIcon)
                actionCard(.write, icon: writeIcon)
                actionCard(.normalize, icon: normalizeIcon)
            }
            .padding(.top, 22)

            HStack(spacing: 4) {
                Spacer()
                Text("Already have a saved plan?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textFaint)
                Text("Apply a normalization session → arrives with M7")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textFaint.opacity(0.7))
                Spacer()
            }
            .padding(.top, 16)
        }
        .padding(EdgeInsets(top: 26, leading: 34, bottom: 40, trailing: 34))
    }

    private func actionCard(_ action: WizardAction, icon: some View) -> some View {
        let selected = selection == action
        let enabled = action.isAvailable
        return Button {
            if enabled { selection = action }
        } label: {
            HStack(alignment: .top, spacing: 16) {
                icon
                    .frame(width: 26, height: 26)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(action.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.text)
                        if let milestone = action.availableMilestone {
                            Text("arrives with \(milestone)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textFaint)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(theme.panel2)
                                .clipShape(Capsule())
                        }
                    }
                    Text(action.subtitle)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(theme.textDim)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(selected ? theme.accent.accent : .clear)
                    Circle()
                        .strokeBorder(selected ? theme.accent.accent : theme.border, lineWidth: 2)
                    if selected {
                        Text("✓")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
            .background(selected ? AnyShapeStyle(theme.accent.soft) : AnyShapeStyle(theme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(selected ? theme.accent.accent : theme.border, lineWidth: 2)
            )
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // Line icons per design §4, drawn from the prototype's SVG paths.
    private var analyzeIcon: some View {
        ZStack {
            Circle().strokeBorder(theme.accent.accent, lineWidth: 1.8)
            Circle().fill(theme.accent.accent).frame(width: 6, height: 6)
        }
    }

    private var writeIcon: some View {
        Image(systemName: "tag")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(theme.accent.accent)
    }

    private var normalizeIcon: some View {
        VStack(alignment: .leading, spacing: 4.5) {
            ForEach([26.0, 18.0, 22.0], id: \.self) { width in
                Capsule().fill(theme.accent.accent).frame(width: width, height: 2.4)
            }
        }
    }
}
