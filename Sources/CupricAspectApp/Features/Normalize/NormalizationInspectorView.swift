import AISidecarCore
import AppKit
import SwiftUI

/// The Normalization Inspector (FR4-026 as amended, design doc §6/§7):
/// read-only per-keyword outcomes with explanations from the shared Core
/// explainer. No per-keyword decision controls exist — the engine has none.
struct NormalizationInspectorView: View {
    @Bindable var model: NormalizationModel
    var onWrite: () -> Void

    @Environment(\.cvTheme) private var theme
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if !model.contextRecords.isEmpty {
                contextResults
                    .padding(.top, 14)
            }

            if model.vocabularyIsStale {
                staleBanner
                    .padding(.top, 12)
            }

            filterBar
                .padding(.top, 16)

            inspectorTable
                .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 24, leading: 34, bottom: 40, trailing: 34))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle().fill(theme.green)
                Text("✓").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Keywords normalized")
                    .font(.system(size: 20, weight: .bold))
                    .kerning(-0.3)
                    .foregroundStyle(theme.text)
                Text("\(model.acceptedTotal) accepted · \(model.withheldTotal) withheld · \(model.skippedTotal) skipped — the engine decided; inspect and adjust vocabulary or context, then re-run.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textDim)
            }
            Spacer()
            actionButton("Import session…") { importSession() }
            actionButton("Save session only") { saveSession() }
            actionButton("Write normalized XMP", filled: true) { onWrite() }
        }
    }

    private func actionButton(_ label: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: filled ? .bold : .semibold))
                .foregroundStyle(filled ? .white : theme.textDim)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(filled ? AnyShapeStyle(theme.accent.accent) : AnyShapeStyle(.clear))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(filled ? .clear : theme.borderStrong))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context results (FR3-025 surfacing)

    private var contextResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESSION CONTEXT RESULTS")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(theme.textFaint)
            ForEach(model.contextRecords, id: \.originalText) { record in
                HStack(spacing: 8) {
                    Text(record.contextType.rawValue.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent.accent)
                    Text(record.originalText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.text)
                    if let path = record.matchedCanonicalPath {
                        Text("→ \(path)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(theme.green)
                    } else {
                        Text(record.unknownPolicyResult)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(theme.danger)
                    }
                    if record.conflictCount > 0 {
                        Text("\(record.conflictCount) conflicted")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.danger)
                    }
                    Text("· \(record.exportResult) · propagation \(record.propagationAllowed ? "on" : "off")")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textFaint)
                    Spacer()
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15))
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.border))
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Text("!")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(theme.accent.accent)
                .clipShape(Circle())
            Text("The vocabulary file changed since this session ran — re-run normalization to apply it (FR4-054).")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.text)
            Spacer()
        }
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
        .background(theme.accent.soft)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: 12) {
            CVSegmentedControl(
                options: NormalizationModel.OutcomeFilter.allCases,
                selection: $model.outcomeFilter,
                label: \.label
            )
            Menu {
                Button("All stages") { model.stageFilter = nil }
                Divider()
                ForEach(NormalizationDecisionStage.allCases, id: \.self) { stage in
                    Button(stageLabel(stage)) { model.stageFilter = stage }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(model.stageFilter.map(stageLabel) ?? "All stages")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("▾").font(.system(size: 9))
                }
                .foregroundStyle(theme.textDim)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.borderStrong))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Text("\(model.filteredSummaries.count) of \(model.summaries.count) keywords")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textFaint)
        }
    }

    private func stageLabel(_ stage: NormalizationDecisionStage) -> String {
        switch stage {
        case .directModelObservation: "Direct"
        case .userSessionContext: "User context"
        case .localAffinityPropagation: "Propagated"
        case .globalBackstopPropagation: "Backstop"
        case .phase2Fallback: "Fallback"
        }
    }

    // MARK: - Table

    private var maxSupport: Int {
        max(1, model.summaries.map(\.totalSupportUnits).max() ?? 1)
    }

    private var inspectorTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                columnLabel("KEYWORD", width: nil)
                Spacer()
                columnLabel("SUPPORT", width: 170)
                columnLabel("OUTCOME", width: 150)
                columnLabel("", width: 20)
            }
            .padding(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
            .background(theme.panel2)

            ForEach(model.filteredSummaries, id: \.keyword) { summary in
                Divider().overlay(theme.border)
                summaryRow(summary)
            }
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border))
    }

    private func columnLabel(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(theme.textFaint)
            .frame(width: width, alignment: .leading)
    }

    private func summaryRow(_ summary: KeywordDecisionSummary) -> some View {
        let isExpanded = expanded.contains(summary.keyword)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded { expanded.remove(summary.keyword) } else { expanded.insert(summary.keyword) }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Text(summary.keyword)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.text)
                            if summary.needsAttention {
                                Text("needs attention")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(theme.danger)
                                    .padding(.vertical, 1.5)
                                    .padding(.horizontal, 5)
                                    .background(theme.danger.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                        HStack(spacing: 9) {
                            Capsule()
                                .fill(theme.accent.accent)
                                .frame(width: max(6, 110 * CGFloat(summary.totalSupportUnits) / CGFloat(maxSupport)), height: 6)
                            Text("\(summary.assetCount)a · \(summary.totalSupportUnits)u")
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.textDim)
                        }
                        .frame(width: 170, alignment: .leading)
                        outcomeChips(summary)
                            .frame(width: 150, alignment: .leading)
                        Text(isExpanded ? "▾" : "▸")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textDim)
                            .frame(width: 20)
                    }
                    Text(whyLine(summary))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textFaint)
                        .lineLimit(isExpanded ? nil : 1)
                }
                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedDetail(summary)
            }
        }
    }

    private func outcomeChips(_ summary: KeywordDecisionSummary) -> some View {
        HStack(spacing: 5) {
            if summary.acceptedCount > 0 { outcomeChip("\(summary.acceptedCount)", theme.green, theme.greenSoft) }
            if summary.withheldCount > 0 { outcomeChip("\(summary.withheldCount)", theme.accent.accent, theme.accent.soft) }
            if summary.skippedCount > 0 { outcomeChip("\(summary.skippedCount)", theme.textDim, AnyShapeStyle(theme.panel2)) }
        }
    }

    private func outcomeChip(_ count: String, _ fg: Color, _ bg: some ShapeStyle) -> some View {
        Text(count)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(fg)
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .background(bg)
            .clipShape(Capsule())
    }

    private func whyLine(_ summary: KeywordDecisionSummary) -> String {
        var parts = summary.stages.map(NormalizationDecisionExplainer.text(for:))
        if !summary.governingRules.isEmpty {
            parts.append("rules: " + summary.governingRules.joined(separator: ", "))
        }
        for (reason, count) in summary.skipReasonCounts.sorted(by: { $0.value > $1.value }).prefix(3) {
            parts.append("×\(count) " + NormalizationDecisionExplainer.text(for: reason))
        }
        if !summary.conflictingCanonicalPaths.isEmpty {
            parts.append("conflicts with " + summary.conflictingCanonicalPaths.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private func expandedDetail(_ summary: KeywordDecisionSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(summary.assetDetails, id: \.assetID) { detail in
                HStack(spacing: 8) {
                    Text(detail.assetID)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(theme.textDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 260, alignment: .leading)
                    Text(detail.status.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(detail.status == .accepted ? theme.green : theme.textDim)
                    Text(NormalizationDecisionExplainer.text(for: detail.stage))
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textFaint)
                    if !detail.skipReasons.isEmpty {
                        Text(detail.skipReasons.map(\.rawValue).joined(separator: ", "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.danger)
                    }
                    if !detail.conflictingCanonicalPaths.isEmpty {
                        Text("⚑ " + detail.conflictingCanonicalPaths.joined(separator: ", "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.danger)
                    }
                    Spacer()
                }
            }
        }
        .padding(EdgeInsets(top: 2, leading: 16, bottom: 12, trailing: 16))
        .background(theme.panel2.opacity(0.5))
    }

    // MARK: - Panels

    private func saveSession() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "normalization-session.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? model.saveSession(to: url)
        }
    }

    private func importSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            try? model.importSession(from: url)
        }
    }
}
