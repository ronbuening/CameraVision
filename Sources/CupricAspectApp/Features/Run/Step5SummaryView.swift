import SwiftUI

/// Wizard Step 5 — run summary. This is the M2 stand-in for the real
/// candidate-review screen (M4); every number comes from the completed run.
struct Step5SummaryView: View {
    let outcome: RunOutcome
    @Environment(\.cvTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(outcome.failed == 0 ? theme.green : theme.accent.accent)
                    Text(outcome.failed == 0 ? "✓" : "!")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(outcome.interrupted ? "Analysis stopped" : "Analysis complete")
                        .font(.system(size: 20, weight: .bold))
                        .kerning(-0.3)
                        .foregroundStyle(theme.text)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textDim)
                }
            }

            if !outcome.errorSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FAILURES BY ERROR CODE")
                        .font(.system(size: 10.5, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(theme.textFaint)
                    ForEach(outcome.errorSummaries, id: \.self) { summary in
                        Text(summary)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.danger)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border))
                .padding(.top, 18)
            }

            HStack(spacing: 8) {
                ApertureView(size: 22)
                Text(
                    "Per-image candidate review arrives with milestone M4 — the .ai.json sidecars are on disk and ready for it."
                )
                .font(.system(size: 12))
                .foregroundStyle(theme.textFaint)
            }
            .padding(.top, 18)
        }
        .padding(EdgeInsets(top: 24, leading: 34, bottom: 40, trailing: 34))
    }

    private var subtitle: String {
        var parts: [String] = []
        if outcome.written > 0 { parts.append("\(outcome.written) analyzed") }
        if outcome.skipped > 0 { parts.append("\(outcome.skipped) skipped (existing)") }
        if outcome.failed > 0 { parts.append("\(outcome.failed) failed") }
        if parts.isEmpty { parts.append("nothing to do") }
        return parts.joined(separator: " · ")
    }
}
