import CryptoKit
import Foundation

/// Model-facing derivative role persisted in `model_runs`.
public enum ModelInputRole: String, Codable, CaseIterable, Sendable, Equatable {
    case wholeImage = "whole_image"
    case subjectIsolated = "subject_isolated"

    public init?(derivativeRole: DerivativeRole) {
        switch derivativeRole {
        case .wholeImage:
            self = .wholeImage
        case .subjectIsolated:
            self = .subjectIsolated
        case .fullResolution:
            return nil
        }
    }
}

/// Versioned model prompt with a stable content hash for provenance.
public struct VersionedPrompt: Codable, Sendable, Equatable {
    public var version: String
    public var text: String
    public var sha256: String

    enum CodingKeys: String, CodingKey {
        case version
        case text
        case sha256
    }

    public init(version: String, text: String) {
        self.version = version
        self.text = text
        self.sha256 = Self.hash(text)
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// JSON Schema payload sent through Ollama's `format` field.
public struct JSONSchemaDocument: Codable, Sendable, Equatable {
    public var version: String
    public var schema: JSONValue

    public init(version: String, schema: JSONValue) {
        self.version = version
        self.schema = schema
    }

    public init(version: String, schemaJSON: String) throws {
        let data = Data(schemaJSON.utf8)
        self.version = version
        self.schema = try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

/// Runtime and model identity resolved before model requests begin.
public struct ModelRuntimeContext: Codable, Sendable, Equatable {
    public var model: String
    public var modelDigest: String
    public var runtime: String
    public var runtimeVersion: String
    public var endpoint: URL
    public var installedVisionTags: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case modelDigest = "model_digest"
        case runtime
        case runtimeVersion = "runtime_version"
        case endpoint
        case installedVisionTags = "installed_vision_tags"
    }

    public init(
        model: String,
        modelDigest: String,
        runtime: String = "ollama",
        runtimeVersion: String,
        endpoint: URL,
        installedVisionTags: [String] = []
    ) {
        self.model = model
        self.modelDigest = modelDigest
        self.runtime = runtime
        self.runtimeVersion = runtimeVersion
        self.endpoint = endpoint
        self.installedVisionTags = installedVisionTags
    }
}

/// Request options recorded per model run and mapped to Ollama request fields.
public struct ModelRunOptions: Codable, Sendable, Equatable {
    public var temperature: Double
    public var seed: Int
    public var thinkingEnabled: Bool
    public var keepAlive: String
    public var timeoutSeconds: Double
    public var retryLimit: Int
    public var contextWindow: Int?

    enum CodingKeys: String, CodingKey {
        case temperature
        case seed
        case thinkingEnabled = "thinking_enabled"
        case keepAlive = "keep_alive"
        case timeoutSeconds = "timeout_seconds"
        case retryLimit = "retry_limit"
        case contextWindow = "context_window"
    }

    public init(
        temperature: Double = 0,
        seed: Int = 0,
        thinkingEnabled: Bool = false,
        keepAlive: String = "30m",
        timeoutSeconds: Double = 180,
        retryLimit: Int = 2,
        contextWindow: Int? = nil
    ) {
        self.temperature = temperature
        self.seed = seed
        self.thinkingEnabled = thinkingEnabled
        self.keepAlive = keepAlive
        self.timeoutSeconds = timeoutSeconds
        self.retryLimit = retryLimit
        self.contextWindow = contextWindow
    }

    public static let `default` = ModelRunOptions()
}

/// Raw and parsed output plus provenance for one model call.
public struct ModelRunRecord: Codable, Sendable, Equatable {
    public var inputRole: ModelInputRole
    public var model: String
    public var modelDigest: String
    public var runtime: String
    public var runtimeVersion: String
    public var promptVersion: String
    public var promptSHA256: String
    public var responseSchemaVersion: String
    public var requestOptions: ModelRunOptions
    public var inputDerivativeSHA256: String
    public var rawResponseText: String
    public var parsedResponseJSON: JSONValue?
    public var jsonValid: Bool
    public var durationMs: Int
    public var error: SidecarError?

    enum CodingKeys: String, CodingKey {
        case inputRole = "input_role"
        case model
        case modelDigest = "model_digest"
        case runtime
        case runtimeVersion = "runtime_version"
        case promptVersion = "prompt_version"
        case promptSHA256 = "prompt_sha256"
        case responseSchemaVersion = "response_schema_version"
        case requestOptions = "request_options"
        case inputDerivativeSHA256 = "input_derivative_sha256"
        case rawResponseText = "raw_response_text"
        case parsedResponseJSON = "parsed_response_json"
        case jsonValid = "json_valid"
        case durationMs = "duration_ms"
        case error
    }

    public init(
        inputRole: ModelInputRole,
        model: String,
        modelDigest: String,
        runtime: String,
        runtimeVersion: String,
        promptVersion: String,
        promptSHA256: String,
        responseSchemaVersion: String,
        requestOptions: ModelRunOptions,
        inputDerivativeSHA256: String,
        rawResponseText: String,
        parsedResponseJSON: JSONValue?,
        jsonValid: Bool,
        durationMs: Int,
        error: SidecarError?
    ) {
        self.inputRole = inputRole
        self.model = model
        self.modelDigest = modelDigest
        self.runtime = runtime
        self.runtimeVersion = runtimeVersion
        self.promptVersion = promptVersion
        self.promptSHA256 = promptSHA256
        self.responseSchemaVersion = responseSchemaVersion
        self.requestOptions = requestOptions
        self.inputDerivativeSHA256 = inputDerivativeSHA256
        self.rawResponseText = rawResponseText
        self.parsedResponseJSON = parsedResponseJSON
        self.jsonValid = jsonValid
        self.durationMs = durationMs
        self.error = error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inputRole, forKey: .inputRole)
        try container.encode(model, forKey: .model)
        try container.encode(modelDigest, forKey: .modelDigest)
        try container.encode(runtime, forKey: .runtime)
        try container.encode(runtimeVersion, forKey: .runtimeVersion)
        try container.encode(promptVersion, forKey: .promptVersion)
        try container.encode(promptSHA256, forKey: .promptSHA256)
        try container.encode(responseSchemaVersion, forKey: .responseSchemaVersion)
        try container.encode(requestOptions, forKey: .requestOptions)
        try container.encode(inputDerivativeSHA256, forKey: .inputDerivativeSHA256)
        try container.encode(rawResponseText, forKey: .rawResponseText)
        if let parsedResponseJSON {
            try container.encode(parsedResponseJSON, forKey: .parsedResponseJSON)
        } else {
            try container.encodeNil(forKey: .parsedResponseJSON)
        }
        try container.encode(jsonValid, forKey: .jsonValid)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encode(error, forKey: .error)
    }
}
