import AISidecarCore
import SwiftUI

struct WizardSectionLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(color)
    }
}

extension ModelBackend {
    var displayName: String {
        switch self {
        case .ollama: "Ollama"
        case .apple: "Apple on-device"
        case .auto: "Automatic"
        }
    }
}

/// One picker-label wording for the scalar-conflict policy, shared by the
/// Step 3 grading group and the apply-session card and pinned by tests so it
/// cannot drift from the CLI docs' phrasing.
extension ScalarConflictPolicy {
    var wizardLabel: String {
        switch self {
        case .preserve: "Preserve — never replace existing values"
        case .refresh: "Refresh — replace only values this app wrote before"
        case .overwrite: "Overwrite — always replace"
        }
    }
}

/// One picker-label wording for the quality scan mode, shared by the Step 3
/// advanced card and the Settings sheet and pinned by tests.
extension QualityScanMode {
    var wizardLabel: String {
        switch self {
        case .combined: "Normal"
        case .sequential: "High quality"
        }
    }
}
