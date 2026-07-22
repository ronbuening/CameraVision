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

    /// The configured model tag, resolved through the standard chain — the
    /// starter suggestion when no vision model is installed.
    private(set) var configuredModel = ""
    private(set) var endpointDisplay = ""

    let visionTagsModel: VisionTagsModel
    /// Alternate config path for tests; nil uses the standard chain.
    private let configPath: String?
    private var checkedEndpoint: URL?

    init(
        configPath: String? = nil,
        listVisionTags: @escaping VisionTagsModel.Loader = VisionTagsModel.liveLoader
    ) {
        self.configPath = configPath
        self.visionTagsModel = VisionTagsModel(loader: listVisionTags)
    }

    init(configPath: String? = nil, visionTagsModel: VisionTagsModel) {
        self.configPath = configPath
        self.visionTagsModel = visionTagsModel
    }

    var visionTags: VisionTagsModel { visionTagsModel }
    var pullCommand: String { "ollama pull \(configuredModel)" }

    var status: Status {
        guard let checkedEndpoint,
            let discoveryEndpoint = visionTagsModel.endpoint,
            checkedEndpoint.absoluteString == discoveryEndpoint.absoluteString
        else {
            return .unknown
        }
        switch visionTagsModel.state {
        case .idle:
            return .unknown
        case .loading:
            return .checking
        case .loaded where visionTagsModel.tags.isEmpty:
            return .noVisionModels
        case .loaded:
            return .ready(visionTagCount: visionTagsModel.tags.count)
        case .failed(let message):
            return .unreachable(message: message)
        }
    }

    var lastChecked: Date? {
        guard let checkedEndpoint,
            let discoveryEndpoint = visionTagsModel.endpoint,
            checkedEndpoint.absoluteString == discoveryEndpoint.absoluteString
        else {
            return nil
        }
        return visionTagsModel.lastChecked
    }

    /// The banner renders only for the two actionable failure shapes.
    var needsAttention: Bool {
        switch status {
        case .unreachable, .noVisionModels: true
        case .unknown, .checking, .ready: false
        }
    }

    /// Automatic launch check; reuses discovery already started by another surface.
    func loadIfNeeded(environment: [String: String] = ProcessInfo.processInfo.environment) {
        startCheck(environment: environment, forceRefresh: false)
    }

    /// Explicit user re-check; repeats a settled request without polling.
    func check(environment: [String: String] = ProcessInfo.processInfo.environment) {
        startCheck(environment: environment, forceRefresh: true)
    }

    private func startCheck(environment: [String: String], forceRefresh: Bool) {
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
            checkedEndpoint = nil
            return
        }
        checkedEndpoint = endpoint
        Task {
            if forceRefresh {
                await visionTagsModel.refresh(endpoint: endpoint)
            } else {
                await visionTagsModel.loadIfNeeded(endpoint: endpoint)
            }
        }
    }
}
