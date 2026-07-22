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
    static let liveLoader: Loader = { endpoint in
        try await OllamaVisionRunner().listInstalledVisionTags(endpoint: endpoint)
    }

    private enum LoadOutcome: Sendable {
        case loaded([String])
        case failed(String)
    }

    private struct SettledDiscovery {
        var tags: [String]
        var state: VisionTagState
        var lastChecked: Date?
    }

    private(set) var tags: [String] = []
    private(set) var state: VisionTagState = .idle
    private(set) var endpoint: URL?
    private(set) var lastChecked: Date?

    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inFlight: (endpoint: String, task: Task<Void, Never>)?
    @ObservationIgnored private var settledByEndpoint: [String: SettledDiscovery] = [:]

    init(loader: @escaping Loader = VisionTagsModel.liveLoader) {
        self.loader = loader
    }

    /// Load once for an endpoint, sharing in-flight work and caching either
    /// the successful result or failure until an explicit refresh.
    func loadIfNeeded(endpoint: URL) async {
        await load(endpoint: endpoint, force: false)
    }

    /// Repeat discovery for a settled endpoint. Repeated refreshes while the
    /// same request is running coalesce onto that request.
    func refresh(endpoint: URL) async {
        await load(endpoint: endpoint, force: true)
    }

    /// Supersede discovery when a caller cannot construct a valid endpoint.
    func fail(message: String) {
        generation += 1
        inFlight = nil
        endpoint = nil
        lastChecked = nil
        tags = []
        state = .failed(message: message)
    }

    private func load(endpoint: URL, force: Bool) async {
        let endpointKey = endpoint.absoluteString
        if let inFlight, inFlight.endpoint == endpointKey {
            await inFlight.task.value
            return
        }
        if !force,
            self.endpoint?.absoluteString == endpointKey,
            state != .idle
        {
            return
        }
        if !force, let settled = settledByEndpoint[endpointKey] {
            generation += 1
            inFlight = nil
            self.endpoint = endpoint
            tags = settled.tags
            state = settled.state
            lastChecked = settled.lastChecked
            return
        }

        generation += 1
        let requestGeneration = generation
        self.endpoint = endpoint
        state = .loading

        let loader = loader
        let task = Task { @MainActor [weak self] in
            let outcome: LoadOutcome
            do {
                outcome = .loaded(try await loader(endpoint))
            } catch {
                outcome = .failed((error as? SidecarError)?.message ?? error.localizedDescription)
            }

            guard let self,
                self.generation == requestGeneration,
                self.endpoint?.absoluteString == endpointKey
            else {
                return
            }
            self.inFlight = nil
            self.lastChecked = Date()
            switch outcome {
            case .loaded(let tags):
                self.tags = tags
                self.state = .loaded
            case .failed(let message):
                self.tags = []
                self.state = .failed(message: message)
            }
            self.settledByEndpoint[endpointKey] = SettledDiscovery(
                tags: self.tags,
                state: self.state,
                lastChecked: self.lastChecked
            )
        }
        inFlight = (endpoint: endpointKey, task: task)
        await task.value
    }
}
