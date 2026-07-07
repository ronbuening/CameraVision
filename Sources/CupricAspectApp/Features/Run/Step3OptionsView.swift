import AISidecarCore
import SwiftUI

/// Wizard Step 3 — "Review & options" (design doc §6 Step 3). RAW+JPEG pair
/// scope is export-only and arrives with M7's export options.
struct Step3OptionsView: View {
    let action: WizardAction
    @Bindable var options: AnalysisOptions
    @Bindable var runModel: AnalysisRunModel
    var importModel: FolderImportModel
    var normalizationModel: NormalizationModel?

    @Environment(\.cvTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Review & options")
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(theme.text)
            Text(action.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(theme.textDim)
                .padding(.top, 5)

            summaryCard
                .padding(.top, 20)

            HStack(spacing: 14) {
                renderModeCard
                modelCard
            }
            .padding(.top, 14)

            advancedCard
                .padding(.top, 14)

            if action == .normalize, let normalizationModel {
                SessionContextPanel(model: normalizationModel)
                    .padding(.top, 14)
            }
        }
        .padding(EdgeInsets(top: 26, leading: 34, bottom: 40, trailing: 34))
        .onAppear {
            options.loadResolvedDefaults()
            runModel.checkPreflight(
                options: options,
                recursive: importModel.recursive,
                outputDir: importModel.outputFolder?.path
            )
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            summaryRow("from", importModel.sourceFolder?.path ?? "—")
            summaryRow("to", importModel.outputFolder?.path ?? "\(importModel.sourceFolder?.path ?? "—") (in place)")
            summaryRow("", "\(importModel.assets.count) images detected")
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label.isEmpty ? "    " : label)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textFaint)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(label.isEmpty ? theme.textFaint : theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var renderModeCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("RENDER MODE")
            CVSegmentedControl(
                options: AnalysisMode.allCases,
                selection: $options.mode,
                label: { mode in
                    switch mode {
                    case .whole: "Whole Image"
                    case .subject: "Subject Only"
                    case .both: "Both"
                    }
                }
            )
        }
        .padding(EdgeInsets(top: 15, leading: 17, bottom: 15, trailing: 17))
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    private var modelCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Vision model")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(options.resolvedModel.isEmpty ? "—" : options.resolvedModel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            preflightBadge
        }
        .padding(EdgeInsets(top: 15, leading: 17, bottom: 15, trailing: 17))
        .frame(maxWidth: .infinity)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    @ViewBuilder
    private var preflightBadge: some View {
        switch runModel.preflight {
        case .unknown, .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("checking…")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textDim)
            }
        case .ready:
            HStack(spacing: 5) {
                Circle().fill(theme.green).frame(width: 7, height: 7)
                Text("ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.green)
            }
        case .failed(let message):
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(theme.danger).frame(width: 7, height: 7)
                        Text("unavailable")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.danger)
                    }
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textDim)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 320)
                }
                Button("Retry") {
                    runModel.checkPreflight(
                        options: options,
                        recursive: importModel.recursive,
                        outputDir: importModel.outputFolder?.path
                    )
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.accent.accent)
            }
        }
    }

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                options.advancedOpen.toggle()
            } label: {
                HStack(spacing: 9) {
                    Text("▶")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textDim)
                        .rotationEffect(.degrees(options.advancedOpen ? 90 : 0))
                    Text("Advanced flags")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text("gps · existing sidecars · concurrency")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textFaint)
                    Spacer()
                }
                .padding(EdgeInsets(top: 13, leading: 17, bottom: 13, trailing: 17))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if options.advancedOpen {
                Divider().overlay(theme.border)
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 16) {
                    GridRow {
                        advancedGroup("GPS CONTEXT") {
                            CVSegmentedControl(
                                options: GPSContextMode.allCases,
                                selection: $options.gps,
                                label: { $0.rawValue.capitalized }
                            )
                        }
                        advancedGroup("EXISTING SIDECARS") {
                            CVSegmentedControl(
                                options: ExistingPolicy.allCases,
                                selection: $options.existing,
                                label: { $0.rawValue.capitalized }
                            )
                        }
                    }
                    GridRow {
                        advancedGroup("CONCURRENCY") {
                            HStack(spacing: 0) {
                                stepButton("−") { options.concurrency = max(1, options.concurrency - 1) }
                                Text("\(options.concurrency)")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .frame(width: 32)
                                stepButton("+") { options.concurrency = min(8, options.concurrency + 1) }
                            }
                            .background(theme.panel2)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
                        }
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
                .padding(EdgeInsets(top: 14, leading: 17, bottom: 18, trailing: 17))
            }
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
    }

    private func advancedGroup(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
            content()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(theme.textFaint)
    }

    private func stepButton(_ glyph: String, action: @escaping () -> Void) -> some View {
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
