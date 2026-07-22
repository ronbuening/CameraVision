import Foundation

/// Resolves one backend for an entire run and constructs its model runner.
public struct VisionModelRunnerFactory: Sendable {
    private let registry: VisionBackendRegistry

    public init(registry: VisionBackendRegistry = .live) {
        self.registry = registry
    }

    /// Construct the runner this run will use.
    ///
    /// A pinned backend needs no availability probe here: the descriptor is
    /// chosen by configuration alone, and the runner's own `prepare` is the
    /// fail-closed gate the pipelines already run before any model work. Probing
    /// eagerly would move that gate earlier than it has ever been, so runs that
    /// never prepare a model — planning (`dry_run`) and fully skipped reruns —
    /// would start failing offline, and a pinned Ollama would report the backend
    /// code for failures that have always been `E_MODEL_ENDPOINT_UNREACHABLE`.
    ///
    /// `auto` is the one shape that cannot pick a descriptor without probing, so
    /// it resolves eagerly (still skipping availability I/O for planning runs).
    public func make(for configuration: ResolvedRunConfiguration) async throws -> any VisionModelRunner {
        switch configuration.modelBackend {
        case .ollama, .apple:
            return try registeredDescriptor(for: configuration.modelBackend).makeRunner()
        case .auto:
            if configuration.dryRun {
                return try registeredDescriptor(for: .auto).makeRunner()
            }
            return try await resolveBackend(for: configuration).makeRunner()
        }
    }

    /// Resolve a pinned backend, or the first available backend in registry order for `auto`.
    public func resolveBackend(
        for configuration: ResolvedRunConfiguration
    ) async throws -> any VisionBackendDescriptor {
        switch configuration.modelBackend {
        case .ollama, .apple:
            guard let descriptor = registry.descriptor(for: configuration.modelBackend) else {
                throw unavailableError(
                    id: configuration.modelBackend,
                    reason: "Backend is not registered in this build."
                )
            }
            switch await descriptor.availability(configuration: configuration) {
            case .available:
                return descriptor
            case .unavailable(let reason, _):
                throw unavailableError(id: descriptor.id, reason: reason)
            }
        case .auto:
            var unavailableReasons: [String] = []
            for descriptor in registry.descriptors {
                switch await descriptor.availability(configuration: configuration) {
                case .available:
                    return descriptor
                case .unavailable(let reason, _):
                    unavailableReasons.append("\(descriptor.displayName): \(reason)")
                }
            }
            let reason =
                unavailableReasons.isEmpty
                ? "No vision backends are registered in this build."
                : "No registered vision backend is available (\(unavailableReasons.joined(separator: "; ")))."
            throw unavailableError(id: .auto, reason: reason)
        }
    }

    /// Look up a descriptor without probing it; `auto` takes registry order.
    private func registeredDescriptor(for backend: ModelBackend) throws -> any VisionBackendDescriptor {
        if backend == .auto, let descriptor = registry.descriptors.first {
            return descriptor
        }
        guard let descriptor = registry.descriptor(for: backend) else {
            throw unavailableError(id: backend, reason: "Backend is not registered in this build.")
        }
        return descriptor
    }

    private func unavailableError(id: ModelBackend, reason: String) -> SidecarError {
        SidecarError(
            code: .modelBackendUnavailable,
            stage: .model,
            message: "Model backend '\(id.rawValue)' is unavailable: \(reason)",
            recoverable: true
        )
    }
}
