import Foundation

/// Resolves one backend for an entire run and constructs its model runner.
public struct VisionModelRunnerFactory: Sendable {
    private let registry: VisionBackendRegistry

    public init(registry: VisionBackendRegistry = .live) {
        self.registry = registry
    }

    /// Resolve and preflight the configured backend before model work begins.
    ///
    /// Analysis planning (`dry_run`) never prepares or calls a runner, so it
    /// preserves its existing offline behavior and skips backend availability I/O.
    public func make(for configuration: ResolvedRunConfiguration) async throws -> any VisionModelRunner {
        if configuration.dryRun {
            return try planningDescriptor(for: configuration.modelBackend).makeRunner()
        }
        return try await resolveBackend(for: configuration).makeRunner()
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

    private func planningDescriptor(for backend: ModelBackend) throws -> any VisionBackendDescriptor {
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
