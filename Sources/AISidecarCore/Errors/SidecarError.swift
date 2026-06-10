import Foundation

/// Frozen Phase 1 error code set.
///
/// Raw string values are stable public data because logs, progress records, and
/// sidecars depend on them across later phases.
public enum SidecarErrorCode: String, Codable, CaseIterable, Sendable {
    case unsupportedFormat = "E_UNSUPPORTED_FORMAT"
    case decodeFailed = "E_DECODE_FAILED"
    case renderFailed = "E_RENDER_FAILED"
    case orientationUnresolved = "E_ORIENTATION_UNRESOLVED"
    case subjectIsolationNoForeground = "E_SUBJECT_ISOLATION_NO_FOREGROUND"
    case subjectIsolationFailed = "E_SUBJECT_ISOLATION_FAILED"
    case modelEndpointUnreachable = "E_MODEL_ENDPOINT_UNREACHABLE"
    case modelTagNotFound = "E_MODEL_TAG_NOT_FOUND"
    case modelTimeout = "E_MODEL_TIMEOUT"
    case modelInvalidJSON = "E_MODEL_INVALID_JSON"
    case modelSchemaViolation = "E_MODEL_SCHEMA_VIOLATION"
    case sidecarExists = "E_SIDECAR_EXISTS"
    case sidecarCollision = "E_SIDECAR_COLLISION"
    case writeFailed = "E_WRITE_FAILED"
    case validationFailed = "E_VALIDATION_FAILED"
    case schemaUnsupported = "E_SCHEMA_UNSUPPORTED"
    case vocabularyInvalid = "E_VOCABULARY_INVALID"
    case sessionStale = "E_SESSION_STALE"
    case configInvalid = "E_CONFIG_INVALID"
    case exifToolMissing = "E_EXIFTOOL_MISSING"
    case interrupted = "E_INTERRUPTED"
}

/// Pipeline stage where a structured error occurred.
public enum SidecarErrorStage: String, Codable, CaseIterable, Sendable {
    case scan
    case render
    case isolate
    case model
    case normalize
    case write
    case configuration
}

/// Structured error record used by logs, scan results, summaries, and sidecars.
public struct SidecarError: Error, Codable, Sendable, Equatable, LocalizedError {
    public var code: SidecarErrorCode
    public var stage: SidecarErrorStage
    public var message: String
    public var recoverable: Bool

    public var errorDescription: String? {
        "\(code.rawValue): \(message)"
    }

    public init(
        code: SidecarErrorCode,
        stage: SidecarErrorStage,
        message: String,
        recoverable: Bool
    ) {
        self.code = code
        self.stage = stage
        self.message = message
        self.recoverable = recoverable
    }

    /// Build a fatal configuration error with the stable Phase 1 code.
    public static func configInvalid(_ message: String) -> SidecarError {
        SidecarError(
            code: .configInvalid,
            stage: .configuration,
            message: message,
            recoverable: false
        )
    }
}
