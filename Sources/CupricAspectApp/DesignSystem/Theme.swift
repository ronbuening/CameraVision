import SwiftUI

// Design tokens from agent_docs/07-cupricaspect-gui-design.md Section 3.
// Values mirror the CupricAspect design handoff exactly; change them only
// against a revision of that document.

/// User-selectable theme. `auto` follows the macOS system appearance.
enum ThemeChoice: String, CaseIterable {
    case light
    case dark
    case auto

    /// The color scheme to force app-wide, or nil to follow the system.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .auto: nil
        }
    }
}

/// User-selectable accent palette. `amber` is shown to users as "Brass".
enum AccentChoice: String, CaseIterable {
    case copper
    case amber
    case patina

    var displayName: String {
        switch self {
        case .copper: "Copper"
        case .amber: "Brass"
        case .patina: "Patina"
        }
    }

    /// Fixed swatch color for pickers (theme-independent by design).
    var swatch: Color {
        switch self {
        case .copper: Color(hex: 0xBE6A20)
        case .amber: Color(hex: 0xC08A1C)
        case .patina: Color(hex: 0x2E8B57)
        }
    }
}

/// Accent trio resolved for a concrete color scheme.
struct AccentPalette {
    let accent: Color
    let hover: Color
    let soft: Color

    static func resolve(_ choice: AccentChoice, dark: Bool) -> AccentPalette {
        switch (choice, dark) {
        case (.copper, false):
            AccentPalette(accent: Color(hex: 0xBE6A20), hover: Color(hex: 0xA55A16), soft: Color(hex: 0xBE6A20, opacity: 0.14))
        case (.copper, true):
            AccentPalette(accent: Color(hex: 0xE39A4C), hover: Color(hex: 0xF2AB5E), soft: Color(hex: 0xE39A4C, opacity: 0.17))
        case (.amber, false):
            AccentPalette(accent: Color(hex: 0xC08A1C), hover: Color(hex: 0xA2720C), soft: Color(hex: 0xC08A1C, opacity: 0.14))
        case (.amber, true):
            AccentPalette(accent: Color(hex: 0xEBB94E), hover: Color(hex: 0xF5C765), soft: Color(hex: 0xEBB94E, opacity: 0.17))
        case (.patina, false):
            AccentPalette(accent: Color(hex: 0x2E8B57), hover: Color(hex: 0x256F46), soft: Color(hex: 0x2E8B57, opacity: 0.15))
        case (.patina, true):
            AccentPalette(accent: Color(hex: 0x58C078), hover: Color(hex: 0x6BD189), soft: Color(hex: 0x58C078, opacity: 0.17))
        }
    }
}

/// The full resolved token set for one color scheme + accent choice.
struct Theme {
    let winBg: Color
    let panel: Color
    let panel2: Color
    let sidebar: Color
    let titlebar: Color
    let text: Color
    let textDim: Color
    let textFaint: Color
    let border: Color
    let borderStrong: Color
    let green: Color
    let greenSoft: Color
    let danger: Color
    let accent: AccentPalette
    /// End color of progress-bar gradients (accent → this).
    let progressTail = Color(hex: 0xE0A24F)

    static func resolve(colorScheme: ColorScheme, accent: AccentChoice) -> Theme {
        let dark = colorScheme == .dark
        let accentPalette = AccentPalette.resolve(accent, dark: dark)
        if dark {
            return Theme(
                winBg: Color(hex: 0x1A1511),
                panel: Color(hex: 0x221C16),
                panel2: Color(hex: 0x2B241D),
                sidebar: Color(hex: 0x151009),
                titlebar: Color(hex: 0x241D15),
                text: Color(hex: 0xF1E9DD),
                textDim: Color(hex: 0xA99A86),
                textFaint: Color(hex: 0x75695A),
                border: Color(hex: 0xFFF0DC, opacity: 0.10),
                borderStrong: Color(hex: 0xFFF0DC, opacity: 0.20),
                green: Color(hex: 0x58C078),
                greenSoft: Color(hex: 0x58C078, opacity: 0.16),
                danger: Color(hex: 0xE06A4F),
                accent: accentPalette
            )
        }
        return Theme(
            winBg: Color(hex: 0xF6F2EC),
            panel: Color(hex: 0xFFFDF9),
            panel2: Color(hex: 0xEFE9DF),
            sidebar: Color(hex: 0xE8E1D5),
            titlebar: Color(hex: 0xE6DECE),
            text: Color(hex: 0x2B2119),
            textDim: Color(hex: 0x7C7161),
            textFaint: Color(hex: 0xA99E8C),
            border: Color(hex: 0x3C2D19, opacity: 0.12),
            borderStrong: Color(hex: 0x3C2D19, opacity: 0.24),
            green: Color(hex: 0x2E8B57),
            greenSoft: Color(hex: 0x2E8B57, opacity: 0.16),
            danger: Color(hex: 0xC0492F),
            accent: accentPalette
        )
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.resolve(colorScheme: .light, accent: .copper)
}

extension EnvironmentValues {
    var cvTheme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Color {
    /// 0xRRGGBB literal from the design doc's hex tables.
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
