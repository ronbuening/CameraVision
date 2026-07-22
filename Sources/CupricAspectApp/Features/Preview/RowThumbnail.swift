import SwiftUI

/// Thumbnail cell reusing the M3 store; falls back to the extension label.
struct RowThumbnail: View {
    let path: String?
    let fallback: String
    let thumbnails: ThumbnailStore

    @Environment(\.cvTheme) private var theme
    @State private var thumbnail: Thumbnail?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(theme.panel2)
                    .overlay(
                        Text(fallback)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.textFaint)
                    )
            }
        }
        .frame(width: 70, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
        .task(id: path) {
            guard let path else { return }
            thumbnail = await thumbnails.thumbnail(for: path)
        }
    }
}
