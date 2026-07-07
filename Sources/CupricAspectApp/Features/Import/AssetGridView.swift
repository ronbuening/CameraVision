import SwiftUI

/// Virtualized thumbnail grid over the asset queue (M3). `LazyVGrid` only
/// materializes visible cells, and each cell requests its thumbnail
/// asynchronously — the FR4-039 path to 5,000 assets without stalls.
struct AssetGridView: View {
    let records: [AssetRecord]
    let thumbnails: ThumbnailStore
    let onSelect: (AssetRecord) -> Void

    @Environment(\.cvTheme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 140), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(records) { record in
                    AssetGridCell(record: record, thumbnails: thumbnails)
                        .onTapGesture { onSelect(record) }
                }
            }
            .padding(10)
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border))
    }
}

private struct AssetGridCell: View {
    let record: AssetRecord
    let thumbnails: ThumbnailStore

    @Environment(\.cvTheme) private var theme
    @State private var thumbnail: Thumbnail?

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(decorative: thumbnail.image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(theme.panel2)
                            .overlay(
                                Text(record.fileExtension.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(theme.textFaint)
                            )
                    }
                }
                .frame(height: 82)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))

                stateDot
                    .padding(5)
            }
            Text(record.fileName)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textDim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .task(id: record.path) {
            thumbnail = thumbnails.cachedThumbnail(for: record.path)
            if thumbnail == nil {
                thumbnail = await thumbnails.thumbnail(for: record.path)
            }
        }
    }

    private var stateDot: some View {
        let color: Color = switch record.state {
        case .discovered: theme.textFaint
        case .analyzed: theme.accent.accent
        case .exported: theme.green
        case .xmpPresentExternal: theme.textDim
        case .xmpMissingWasExported, .failed: theme.danger
        }
        return Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
            .help(record.state.displayName)
    }
}
