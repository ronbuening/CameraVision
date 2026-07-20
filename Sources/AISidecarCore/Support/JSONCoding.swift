import Foundation

/// Centralizes the JSON encoder/decoder configurations shared across the project's auditable
/// artifacts so every writer produces byte-identical output from one source of truth.
///
/// The formatting is deliberately stable: `.sortedKeys` and `.withoutEscapingSlashes` keep raw
/// sidecar, report, summary, and progress output deterministic, and golden fixtures assert on it.
/// Two formats are used across the codebase — compact (JSONL and single-line documents) and
/// pretty-printed (human-readable JSON files) — each optionally applying the project's ISO-8601
/// date convention. Types without `Date` fields pass `iso8601Dates: false` to preserve the exact
/// encoder state they used before this factory existed.
public enum JSONCoding {
    /// Compact encoder for newline-delimited JSONL logs and single-line JSON output.
    public static func jsonlEncoder(iso8601Dates: Bool = true) -> JSONEncoder {
        makeEncoder(pretty: false, iso8601Dates: iso8601Dates)
    }

    /// Pretty-printed encoder for human-readable JSON documents (sidecars, reports, summaries).
    public static func documentEncoder(iso8601Dates: Bool = true) -> JSONEncoder {
        makeEncoder(pretty: true, iso8601Dates: iso8601Dates)
    }

    /// Decoder matching the project's ISO-8601 date convention.
    public static func decoder(iso8601Dates: Bool = true) -> JSONDecoder {
        let decoder = JSONDecoder()
        if iso8601Dates {
            decoder.dateDecodingStrategy = .iso8601
        }
        return decoder
    }

    private static func makeEncoder(pretty: Bool, iso8601Dates: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        if iso8601Dates {
            encoder.dateEncodingStrategy = .iso8601
        }
        encoder.outputFormatting =
            pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
