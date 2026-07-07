import AISidecarCore
import SwiftUI

/// The FR4-029 dry-run gate: every write is fronted by this plan review.
/// Shows per-target adds, same-base-name grouping with the session's pair
/// scope (FR4-034, AC4-018), failed targets with error codes (FR4-035a —
/// excluded from the write), and the compatibility notes (FR4-036–038).
struct ChangePlanSheet: View {
    @Bindable var export: ExportModel

    @Environment(\.cvTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Change plan")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.text)
                Text("dry run — nothing has been written yet")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textFaint)
                Spacer()
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
            .background(theme.titlebar)

            Divider().overlay(theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(export.writableTargets, id: \.targetXMPPath) { plan in
                        targetRow(plan)
                    }
                    if !export.failedTargets.isEmpty || !export.planFailures.isEmpty {
                        failuresSection
                    }
                    compatibilityCard
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(theme.border)

            HStack(spacing: 14) {
                Text(footerSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textDim)
                Spacer()
                Button("Cancel") {
                    export.cancelPlan()
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.textDim)
                Button {
                    export.confirmWrite()
                    dismiss()
                } label: {
                    Text("Write \(export.writableTargets.count) sidecar\(export.writableTargets.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 18)
                        .background(theme.accent.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(export.writableTargets.isEmpty)
                .opacity(export.writableTargets.isEmpty ? 0.4 : 1)
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
            .background(theme.titlebar)
        }
        .frame(width: 760, height: 560)
        .background(theme.winBg)
    }

    private var footerSummary: String {
        let flat = export.writableTargets.reduce(0) { $0 + $1.flatKeywordsToAdd.count }
        let hierarchical = export.writableTargets.reduce(0) { $0 + $1.hierarchicalKeywordsToAdd.count }
        var text = "\(flat) flat · \(hierarchical) hierarchical keywords to add"
        let excluded = export.failedTargets.count + export.planFailures.count
        if excluded > 0 {
            text += " · \(excluded) excluded (see failures)"
        }
        return text
    }

    private func targetRow(_ plan: XMPChangePlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(plan.targetRelativePath)
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if plan.sourceMembers.count > 1 {
                    Text("\(plan.sourceMembers.count)-file group · \(plan.pairScope.rawValue)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent.accent)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(theme.accent.soft)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("+\(plan.flatKeywordsToAdd.count) flat · +\(plan.hierarchicalKeywordsToAdd.count) hier")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textDim)
            }
            if !plan.flatKeywordsToAdd.isEmpty {
                Text(plan.flatKeywordsToAdd.map(\.term).joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textFaint)
                    .lineLimit(2)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.border))
    }

    private var failuresSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXCLUDED FROM THIS WRITE")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(theme.danger)
            ForEach(export.failedTargets, id: \.targetXMPPath) { plan in
                failureLine(
                    path: plan.targetRelativePath,
                    codes: plan.failures.map(\.code.rawValue)
                )
            }
            ForEach(Array(export.planFailures.enumerated()), id: \.offset) { _, failure in
                failureLine(path: failure.sidecarPath, codes: [failure.error.code.rawValue])
            }
            Text("Resolve or leave excluded — the write proceeds without them (FR4-035a).")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textFaint)
        }
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.danger.opacity(0.4)))
    }

    private func failureLine(path: String, codes: [String]) -> some View {
        HStack(spacing: 8) {
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(codes.joined(separator: ", "))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.danger)
            Spacer()
        }
    }

    /// FR4-036–038: compatibility profiles and post-export instructions.
    private var compatibilityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COMPATIBILITY")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(theme.textFaint)
            Text("Lightroom Classic: select the already-imported photos and run Metadata → Read Metadata from Files to pick up sidecar changes. Hierarchical keywords use lr:HierarchicalSubject.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textDim)
            Text("Capture One: behavior follows Preferences → Metadata (Auto Sync Sidecar XMP: Load / Full Sync). Flat keywords use dc:subject; Lightroom-style hierarchy may not behave identically.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textDim)
            Text("Writes go through the owned XMP engine with deterministic backups, source-hash checks, and post-write validation — no external tools.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textFaint)
        }
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.border))
    }
}

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
            ForEach(Array(report.targetReports.enumerated()), id: \.offset) { _, target in
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
            }
            Text("Engine \(report.engine.engineName) \(report.engine.engineVersion) · recipe \(report.engine.writerRecipeVersion)")
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

    private func statusBadge(_ status: XMPExportTargetStatus) -> some View {
        let color: Color = switch status {
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
