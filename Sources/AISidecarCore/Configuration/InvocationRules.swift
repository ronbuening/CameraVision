import Foundation

/// Shared requirement-level validation for the CLI invocation scaffolds.
///
/// The `normalize`, `write-xmp`, and `apply-session` validators enforce the same flag-compatibility
/// contract with the same user-facing wording. Centralizing the rules here keeps that contract in one
/// place so the commands cannot drift apart (for example, guarding a flag against `--from-json` in one
/// command but silently accepting it in another).
enum InvocationRules {
    /// Trim a path option, treating a whitespace-only value as absent.
    static func normalizedPath(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    /// Reject a `--flag` / `--no-flag` pair supplied together.
    ///
    /// `name` is the flag stem without the leading dashes, e.g. `"backup-sidecars"`.
    static func rejectConflictingFlag(_ name: String, enabled: Bool, disabled: Bool) throws {
        if enabled, disabled {
            throw SidecarError.configInvalid("--\(name) and --no-\(name) cannot be combined.")
        }
    }

    /// Reject options that are invalid when input is sourced from `--from-json`.
    ///
    /// Each entry pairs a flag stem with whether it was supplied. The first supplied flag throws with
    /// the shared "invalid with --from-json" message, preserving the order the caller lists them in.
    static func rejectFromJSONIncompatible(_ options: [(flag: String, supplied: Bool)]) throws {
        for option in options where option.supplied {
            throw SidecarError.configInvalid("--\(option.flag) is invalid with --from-json.")
        }
    }
}
