import AISidecarCore
import AppKit
import Foundation
import Observation

struct BackendPickerOption: Identifiable, Equatable {
    var id: ModelBackend
    var displayName: String
    var availabilityText: String
}

/// Settings state (FR4-056/057): reads through the same resolver chain as
/// every run (CLI flag > env > config.json > defaults) and writes user
/// changes back to the shared `config.json` via `ConfigFileEditor`, so CLI
/// and GUI defaults can never diverge. Environment overrides are disclosed,
/// not hidden — a setting masked by `AISIDECAR_*` still writes to the file
/// but the effective value comes from the environment.
@MainActor
@Observable
final class SettingsModel {
    private let configPath: String
    private let environment: [String: String]
    private let backendRegistry: VisionBackendRegistry
    let visionTagsModel: VisionTagsModel

    private(set) var model = ""
    private(set) var modelBackend = ModelBackend.ollama
    private(set) var endpoint = ""
    private(set) var mode: AnalysisMode = .both
    private(set) var gps: GPSContextMode = .coarse
    private(set) var existing: ExistingPolicy = .skip
    private(set) var xmpConflictPolicy: XMPConflictPolicy = ResolvedApplySessionConfiguration.builtInDefaults
        .xmpConflictPolicy
    private(set) var qualityScanMode = ResolvedRunConfiguration.builtInDefaults.qualityScanMode
    private(set) var qualityMinimumConfidence = QualityGradingPolicy.builtInDefaults.minimumConfidence
    private(set) var qualityWriteRating = QualityGradingPolicy.builtInDefaults.writeRating
    private(set) var qualityWriteLabel = QualityGradingPolicy.builtInDefaults.writeLabel
    private(set) var qualityWriteUrgency = QualityGradingPolicy.builtInDefaults.writeUrgency
    private(set) var qualityWriteFlag = QualityGradingPolicy.builtInDefaults.writeFlag
    private(set) var qualityWriteKeywords = QualityGradingPolicy.builtInDefaults.writeKeywords
    private(set) var stageConcurrency = min(8, max(1, ResolvedRunConfiguration.defaultStageConcurrency()))
    private(set) var profile = ModelInputProfile.defaultProfile.name
    private(set) var modelContextWindow = ResolvedRunConfiguration.builtInDefaults.modelContextWindow
    private(set) var modelTimeoutSeconds = ResolvedRunConfiguration.builtInDefaults.modelTimeoutSeconds
    private(set) var modelRetryLimit = ResolvedRunConfiguration.builtInDefaults.modelRetryLimit
    private(set) var derivativeCachePath = ""
    private(set) var loadError: String?
    /// AISIDECAR_* variables present in the environment (precedence notice).
    private(set) var environmentOverrides: [String] = []
    private(set) var backendAvailability: [ModelBackend: BackendAvailability] = [:]

    var endpointDraft = ""

    init(
        configPath: String = ConfigurationResolver.defaultConfigPath(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        visionTagsModel: VisionTagsModel = VisionTagsModel(),
        backendRegistry: VisionBackendRegistry = .live
    ) {
        self.configPath = configPath
        self.environment = environment
        self.visionTagsModel = visionTagsModel
        self.backendRegistry = backendRegistry
        reload()
    }

    var configPathDisplay: String { configPath }
    var visionTags: [String] { visionTagsModel.tags }
    var visionTagState: VisionTagState { visionTagsModel.state }
    var backendOptions: [BackendPickerOption] {
        let automaticStatus: String
        if backendAvailability.values.contains(.available) {
            automaticStatus = "uses first available"
        } else if backendAvailability.count == backendRegistry.descriptors.count,
            !backendRegistry.descriptors.isEmpty
        {
            automaticStatus = "unavailable"
        } else {
            automaticStatus = "checking…"
        }
        return [
            BackendPickerOption(id: .auto, displayName: "Automatic", availabilityText: automaticStatus)
        ]
            + backendRegistry.descriptors.map { descriptor in
                BackendPickerOption(
                    id: descriptor.id,
                    displayName: descriptor.displayName,
                    availabilityText: availabilityText(for: descriptor.id)
                )
            }
    }

    var selectedBackendDisplayName: String {
        if modelBackend == .auto { return "Automatic" }
        return backendRegistry.descriptor(for: modelBackend)?.displayName ?? modelBackend.rawValue.capitalized
    }

    var selectedBackendID: ModelBackend? { selectedBackendDescriptor?.id }

    var selectedBackendGuidance: BackendGuidance? {
        selectedBackendDescriptor?.guidance
    }

    var supportedTuningKnobs: Set<ModelTuningKnob> {
        selectedBackendDescriptor?.supportedTuningKnobs ?? []
    }

    var usesEndpoint: Bool {
        selectedBackendDescriptor?.id == .ollama
    }

    func reload() {
        do {
            let resolved = try ConfigurationResolver.resolve(
                environment: environment,
                defaultConfigPath: configPath
            )
            let resolvedApply = try ConfigurationResolver.resolveApplySession(
                environment: environment,
                defaultConfigPath: configPath
            )
            model = resolved.model
            modelBackend = resolved.modelBackend
            endpoint = resolved.modelEndpoint.absoluteString
            endpointDraft = endpoint
            mode = resolved.mode
            gps = resolved.gpsContext
            existing = resolved.existing
            xmpConflictPolicy = resolvedApply.xmpConflictPolicy
            qualityScanMode = resolved.qualityScanMode
            let qualityPolicy = resolvedApply.qualityGrading.policy
            qualityMinimumConfidence = qualityPolicy.minimumConfidence
            qualityWriteRating = qualityPolicy.writeRating
            qualityWriteLabel = qualityPolicy.writeLabel
            qualityWriteUrgency = qualityPolicy.writeUrgency
            qualityWriteFlag = qualityPolicy.writeFlag
            qualityWriteKeywords = qualityPolicy.writeKeywords
            stageConcurrency = min(8, max(1, resolved.stageConcurrency))
            profile = resolved.profile
            modelContextWindow = resolved.modelContextWindow
            modelTimeoutSeconds = resolved.modelTimeoutSeconds
            modelRetryLimit = resolved.modelRetryLimit
            derivativeCachePath = resolved.derivativeCacheDir
            loadError = nil
        } catch {
            loadError = (error as? SidecarError)?.message ?? error.localizedDescription
        }
        environmentOverrides = environment.keys
            .filter { $0.hasPrefix("AISIDECAR_") }
            .sorted()
    }

    // MARK: - Write-through (FR4-056)

    private func write(_ key: String, _ value: JSONValue?) {
        do {
            try ConfigFileEditor.merge([key: value], atPath: configPath)
            reload()
        } catch {
            loadError = (error as? SidecarError)?.message ?? error.localizedDescription
        }
    }

    func setMode(_ newMode: AnalysisMode) { write("mode", .string(newMode.rawValue)) }
    func setGPS(_ newGPS: GPSContextMode) { write("gps_context", .string(newGPS.rawValue)) }
    func setExisting(_ newExisting: ExistingPolicy) { write("existing", .string(newExisting.rawValue)) }
    func setXMPConflictPolicy(_ policy: XMPConflictPolicy) { write("xmp_conflict_policy", .string(policy.rawValue)) }
    func setQualityScanMode(_ mode: QualityScanMode) { write("quality_scan_mode", .string(mode.rawValue)) }
    func setQualityMinimumConfidence(_ confidence: QualityAssessmentRecord.Confidence) {
        write("xmp_quality_min_confidence", .string(confidence.rawValue))
    }
    func setQualityWriteRating(_ enabled: Bool) { write("xmp_quality_write_rating", .bool(enabled)) }
    func setQualityWriteLabel(_ enabled: Bool) { write("xmp_quality_write_label", .bool(enabled)) }
    func setQualityWriteUrgency(_ enabled: Bool) { write("xmp_quality_write_urgency", .bool(enabled)) }
    func setQualityWriteFlag(_ enabled: Bool) { write("xmp_quality_write_flag", .bool(enabled)) }
    func setQualityWriteKeywords(_ enabled: Bool) { write("xmp_quality_write_keywords", .bool(enabled)) }
    func setConcurrency(_ value: Int) { write("stage_concurrency", .number(Double(min(8, max(1, value))))) }
    func setProfile(_ name: String) { write("profile", .string(name)) }
    func setModelContextWindow(_ tokens: Int) { write("model_context_window", .number(Double(tokens))) }

    func setModelTimeoutSeconds(_ seconds: Double) {
        guard seconds > 0, seconds.isFinite else {
            loadError = "Model timeout must be a finite value greater than zero."
            return
        }
        write("model_timeout_seconds", .number(seconds))
    }

    func setModelRetryLimit(_ limit: Int) {
        guard limit >= 0 else {
            loadError = "Model retry limit must be zero or greater."
            return
        }
        write("model_retry_limit", .number(Double(limit)))
    }

    func setModel(_ tag: String) {
        write("model", .string(tag))
    }

    func setModelBackend(_ backend: ModelBackend) {
        write("model_backend", .string(backend.rawValue))
        Task { await loadBackendDataIfNeeded() }
    }

    /// Validate and persist the endpoint draft; refreshes the model list.
    func applyEndpoint() {
        let trimmed = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            loadError = "Not a valid endpoint URL: \(trimmed)"
            return
        }
        write("model_endpoint", .string(trimmed))
        refreshVisionTags()
    }

    // MARK: - Model picker (FR4-057, CORE-8)

    func refreshVisionTags() {
        Task {
            await loadBackendData(forceDiscovery: true)
        }
    }

    func loadVisionTagsIfNeeded() async {
        await loadBackendDataIfNeeded()
    }

    func loadBackendDataIfNeeded() async {
        await loadBackendData(forceDiscovery: false)
    }

    /// The configured model is missing or lost its vision capability.
    var configuredModelUnavailable: Bool {
        visionTagState == .loaded && !visionTags.contains(model)
    }

    private var selectedBackendDescriptor: (any VisionBackendDescriptor)? {
        if modelBackend != .auto {
            return backendRegistry.descriptor(for: modelBackend)
        }
        if let available = backendRegistry.descriptors.first(where: {
            backendAvailability[$0.id] == .available
        }) {
            return available
        }
        return backendRegistry.descriptor(for: .ollama) ?? backendRegistry.descriptors.first
    }

    private func loadBackendData(forceDiscovery: Bool) async {
        let configuration: ResolvedRunConfiguration
        do {
            configuration = try ConfigurationResolver.resolve(
                environment: environment,
                defaultConfigPath: configPath
            )
        } catch {
            loadError = (error as? SidecarError)?.message ?? error.localizedDescription
            return
        }

        // Every backend's annotation comes from its own descriptor probe — the
        // same answer the factory acts on — so the picker and a run can never
        // disagree. Discovery below answers the separate question of which
        // models the selected backend offers.
        var availability = backendAvailability
        for descriptor in backendRegistry.descriptors {
            availability[descriptor.id] = await descriptor.availability(configuration: configuration)
        }
        backendAvailability = availability

        guard let descriptor = selectedBackendDescriptor else {
            loadError = "No vision backend is registered for \(configuration.modelBackend.rawValue)."
            return
        }
        if case .unavailable(let reason, _) = backendAvailability[descriptor.id] {
            visionTagsModel.fail(descriptor: descriptor, configuration: configuration, message: reason)
            return
        }
        if forceDiscovery {
            await visionTagsModel.refresh(descriptor: descriptor, configuration: configuration)
        } else {
            await visionTagsModel.loadIfNeeded(descriptor: descriptor, configuration: configuration)
        }
    }

    private func availabilityText(for backend: ModelBackend) -> String {
        switch backendAvailability[backend] {
        case .available:
            "available"
        case .unavailable(let reason, _):
            "unavailable: \(reason)"
        case nil:
            "checking…"
        }
    }

    // MARK: - Cache

    func purgeDerivativeCache() -> Int {
        do {
            let resolved = try ConfigurationResolver.resolve(
                environment: environment,
                defaultConfigPath: configPath
            )
            let cache = DerivativeCache(
                directoryPath: resolved.derivativeCacheDir,
                sizeCapBytes: resolved.derivativeCacheSizeBytes
            )
            return try cache.clear().removedFileCount
        } catch {
            loadError = (error as? SidecarError)?.message ?? error.localizedDescription
            return 0
        }
    }

    func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: configPath)])
    }
}
