import Foundation

/// A model exposed by a vision backend for interactive selection.
public struct BackendModelChoice: Identifiable, Sendable, Hashable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// User-facing remediation supplied by a backend instead of a GUI call site.
public struct BackendGuidance: Sendable, Equatable {
    public var runtimeUnavailableMessage: String
    public var preflightUnavailableMessage: String
    public var downloadButtonTitle: String?
    public var downloadURL: URL?
    public var serveCommand: String?
    public var noModelsMessage: String?
    public var pullCommandPrefix: String?
    public var modelNotFoundHelp: String?

    public init(
        runtimeUnavailableMessage: String,
        preflightUnavailableMessage: String? = nil,
        downloadButtonTitle: String? = nil,
        downloadURL: URL? = nil,
        serveCommand: String? = nil,
        noModelsMessage: String? = nil,
        pullCommandPrefix: String? = nil,
        modelNotFoundHelp: String? = nil
    ) {
        self.runtimeUnavailableMessage = runtimeUnavailableMessage
        self.preflightUnavailableMessage = preflightUnavailableMessage ?? runtimeUnavailableMessage
        self.downloadButtonTitle = downloadButtonTitle
        self.downloadURL = downloadURL
        self.serveCommand = serveCommand
        self.noModelsMessage = noModelsMessage
        self.pullCommandPrefix = pullCommandPrefix
        self.modelNotFoundHelp = modelNotFoundHelp
    }

    /// Render the backend's model-install command for a concrete model id.
    public func pullCommand(for model: String) -> String? {
        pullCommandPrefix.map { "\($0) \(model)" }
    }
}

/// Result of probing whether a backend can serve this application's workload.
public enum BackendAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String, guidance: BackendGuidance)
}

/// Configuration controls a backend can honor during inference.
public enum ModelTuningKnob: String, Codable, CaseIterable, Sendable {
    case contextWindow = "context_window"
    case keepAlive = "keep_alive"
    case maxResponseTokens = "max_response_tokens"
    case temperature
    case timeout
    case retryLimit = "retry_limit"
}

/// GUI- and CLI-facing metadata plus construction seams for one vision runtime.
public protocol VisionBackendDescriptor: Sendable {
    var id: ModelBackend { get }
    var displayName: String { get }
    var guidance: BackendGuidance { get }
    var supportedTuningKnobs: Set<ModelTuningKnob> { get }

    /// Probe availability using the endpoint resolved for this run.
    func availability(configuration: ResolvedRunConfiguration) async -> BackendAvailability

    /// Return the models this backend can use for image analysis.
    func discoverModels(configuration: ResolvedRunConfiguration) async throws -> [BackendModelChoice]

    /// Construct the runner after the factory has accepted this descriptor.
    func makeRunner() -> any VisionModelRunner
}
