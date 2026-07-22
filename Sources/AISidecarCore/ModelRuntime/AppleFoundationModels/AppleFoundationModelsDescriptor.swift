import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Describes the planned Apple on-device backend without claiming image-input support exists today.
public struct AppleFoundationModelsDescriptor: VisionBackendDescriptor {
    public static let unavailableReason =
        "requires a vision-capable Apple on-device model; current macOS/FoundationModels does not provide image input for this workload (expected in a future macOS release)"

    public let id = ModelBackend.apple
    public let displayName = "Apple on-device"
    public let guidance = BackendGuidance(
        runtimeUnavailableMessage:
            "Apple on-device analysis requires a vision-capable system model. Current macOS/FoundationModels releases do not provide image input for this workload; support is expected in a future macOS release."
    )
    public let supportedTuningKnobs: Set<ModelTuningKnob> = []

    public init() {}

    /// This remains unavailable even on macOS 26 because its public FoundationModels API is text-only.
    public func availability(configuration _: ResolvedRunConfiguration) async -> BackendAvailability {
        .unavailable(reason: Self.unavailableReason, guidance: guidance)
    }

    public func discoverModels(configuration _: ResolvedRunConfiguration) async throws -> [BackendModelChoice] {
        throw Self.unavailableError()
    }

    public func makeRunner() -> any VisionModelRunner {
        AppleFoundationModelsRunner()
    }

    static func unavailableError(includeBackendPrefix: Bool = false) -> SidecarError {
        let message =
            includeBackendPrefix
            ? "Model backend 'apple' is unavailable: \(unavailableReason)"
            : unavailableReason
        return SidecarError(
            code: .modelBackendUnavailable,
            stage: .model,
            message: message,
            recoverable: true
        )
    }

    #if canImport(FoundationModels)
        /// Keeps the future adapter's framework boundary compiling without treating text availability as vision support.
        @available(macOS 26, *)
        private static func compileAgainstPublicFrameworkSurface() {
            _ = SystemLanguageModel.default
        }
    #endif
}

/// Safe placeholder runner for a backend the factory deliberately refuses to select.
public struct AppleFoundationModelsRunner: VisionModelRunner {
    public static let runtimeIdentifier = "apple-foundation-models"
    public static let modelIdentifier = "system-language-model"

    public init() {}

    /// Canonical macOS product version reserved for future Apple runtime provenance.
    public static func runtimeVersion(for version: OperatingSystemVersion) -> String {
        let base = "\(version.majorVersion).\(version.minorVersion)"
        return version.patchVersion == 0 ? base : "\(base).\(version.patchVersion)"
    }

    /// Canonical system-model digest reserved for future Apple runtime provenance.
    public static func modelDigest(osBuild: String) -> String {
        "system:\(osBuild)"
    }

    public static var currentRuntimeVersion: String {
        runtimeVersion(for: ProcessInfo.processInfo.operatingSystemVersion)
    }

    public static var currentModelDigest: String {
        modelDigest(osBuild: currentOSBuild())
    }

    public func prepare(configuration _: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        throw AppleFoundationModelsDescriptor.unavailableError(includeBackendPrefix: true)
    }

    public func analyze(
        image: DerivativeRecord,
        inputRole: ModelInputRole,
        prompt: VersionedPrompt,
        schema: JSONSchemaDocument,
        options: ModelRunOptions,
        runtime: ModelRuntimeContext,
        isInterrupted _: (@Sendable () -> Bool)?
    ) async -> ModelRunRecord {
        ModelRunRecord(
            inputRole: inputRole,
            model: runtime.model,
            modelDigest: runtime.modelDigest,
            runtime: runtime.runtime,
            runtimeVersion: runtime.runtimeVersion,
            promptVersion: prompt.version,
            promptSHA256: prompt.sha256,
            responseSchemaVersion: schema.version,
            requestOptions: options,
            inputDerivativeSHA256: image.sha256,
            rawResponseText: "",
            parsedResponseJSON: nil,
            jsonValid: false,
            durationMs: 0,
            error: AppleFoundationModelsDescriptor.unavailableError(includeBackendPrefix: true)
        )
    }

    private static func currentOSBuild() -> String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else {
            return "unknown"
        }
        return String(decoding: bytes.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}
