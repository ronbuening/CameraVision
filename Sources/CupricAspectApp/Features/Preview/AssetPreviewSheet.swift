import SwiftUI

/// Large-preview sheet for one asset: whole image (pipeline derivative when
/// cached), subject-isolated derivative with instance count and selection
/// indication when available (FR4-014 groundwork), and sidecar facts.
struct AssetPreviewSheet: View {
    let record: AssetRecord
    let outputDir: String?

    @Environment(\.cvTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var details: AssetPreviewDetails?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(record.relativePath)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(record.state.displayName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.textDim)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 7)
                    .background(theme.panel2)
                    .clipShape(Capsule())
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.textDim)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
            .background(theme.titlebar)

            Divider().overlay(theme.border)

            if let details {
                content(details)
            } else {
                VStack(spacing: 14) {
                    ApertureView(size: 64, running: true, spin: true)
                    Text("Loading preview…")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textFaint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 940, height: 620)
        .background(theme.winBg)
        .task {
            let sourcePath = record.path
            let sidecarPath = AssetQueueDerivation.rawSidecarPath(
                sourcePath: record.path,
                relativePath: record.relativePath,
                outputDir: outputDir
            )
            details = await Task.detached(priority: .userInitiated) {
                AssetPreviewDetails.load(sourcePath: sourcePath, rawSidecarPath: sidecarPath)
            }.value
        }
    }

    private func content(_ details: AssetPreviewDetails) -> some View {
        HStack(alignment: .top, spacing: 14) {
            imagePanel(
                title: "WHOLE IMAGE",
                image: details.fullImage,
                emptyText: "Preview unavailable for this format."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                imagePanel(
                    title: "SUBJECT ISOLATED",
                    image: details.subjectImage,
                    emptyText: details.instanceCount == nil
                        ? "No subject isolation recorded — run analysis in Subject or Both mode."
                        : "Subject derivative not in the cache (purged or rendered elsewhere)."
                )
                .frame(width: 300, height: 260)

                if let instanceCount = details.instanceCount {
                    HStack(spacing: 6) {
                        Text("\(instanceCount) instance\(instanceCount == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.accent.accent)
                        if !details.selectedInstanceIndices.isEmpty {
                            Text("· selected \(details.selectedInstanceIndices.map(String.init).joined(separator: ", "))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.textDim)
                        }
                        if let status = details.isolationStatus {
                            Text("· \(status)")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textFaint)
                        }
                    }
                }

                factRow("Model runs", details.modelRunCount == 0 ? "none" : "\(details.modelRunCount)")
                if !details.sidecarErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SIDECAR ERRORS")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(theme.textFaint)
                        ForEach(details.sidecarErrors.prefix(4), id: \.self) { error in
                            Text(error)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(theme.danger)
                                .lineLimit(2)
                        }
                    }
                }
                Spacer()
            }
            .frame(width: 300)
        }
        .padding(14)
    }

    private func imagePanel(title: String, image: CGImage?, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(theme.textFaint)
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text(emptyText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textFaint)
                        .multilineTextAlignment(.center)
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(theme.panel2)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.border))
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.textDim)
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(theme.text)
        }
    }
}
