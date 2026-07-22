import Foundation

/// Descriptor for the existing local Ollama vision runtime.
public struct OllamaBackendDescriptor: VisionBackendDescriptor {
    public let id = ModelBackend.ollama
    public let displayName = "Ollama"

    public let guidance = BackendGuidance(
        runtimeUnavailableMessage:
            "Analysis needs Ollama running locally. If it's installed, open the Ollama app (or run `ollama serve` in Terminal). If not, download it first — reviewing and exporting already-analyzed photos works without it.",
        preflightUnavailableMessage:
            "Ollama isn't reachable. If it's installed, open the Ollama app (or run `ollama serve`); if not, download it from https://ollama.com/download. Then retry.",
        downloadButtonTitle: "Download Ollama",
        downloadURL: URL(string: "https://ollama.com/download"),
        serveCommand: "ollama serve",
        noModelsMessage: "Analysis needs a vision-capable model. Install the starter model in Terminal, then re-check:",
        pullCommandPrefix: "ollama pull",
        modelNotFoundHelp: "Pull it with `ollama pull <tag>` or pick an installed vision model."
    )

    public let supportedTuningKnobs: Set<ModelTuningKnob> = [
        .contextWindow,
        .keepAlive,
        .maxResponseTokens,
        .temperature,
        .timeout,
        .retryLimit,
    ]

    private let runner: OllamaVisionRunner

    public init(runner: OllamaVisionRunner = OllamaVisionRunner()) {
        self.runner = runner
    }

    public func availability(configuration: ResolvedRunConfiguration) async -> BackendAvailability {
        do {
            try await runner.probeReachability(
                endpoint: configuration.modelEndpoint,
                timeoutSeconds: configuration.modelTimeoutSeconds
            )
            return .available
        } catch is CancellationError {
            return .unavailable(reason: "Ollama availability check was cancelled.", guidance: guidance)
        } catch let error as SidecarError {
            return .unavailable(reason: error.message, guidance: guidance)
        } catch {
            return .unavailable(
                reason: "Unable to reach Ollama endpoint: \(error.localizedDescription)",
                guidance: guidance
            )
        }
    }

    public func discoverModels(configuration: ResolvedRunConfiguration) async throws -> [BackendModelChoice] {
        try await runner.listInstalledVisionTags(
            endpoint: configuration.modelEndpoint,
            timeoutSeconds: configuration.modelTimeoutSeconds
        )
        .map { BackendModelChoice(id: $0, displayName: $0) }
    }

    public func makeRunner() -> any VisionModelRunner {
        runner
    }
}
