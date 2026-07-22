import SwiftUI

/// Compact quality/status badge shared by review and export presentation.
struct QualityBadge: View {
    let text: String
    let color: Color
    var verticalPadding: CGFloat = 2

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
