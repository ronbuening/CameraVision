import AISidecarCore
import AppKit
import Foundation
import Observation

enum VisionTagState: Equatable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

enum VisionTagLoader {
    static func listInstalledVisionTags(endpoint: URL) async throws -> [String] {
        try await OllamaVisionRunner().listInstalledVisionTags(endpoint: endpoint)
    }
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

    private(set) var model = ""
    private(set) var endpoint = ""
    private(set) var mode: AnalysisMode = .both
    private(set) var gps: GPSContextMode = .coarse
    private(set) var existing: ExistingPolicy = .skip
    private(set) var xmpConflictPolicy: XMPConflictPolicy = ResolvedApplySessionConfiguration.builtInDefaults.xmpConflictPolicy
    private(set) var stageConcurrency = min(8, max(1, ResolvedRunConfiguration.defaultStageConcurrency()))
    private(set) var profile = ModelInputProfile.defaultProfile.name
    private(set) var modelContextWindow = ResolvedRunConfiguration.builtInDefaults.modelContextWindow
    private(set) var modelTimeoutSeconds = ResolvedRunConfiguration.builtInDefaults.modelTimeoutSeconds
    private(set) var modelRetryLimit = ResolvedRunConfiguration.builtInDefaults.modelRetryLimit
    private(set) var derivativeCachePath = ""
    private(set) var loadError: String?
    /// AISIDECAR_* variables present in the environment (precedence notice).
    private(set) var environmentOverrides: [String] = []

    private(set) var visionTags: [String] = []
    private(set) var visionTagState: VisionTagState = .idle

    var endpointDraft = ""

    init(
        configPath: String = ConfigurationResolver.defaultConfigPath(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.configPath = configPath
        self.environment = environment
        reload()
    }

    var configPathDisplay: String { configPath }

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
            endpoint = resolved.modelEndpoint.absoluteString
            endpointDraft = endpoint
            mode = resolved.mode
            gps = resolved.gpsContext
            existing = resolved.existing
            xmpConflictPolicy = resolvedApply.xmpConflictPolicy
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
        guard visionTagState != .loading else { return }
        guard let url = URL(string: endpoint) else { return }
        visionTagState = .loading
        Task {
            do {
                let tags = try await VisionTagLoader.listInstalledVisionTags(endpoint: url)
                visionTags = tags
                visionTagState = .loaded
            } catch {
                visionTags = []
                let message = (error as? SidecarError)?.message ?? error.localizedDescription
                visionTagState = .failed(message: message)
            }
        }
    }

    /// The configured model is missing or lost its vision capability.
    var configuredModelUnavailable: Bool {
        visionTagState == .loaded && !visionTags.contains(model)
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
