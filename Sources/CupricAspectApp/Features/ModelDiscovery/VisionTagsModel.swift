import AISidecarCore
import Foundation
import Observation

enum VisionTagState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

/// Shared Ollama vision-model discovery state for every GUI surface.
///
/// Automatic consumers reuse the settled result for an endpoint, while an
/// explicit refresh repeats discovery. Requests for a new endpoint supersede
/// older work so a late response cannot restore stale model tags. Settled
/// results are kept per endpoint, so one surface's failure (or an endpoint
/// switch) never costs another endpoint its cached result.
@MainActor
@Observable
final class VisionTagsModel {
    typealias Loader = @Sendable (URL) async throws -> [String]
    typealias BackendLoader =
        @Sendable (any VisionBackendDescriptor, ResolvedRunConfiguration) async throws -> [BackendModelChoice]

    static let liveLoader: Loader = { endpoint in
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelEndpoint = endpoint
        return try await OllamaBackendDescriptor().discoverModels(configuration: configuration).map(\.id)
    }
    static let liveBackendLoader: BackendLoader = { descriptor, configuration in
        try await descriptor.discoverModels(configuration: configuration)
    }

    private enum LoadOutcome: Sendable {
        case loaded([BackendModelChoice])
        case failed(String)
    }

    private struct SettledDiscovery {
        var models: [BackendModelChoice]
        var state: VisionTagState
        var lastChecked: Date?
    }

    private struct DiscoveryKey: Hashable {
        var backendID: ModelBackend
        var endpoint: String
    }

    private(set) var models: [BackendModelChoice] = []
    private(set) var state: VisionTagState = .idle
    private(set) var backendID: ModelBackend?
    private(set) var endpoint: URL?
    private(set) var lastChecked: Date?

    var tags: [String] { models.map(\.id) }

    @ObservationIgnored private let backendLoader: BackendLoader
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inFlight: (key: DiscoveryKey, task: Task<Void, Never>)?
    @ObservationIgnored private var settledByKey: [DiscoveryKey: SettledDiscovery] = [:]

    init() {
        self.backendLoader = Self.liveBackendLoader
    }

    init(loader: @escaping Loader) {
        self.backendLoader = { _, configuration in
            try await loader(configuration.modelEndpoint).map { BackendModelChoice(id: $0, displayName: $0) }
        }
    }

    init(backendLoader: @escaping BackendLoader) {
        self.backendLoader = backendLoader
    }

    /// Load once for an endpoint, sharing in-flight work and caching either
    /// the successful result or failure until an explicit refresh.
    func loadIfNeeded(endpoint: URL) async {
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelEndpoint = endpoint
        await load(
            descriptor: OllamaBackendDescriptor(),
            configuration: configuration,
            force: false
        )
    }

    /// Repeat discovery for a settled endpoint. Repeated refreshes while the
    /// same request is running coalesce onto that request.
    func refresh(endpoint: URL) async {
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelEndpoint = endpoint
        await load(
            descriptor: OllamaBackendDescriptor(),
            configuration: configuration,
            force: true
        )
    }

    func loadIfNeeded(
        descriptor: any VisionBackendDescriptor,
        configuration: ResolvedRunConfiguration
    ) async {
        await load(descriptor: descriptor, configuration: configuration, force: false)
    }

    func refresh(
        descriptor: any VisionBackendDescriptor,
        configuration: ResolvedRunConfiguration
    ) async {
        await load(descriptor: descriptor, configuration: configuration, force: true)
    }

    /// Supersede discovery when a caller cannot construct a valid endpoint.
    func fail(message: String) {
        generation += 1
        inFlight = nil
        backendID = nil
        endpoint = nil
        lastChecked = nil
        models = []
        state = .failed(message: message)
    }

    /// Project a backend-scoped validation or availability failure without evicting other caches.
    func fail(
        descriptor: any VisionBackendDescriptor,
        configuration: ResolvedRunConfiguration,
        message: String
    ) {
        generation += 1
        inFlight = nil
        let key = DiscoveryKey(
            backendID: descriptor.id,
            endpoint: configuration.modelEndpoint.absoluteString
        )
        backendID = descriptor.id
        endpoint = configuration.modelEndpoint
        lastChecked = Date()
        models = []
        state = .failed(message: message)
        settledByKey[key] = SettledDiscovery(models: [], state: state, lastChecked: lastChecked)
    }

    private func load(
        descriptor: any VisionBackendDescriptor,
        configuration: ResolvedRunConfiguration,
        force: Bool
    ) async {
        let key = DiscoveryKey(
            backendID: descriptor.id,
            endpoint: configuration.modelEndpoint.absoluteString
        )
        if let inFlight, inFlight.key == key {
            await inFlight.task.value
            return
        }
        if !force,
            backendID == key.backendID,
            endpoint?.absoluteString == key.endpoint,
            state != .idle
        {
            return
        }
        if !force, let settled = settledByKey[key] {
            generation += 1
            inFlight = nil
            backendID = key.backendID
            endpoint = configuration.modelEndpoint
            models = settled.models
            state = settled.state
            lastChecked = settled.lastChecked
            return
        }

        generation += 1
        let requestGeneration = generation
        backendID = key.backendID
        endpoint = configuration.modelEndpoint
        state = .loading

        let backendLoader = backendLoader
        let task = Task { @MainActor [weak self] in
            let outcome: LoadOutcome
            do {
                outcome = .loaded(try await backendLoader(descriptor, configuration))
            } catch {
                outcome = .failed((error as? SidecarError)?.message ?? error.localizedDescription)
            }

            guard let self,
                self.generation == requestGeneration,
                self.backendID == key.backendID,
                self.endpoint?.absoluteString == key.endpoint
            else {
                return
            }
            self.inFlight = nil
            self.lastChecked = Date()
            switch outcome {
            case .loaded(let models):
                self.models = models
                self.state = .loaded
            case .failed(let message):
                self.models = []
                self.state = .failed(message: message)
            }
            self.settledByKey[key] = SettledDiscovery(
                models: self.models,
                state: self.state,
                lastChecked: self.lastChecked
            )
        }
        inFlight = (key: key, task: task)
        await task.value
    }
}
