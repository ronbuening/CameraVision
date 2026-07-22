import AISidecarCore
import SwiftUI

/// Post-write export report (FR4-035b/c): per-target status, backups,
/// validation, restorations, and structured errors, plus the engine identity
/// and application instructions recorded in the report itself.
struct ExportReportView: View {
    let report: XMPExportReport

    @Environment(\.cvTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXPORT REPORT")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(theme.textFaint)
            let qualitySummary = ExportModel.qualitySummary(for: report)
            if !qualitySummary.isEmpty {
                Text(
                    "Quality: \(qualitySummary.gradedTargetCount) graded · \(qualitySummary.ungradedTargetCount) ungraded · \(qualitySummary.writtenScalarCount) scalars written · \(qualitySummary.skippedScalarCount) skipped by policy"
                )
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.textDim)
            }
            ForEach(Array(report.targetReports.enumerated()), id: \.offset) { _, target in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(target.plan.targetRelativePath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        statusBadge(target.status)
                        if target.backup != nil {
                            Text("backup ✓")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.green)
                        }
                        if let validation = target.validation {
                            Text(validation.valid ? "validated ✓" : "validation failed — restored")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(validation.valid ? theme.green : theme.danger)
                        }
                        if !target.errors.isEmpty {
                            Text(target.errors.map(\.code.rawValue).joined(separator: ", "))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.danger)
                        }
                        Spacer()
                    }
                    qualityReportRows(target)
                }
            }
            Text(
                "Engine \(report.engine.engineName) \(report.engine.engineVersion) · recipe \(report.engine.writerRecipeVersion)"
            )
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(theme.textFaint)
            ForEach(report.applicationInstructions, id: \.self) { instruction in
                Text(instruction)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textDim)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.border))
    }

    @ViewBuilder
    private func qualityReportRows(_ target: XMPExportTargetReport) -> some View {
        if let quality = ExportModel.qualityPresentation(for: target) {
            HStack(spacing: 6) {
                if let tier = quality.tier {
                    QualityBadge(
                        text: tier.rawValue,
                        color: QualityTierPalette.color(for: tier, theme: theme),
                        verticalPadding: 1.5
                    )
                } else if quality.ungradedReason != nil {
                    QualityBadge(text: "ungraded", color: theme.accent.accent, verticalPadding: 1.5)
                }
                Spacer()
            }
            ForEach(quality.scalars) { scalar in
                Text(
                    "\(scalar.field): \(scalar.resultExistingValue ?? "—") → \(scalar.resultResultingValue ?? "—") · \(scalar.action.rawValue)"
                )
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(scalar.action == .skipExisting ? theme.accent.accent : theme.textDim)
            }
            ForEach(Array(quality.explanations.enumerated()), id: \.offset) { _, explanation in
                Text(explanation)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textFaint)
                    .textSelection(.enabled)
            }
        }
    }

    private func statusBadge(_ status: XMPExportTargetStatus) -> some View {
        let color: Color =
            switch status {
            case .written, .created: theme.green
            case .unchanged, .dryRun: theme.textDim
            case .failed, .interrupted: theme.danger
            }
        return Text(status.rawValue)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.vertical, 1.5)
            .padding(.horizontal, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
