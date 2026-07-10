import Foundation

/// Shared timestamp formatting for provenance fields and filesystem artifact names.
///
/// Several pipelines and writers independently built an `ISO8601DateFormatter` with
/// `[.withInternetDateTime]`; this centralizes that one format. Callers that need a different
/// option set (for example fractional-second log lines) construct their own formatter and are
/// intentionally not routed through here.
public enum Timestamp {
    /// Format a date as an internet date-time ISO-8601 string (`yyyy-MM-dd'T'HH:mm:ssZ`).
    public static func internetDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Format a date for filenames by removing the colons from the internet date-time form.
    public static func filenameSafe(_ date: Date) -> String {
        internetDateTime(date).replacingOccurrences(of: ":", with: "")
    }

    /// Generate a lowercase four-hex suffix that de-collides artifact names created in the same second.
    public static func randomFilenameSuffix() -> String {
        String(UUID().uuidString.prefix(4)).lowercased()
    }

    /// Combine a filesystem-safe timestamp with one caller-supplied run suffix.
    public static func filenameToken(_ date: Date, suffix: String) -> String {
        "\(filenameSafe(date))-\(suffix)"
    }
}
