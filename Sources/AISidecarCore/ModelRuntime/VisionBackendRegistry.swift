import Foundation

/// Deterministically ordered set of vision backends compiled into this build.
public struct VisionBackendRegistry: Sendable {
    public let descriptors: [any VisionBackendDescriptor]

    public init(descriptors: [any VisionBackendDescriptor]) {
        self.descriptors = descriptors
    }

    /// Production order implements `auto`: Apple first, then Ollama fallback.
    public static var live: VisionBackendRegistry {
        VisionBackendRegistry(descriptors: [
            AppleFoundationModelsDescriptor(),
            OllamaBackendDescriptor(),
        ])
    }

    public func descriptor(for id: ModelBackend) -> (any VisionBackendDescriptor)? {
        descriptors.first { $0.id == id }
    }
}
