import Foundation

/// Shared ISO-8601 timestamp formatting for artifact filenames and provenance fields.
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
}
