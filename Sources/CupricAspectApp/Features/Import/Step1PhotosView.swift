import SwiftUI
import UniformTypeIdentifiers

/// Wizard Step 1 — "Choose your photos" (design doc §6, Step 1), plus the M1
/// asset-queue table that appears once a folder is scanned.
struct Step1PhotosView: View {
    @Bindable var model: FolderImportModel
    @Environment(\.cvTheme) private var theme

    /// One fileImporter per view branch: SwiftUI silently drops all but one
    /// `.fileImporter` attached to the same view, so both pickers share a
    /// single presentation keyed by target.
    enum PickTarget: Identifiable {
        case source
        case output
        var id: Self { self }
    }

    @State private var pickTarget: PickTarget?
    @State private var displayMode: QueueDisplay = .grid
    @State private var previewRecord: AssetRecord?
    @State private var thumbnails = ThumbnailStore()

    enum QueueDisplay: CaseIterable {
        case grid
        case list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose your photos")
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(theme.text)
            Text("Everything runs locally through Ollama — your images never leave the machine.")
                .font(.system(size: 14))
                .foregroundStyle(theme.textDim)
                .padding(.top, 5)

            dropZone
                .padding(.top, 22)

            HStack(spacing: 14) {
                outputCard
                recursiveCard
            }
            .padding(.top, 18)

            Text("Supported: nef · cr3 · cr2 · arw · raf · orf · rw2 · dng · jpg · heic · tif · png")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textFaint)
                .padding(.top, 16)

            if !model.assets.isEmpty || !model.scanErrors.isEmpty {
                queueSection
                    .padding(.top, 18)
            }
        }
        .padding(EdgeInsets(top: 26, leading: 34, bottom: 40, trailing: 34))
        .fileImporter(
            isPresented: Binding(
                get: { pickTarget != nil },
                set: { if !$0 { pickTarget = nil } }
            ),
            allowedContentTypes: [.folder]
        ) { result in
            defer { pickTarget = nil }
            guard case .success(let url) = result else { return }
            switch pickTarget {
            case .source: model.chooseSource(url)
            case .output: model.chooseOutput(url)
            case nil: break
            }
        }
        .sheet(item: $previewRecord) { record in
            AssetPreviewSheet(record: record, outputDir: model.outputFolder?.path)
        }
    }

    private var hasSource: Bool { model.sourceFolder != nil }

    private var dropZone: some View {
        Button {
            pickTarget = .source
        } label: {
            VStack(spacing: 0) {
                ApertureView(size: 64, running: model.scanning, spin: true)
                Text(model.sourceFolder?.path ?? "Drop a folder of photos here")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(hasSource ? theme.accent.accent : theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 16)
                Text(hasSource ? "\(model.summary) · click to change" : "or click to browse")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textFaint)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(38)
            .background(hasSource ? AnyShapeStyle(theme.accent.soft) : AnyShapeStyle(theme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        hasSource ? theme.accent.accent : theme.borderStrong,
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
            )
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return false
            }
            model.chooseSource(url)
            return true
        }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("OUTPUT FOLDER")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(theme.textFaint)
            HStack(spacing: 10) {
                Text(model.outputFolder?.path ?? "Same as input folder")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(model.outputFolder == nil ? theme.textDim : theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.outputFolder != nil {
                    smallButton("Same as input") { model.chooseOutput(nil) }
                }
                smallButton("Choose…", filled: true) { pickTarget = .output }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border))
    }

    private var recursiveCard: some View {
        HStack(spacing: 9) {
            Toggle("", isOn: Binding(
                get: { model.recursive },
                set: { _ in model.toggleRecursive() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(theme.accent.accent)
            Text("Include subfolders")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.text)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border))
    }

    private func smallButton(_ label: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(filled ? theme.text : theme.textDim)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(filled ? AnyShapeStyle(theme.panel2) : AnyShapeStyle(.clear))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.borderStrong))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Queue table

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Queue")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.textDim)
                Text("\(model.filteredAssets.count) of \(model.assets.count)")
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent.accent)
                if !model.scanErrors.isEmpty {
                    Text("· \(model.scanErrors.count) skipped (\(model.presentErrorCodes.joined(separator: ", ")))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.danger)
                }
                Rectangle().fill(theme.border).frame(height: 1)
                CVSegmentedControl(
                    options: QueueDisplay.allCases,
                    selection: $displayMode,
                    label: { $0 == .grid ? "Grid" : "List" }
                )
            }

            switch displayMode {
            case .grid:
                AssetGridView(records: model.filteredAssets, thumbnails: thumbnails) { record in
                    previewRecord = record
                }
                .frame(minHeight: 220, maxHeight: 380)
            case .list:
                queueTable
            }
        }
    }

    private var queueTable: some View {
        Table(model.filteredAssets) {
                TableColumn("State") { record in
                    stateBadge(record.state)
                }
                .width(min: 120, ideal: 170)
                TableColumn("File") { record in
                    Text(record.relativePath)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                TableColumn("Type") { record in
                    Text(record.fileExtension.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent.accent)
                }
                .width(min: 46, ideal: 56)
                TableColumn("Size") { record in
                    Text(ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(theme.textDim)
                }
                .width(min: 60, ideal: 80)
            }
            .frame(minHeight: 220, maxHeight: 340)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border))
    }

    private func stateBadge(_ state: AssetQueueState) -> some View {
        let color: Color = switch state {
        case .discovered: theme.textDim
        case .analyzed: theme.accent.accent
        case .exported: theme.green
        case .xmpPresentExternal: theme.textDim
        case .xmpMissingWasExported: theme.danger
        case .failed: theme.danger
        }
        return Text(state.displayName)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
