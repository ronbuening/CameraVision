import Foundation

/// Deterministically ordered set of vision backends compiled into this build.
public struct VisionBackendRegistry: Sendable {
    public let descriptors: [any VisionBackendDescriptor]

    public init(descriptors: [any VisionBackendDescriptor]) {
        self.descriptors = descriptors
    }

    /// Production registry. The unavailable Apple descriptor joins this list in D5.
    public static var live: VisionBackendRegistry {
        VisionBackendRegistry(descriptors: [OllamaBackendDescriptor()])
    }

    public func descriptor(for id: ModelBackend) -> (any VisionBackendDescriptor)? {
        descriptors.first { $0.id == id }
    }
}
