import SwiftUI

/// Wizard Step 4 — the working screen (design doc §6 Step 4): aperture hero,
/// live progress from the CORE-1 hook, elapsed/rate stats, cancel.
struct Step4WorkingView: View {
    let action: WizardAction
    @Bindable var runModel: AnalysisRunModel

    @Environment(\.cvTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ApertureView(size: 196, running: runModel.isRunning, spin: true)

            Text(action.workingTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.text)
                .padding(.top, 26)
            Text(runModel.currentFile.isEmpty ? "preparing…" : runModel.currentFile)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textDim)
                .padding(.top, 6)

            progressBar
                .frame(width: 460)
                .padding(.top, 22)

            statsRow
                .padding(.top, 20)

            Button {
                runModel.cancel()
            } label: {
                Text(runModel.phase == .cancelling ? "Cancelling…" : "Cancel")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.textDim)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 18)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.borderStrong))
            }
            .buttonStyle(.plain)
            .disabled(runModel.phase == .cancelling)
            .padding(.top, 24)

            // B0-6 pause story (FR4-010): cancel is a safe pause — finished
            // sidecars stay on disk and the next Start skips them (CORE-3).
            Text("Progress is kept — analyzed photos stay done. Start again to resume where you left off.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textFaint)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var progressBar: some View {
        VStack(spacing: 7) {
            HStack {
                Text("\(runModel.done) / \(runModel.total)")
                    .foregroundStyle(theme.textDim)
                Spacer()
                Text("\(Int((runModel.progressFraction * 100).rounded()))%")
                    .foregroundStyle(theme.accent.accent)
            }
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(theme.panel2)
                    barberFill
                        .frame(width: max(6, proxy.size.width * runModel.progressFraction))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .animation(.linear(duration: 0.2), value: runModel.progressFraction)
                }
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.border))
            }
            .frame(height: 9)
        }
    }

    /// Accent gradient with a scrolling barber-pole sheen (static under
    /// reduce-motion, FR4-043).
    @ViewBuilder
    private var barberFill: some View {
        let base = LinearGradient(
            colors: [theme.accent.accent, theme.progressTail],
            startPoint: .leading, endPoint: .trailing
        )
        if reduceMotion {
            Rectangle().fill(base)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.7) / 0.7
                Rectangle()
                    .fill(base)
                    .overlay(
                        GeometryReader { proxy in
                            let stripe = 34.0
                            HStack(spacing: stripe / 2) {
                                ForEach(0..<Int(proxy.size.width / stripe) + 3, id: \.self) { _ in
                                    Rectangle()
                                        .fill(.white.opacity(0.14))
                                        .frame(width: stripe / 2)
                                }
                            }
                            .rotationEffect(.degrees(-20))
                            .offset(x: -stripe + phase * stripe)
                        }
                    )
            }
        }
    }

    private var statsRow: some View {
        // Elapsed and rate depend on wall-clock time, not observed state, so
        // they need a periodic timeline to re-render while the run is live.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 26) {
                stat("Elapsed", elapsedText)
                stat(
                    "Rate", runModel.secondsPerImage > 0 ? String(format: "%.1f s/img", runModel.secondsPerImage) : "—")
                stat("Model", modelText)
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(theme.textFaint)
    }

    private var modelText: String {
        if case .ready(_, _, let model, _, _) = runModel.preflight { return model }
        return "—"
    }

    private var elapsedText: String {
        guard let startedAt = runModel.startedAt else { return "0s" }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textDim)
        }
    }
}
