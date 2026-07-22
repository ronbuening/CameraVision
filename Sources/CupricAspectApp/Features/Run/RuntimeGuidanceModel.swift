import AISidecarCore
import Foundation
import Observation

/// Launch-time backend guidance (FR4-058, AC4-034): one check when the shell
/// appears plus manual re-checks — never a polling loop (FR4-051 policy).
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

    /// The configured model tag, resolved through the standard chain — the
    /// starter suggestion when no vision model is installed.
    private(set) var configuredModel = ""
    private(set) var endpointDisplay = ""
    private(set) var backendID = ModelBackend.ollama
    private(set) var backendDisplayName = "Ollama"
    private(set) var backendGuidance = OllamaBackendDescriptor().guidance

    let visionTagsModel: VisionTagsModel
    /// Alternate config path for tests; nil uses the standard chain.
    private let configPath: String?
    private let backendRegistry: VisionBackendRegistry
    private let runnerFactory: VisionModelRunnerFactory
    private var checkedEndpoint: URL?
    private var checkedBackendID: ModelBackend?
    private var checkGeneration = 0
    private var checkingResolution = false
    private var directFailure: String?
    private var directFailureCheckedAt: Date?

    init(
        configPath: String? = nil,
        backendRegistry: VisionBackendRegistry = .live
    ) {
        self.configPath = configPath
        self.visionTagsModel = VisionTagsModel()
        self.backendRegistry = backendRegistry
        self.runnerFactory = VisionModelRunnerFactory(registry: backendRegistry)
    }

    init(
        configPath: String? = nil,
        listVisionTags: @escaping VisionTagsModel.Loader,
        backendRegistry: VisionBackendRegistry = .live
    ) {
        self.configPath = configPath
        self.visionTagsModel = VisionTagsModel(loader: listVisionTags)
        self.backendRegistry = backendRegistry
        self.runnerFactory = VisionModelRunnerFactory(registry: backendRegistry)
    }

    init(
        configPath: String? = nil,
        visionTagsModel: VisionTagsModel,
        backendRegistry: VisionBackendRegistry = .live
    ) {
        self.configPath = configPath
        self.visionTagsModel = visionTagsModel
        self.backendRegistry = backendRegistry
        self.runnerFactory = VisionModelRunnerFactory(registry: backendRegistry)
    }

    var visionTags: VisionTagsModel { visionTagsModel }
    var pullCommand: String { backendGuidance.pullCommand(for: configuredModel) ?? "" }
    var downloadURL: URL? { backendGuidance.downloadURL }

    var status: Status {
        if checkingResolution { return .checking }
        if let directFailure { return .unreachable(message: directFailure) }
        guard let checkedEndpoint,
            let checkedBackendID,
            checkedBackendID == visionTagsModel.backendID,
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
        if directFailure != nil { return directFailureCheckedAt }
        guard let checkedEndpoint,
            let checkedBackendID,
            checkedBackendID == visionTagsModel.backendID,
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
        let configuration: ResolvedRunConfiguration
        do {
            configuration = try ConfigurationResolver.resolve(
                environment: environment,
                defaultConfigPath: configPath
            )
            configuredModel = configuration.model
            endpointDisplay = configuration.modelEndpoint.absoluteString
        } catch {
            // An unresolvable config never blocks launch; Settings surfaces it.
            checkedEndpoint = nil
            checkedBackendID = nil
            checkingResolution = false
            directFailure = nil
            return
        }

        checkGeneration += 1
        let generation = checkGeneration
        checkingResolution = true
        directFailure = nil
        Task {
            let descriptor: any VisionBackendDescriptor
            do {
                if configuration.modelBackend == .auto {
                    descriptor = try await runnerFactory.resolveBackend(for: configuration)
                } else if let pinned = backendRegistry.descriptor(for: configuration.modelBackend) {
                    descriptor = pinned
                } else {
                    throw SidecarError(
                        code: .modelBackendUnavailable,
                        stage: .model,
                        message: "Backend is not registered in this build.",
                        recoverable: true
                    )
                }
            } catch {
                guard generation == checkGeneration else { return }
                let fallback =
                    backendRegistry.descriptor(for: configuration.modelBackend)
                    ?? backendRegistry.descriptor(for: .ollama)
                    ?? backendRegistry.descriptors.last
                backendID = fallback?.id ?? configuration.modelBackend
                backendDisplayName = fallback?.displayName ?? configuration.modelBackend.displayName
                if let fallback { backendGuidance = fallback.guidance }
                directFailure = (error as? SidecarError)?.message ?? error.localizedDescription
                directFailureCheckedAt = Date()
                checkedEndpoint = configuration.modelEndpoint
                checkedBackendID = backendID
                checkingResolution = false
                return
            }

            guard generation == checkGeneration else { return }
            backendID = descriptor.id
            backendDisplayName = descriptor.displayName
            backendGuidance = descriptor.guidance
            checkedEndpoint = configuration.modelEndpoint
            checkedBackendID = descriptor.id
            if forceRefresh {
                await visionTagsModel.refresh(descriptor: descriptor, configuration: configuration)
            } else {
                await visionTagsModel.loadIfNeeded(descriptor: descriptor, configuration: configuration)
            }
            guard generation == checkGeneration else { return }
            checkingResolution = false
        }
    }
}
