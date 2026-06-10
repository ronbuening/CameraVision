import Foundation

/// Single structured log event.
///
/// JSON output uses stable snake_case field names so later GUI and batch tools
/// can decode logs with the same model as progress records.
public struct LogRecord: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var level: LogLevel
    public var event: String
    public var message: String
    public var sourcePath: String?
    public var sidecarPath: String?
    public var status: String?
    public var errors: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case timestamp
        case level
        case event
        case message
        case sourcePath = "source_path"
        case sidecarPath = "sidecar_path"
        case status
        case errors
    }

    public init(
        timestamp: Date = Date(),
        level: LogLevel,
        event: String,
        message: String,
        sourcePath: String? = nil,
        sidecarPath: String? = nil,
        status: String? = nil,
        errors: [SidecarError] = []
    ) {
        self.timestamp = timestamp
        self.level = level
        self.event = event
        self.message = message
        self.sourcePath = sourcePath
        self.sidecarPath = sidecarPath
        self.status = status
        self.errors = errors
    }
}

/// Small synchronous logger for CLI presentation.
///
/// The sink is injectable so tests can verify rendering without writing to
/// standard error.
public struct Logger: Sendable {
    public var minimumLevel: LogLevel
    public var format: LogFormat
    private let sink: @Sendable (String) -> Void

    public init(
        minimumLevel: LogLevel = .info,
        format: LogFormat = .text,
        sink: @escaping @Sendable (String) -> Void = { line in
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    ) {
        self.minimumLevel = minimumLevel
        self.format = format
        self.sink = sink
    }

    /// Render and emit the record when it meets the configured severity level.
    public func log(_ record: LogRecord) throws {
        guard record.level <= minimumLevel else {
            return
        }
        sink(try render(record))
    }

    /// Render a log record without writing it.
    public func render(_ record: LogRecord) throws -> String {
        try Self.render(record, format: format)
    }

    /// Shared renderer used by production logging and tests.
    public static func render(_ record: LogRecord, format: LogFormat) throws -> String {
        switch format {
        case .text:
            return renderText(record)
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(record)
            return String(decoding: data, as: UTF8.self)
        }
    }

    private static func renderText(_ record: LogRecord) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: record.timestamp)
        var line = "\(timestamp) \(record.level.rawValue.uppercased()) \(record.event): \(record.message)"
        if let sourcePath = record.sourcePath {
            line += " source_path=\(sourcePath)"
        }
        if let sidecarPath = record.sidecarPath {
            line += " sidecar_path=\(sidecarPath)"
        }
        if let status = record.status {
            line += " status=\(status)"
        }
        if !record.errors.isEmpty {
            let codes = record.errors.map { $0.code.rawValue }.joined(separator: ",")
            line += " errors=\(codes)"
        }
        return line
    }
}
