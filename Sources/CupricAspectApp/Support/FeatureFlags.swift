import Foundation

/// Hidden build/runtime gates for UI surfaces that exist in code but are not
/// yet ready to expose. Each gate is off by default and opts in per launch
/// through an environment variable, following the `CUPRIC_*` convention the
/// wizard already uses for its dev hooks (`CUPRIC_DEBUG_STEP`, etc.).
///
/// These gate *presentation only*. The underlying pipelines and their
/// built-in defaults behave identically whether a flag is on or off, so
/// hiding a surface never changes a shipped modality — it only removes the
/// affordance from the screen.
enum FeatureFlags {
    /// Controlled-vocabulary UI surface: the custom vocabulary-file picker and
    /// "if not in vocabulary" policy in the normalize session-context panel,
    /// the vocabulary-file stale banner, and every "vocabulary" mention in the
    /// normalize/export copy. Hidden until the vocabulary tooling ships (post
    /// M11, roadmap F1); enable with `CUPRIC_VOCABULARY_UI=1`.
    ///
    /// When off, normalization still runs on the bundled starter vocabulary
    /// with its built-in `unknownSessionContextPolicy` default — the same
    /// configuration a fresh run uses today.
    static let vocabularyUI: Bool = isEnabled("CUPRIC_VOCABULARY_UI")

    /// Truthy-parse a hidden gate from the given environment (defaults to the
    /// process environment). Accepts `1`/`true`/`yes`/`on` (case-insensitive,
    /// surrounding whitespace ignored); everything else — including an absent
    /// or empty value — reads as off.
    static func isEnabled(
        _ key: String,
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let value = environment[key]?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        switch value {
        case "1", "true", "yes", "on": return true
        default: return false
        }
    }
}
