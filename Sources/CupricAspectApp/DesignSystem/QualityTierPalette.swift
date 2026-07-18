import AISidecarCore
import SwiftUI

/// One tier→color mapping for every quality badge (Review rows, change-plan
/// sheet, export report), so the surfaces cannot drift apart. Colors are
/// presentation only; tier values themselves always come from Core.
enum QualityTierPalette {
    static func color(for tier: QualityTier, theme: Theme) -> Color {
        switch tier {
        case .reject: theme.danger
        case .belowAverage: theme.accent.accent
        case .neutral: theme.textDim
        case .good, .excellent: theme.green
        }
    }
}
