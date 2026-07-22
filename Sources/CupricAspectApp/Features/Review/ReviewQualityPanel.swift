import AISidecarCore
import SwiftUI

struct ReviewQualityPanel: View {
    let quality: ReviewAssetQualityPresentation

    @Environment(\.cvTheme) private var theme

    @ViewBuilder
    var body: some View {
        if !quality.records.isEmpty || !quality.issueDiagnostics.isEmpty || quality.ungradedReason != nil {
            Divider().overlay(theme.border)
            VStack(alignment: .leading, spacing: 8) {
                Text("QUALITY ASSESSMENT · READ ONLY")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(theme.textFaint)
                ForEach(Array(quality.records.enumerated()), id: \.offset) { _, record in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            "\(record.role.rawValue) · overall \(record.overall.rawValue) · confidence \(record.confidence.rawValue)"
                        )
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                        FlowLayout(spacing: 6) {
                            ForEach(
                                QualityAssessmentRecord.Criterion.allCases.filter { record.criteria[$0] != nil },
                                id: \.rawValue
                            ) { criterion in
                                if let level = record.criteria[criterion] {
                                    Text("\(criterion.rawValue): \(level.rawValue)")
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(theme.textDim)
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 6)
                                        .background(theme.panel2)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        if !record.strengths.isEmpty {
                            Text("strengths: " + record.strengths.joined(separator: " · "))
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.green)
                        }
                        if !record.concerns.isEmpty {
                            Text("concerns: " + record.concerns.joined(separator: " · "))
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.accent.accent)
                        }
                    }
                }
                if let ungradedReason = quality.ungradedReason {
                    Text(ungradedReason)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.accent.accent)
                }
                ForEach(Array(quality.issueDiagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    Text("diagnostic: \(diagnostic)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.accent.accent)
                }
            }
        }
    }
}
