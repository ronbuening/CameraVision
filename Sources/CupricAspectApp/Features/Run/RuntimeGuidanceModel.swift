import AISidecarCore
import Foundation
import Observation

/// Launch-time runtime guidance (FR4-058, AC4-034): one check when the shell
/// appears plus manual re-checks — never a polling loop (FR4-051 policy).
///
/// Two failure shapes get first-class guidance instead of an empty picker or
/// a failing run: Ollama unreachable (install/start pointers) and Ollama
/// reachable with no vision-capable model installed (a starter model named
/// with its `ollama pull` command — the configured default tag is never
/// silently assumed to exist).
@MainActor
@Observable
final class RuntimeGuidanceModel {
    enum Status: Equatable {
        case unknown
        case checking
        case ready(visionTagCount: Int)
        case unreachable(message: String)
        case noVisionModels
    }

    static let downloadURL = "https://ollama.com/download"

    private(set) var status: Status = .unknown
    private(set) var lastChecked: Date?
    /// The configured model tag, resolved through the standard chain — the
    /// starter suggestion when no vision model is installed.
    private(set) var configuredModel = ""
    private(set) var endpointDisplay = ""

    /// Injectable tag lister so tests never need a live Ollama
    /// (production default is CORE-8's `/api/tags` + `/api/show` probe).
    private let listVisionTags: @Sendable (URL) async throws -> [String]
    /// Alternate config path for tests; nil uses the standard chain.
    private let configPath: String?

    init(
        configPath: String? = nil,
        listVisionTags: @escaping @Sendable (URL) async throws -> [String] = { endpoint in
            try await OllamaVisionRunner().listInstalledVisionTags(endpoint: endpoint)
        }
    ) {
        self.configPath = configPath
        self.listVisionTags = listVisionTags
    }

    var pullCommand: String { "ollama pull \(configuredModel)" }

    /// The banner renders only for the two actionable failure shapes.
    var needsAttention: Bool {
        switch status {
        case .unreachable, .noVisionModels: true
        case .unknown, .checking, .ready: false
        }
    }

    func check(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard status != .checking else { return }
        status = .checking
        let endpoint: URL
        do {
            let resolved = try ConfigurationResolver.resolve(
                environment: environment,
                defaultConfigPath: configPath
            )
            configuredModel = resolved.model
            endpoint = resolved.modelEndpoint
            endpointDisplay = endpoint.absoluteString
        } catch {
            // An unresolvable config never blocks launch; Settings surfaces it.
            status = .unknown
            return
        }
        let listVisionTags = listVisionTags
        Task {
            do {
                let tags = try await listVisionTags(endpoint)
                status = tags.isEmpty ? .noVisionModels : .ready(visionTagCount: tags.count)
            } catch {
                status = .unreachable(
                    message: (error as? SidecarError)?.message ?? error.localizedDescription
                )
            }
            lastChecked = Date()
        }
    }
}
