import AISidecarCore
import Foundation
import XCTest

@testable import CupricAspectApp

@MainActor
final class VisionTagsModelTests: XCTestCase {
    func testOneDiscoveryIdentityFlowsThroughRuntimeFlowSettingsAndStep3() {
        let discovery = VisionTagsModel(loader: { _ in
            throw VisionTagsTestError.unexpectedLoaderCall
        })
        let configPath = missingConfigPath()
        let runtime = RuntimeGuidanceModel(configPath: configPath, visionTagsModel: discovery)
        let flow = WizardFlowModel(runtimeGuidance: runtime)
        let settings = SettingsModel(configPath: configPath, environment: [:], visionTagsModel: discovery)
        let step3 = Step3OptionsView(
            action: .analyze,
            options: AnalysisOptions(environment: [:], defaultConfigPath: configPath),
            runModel: AnalysisRunModel(),
            importModel: FolderImportModel(),
            normalizationModel: nil,
            visionTagsModel: discovery
        )

        XCTAssertTrue(runtime.visionTagsModel === discovery)
        XCTAssertTrue(runtime.visionTags === discovery)
        XCTAssertTrue(flow.visionTagsModel === discovery)
        XCTAssertTrue(settings.visionTagsModel === discovery)
        XCTAssertTrue(step3.visionTagsModel === discovery)
    }

    func testAutomaticLoadCachesSuccessAndSameEndpointRefreshCoalesces() async throws {
        let loader = ControlledVisionTagLoader()
        let model = VisionTagsModel(loader: { endpoint in
            try await loader.load(endpoint)
        })
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:11434"))

        let automaticLoad = Task { await model.loadIfNeeded(endpoint: endpoint) }
        try await waitForCallCount(1, loader: loader)
        XCTAssertEqual(model.state, .loading)
        XCTAssertEqual(model.tags, [])

        await loader.succeed(callAt: 0, tags: ["first:vision"])
        await automaticLoad.value
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.tags, ["first:vision"])

        await model.loadIfNeeded(endpoint: endpoint)
        let cachedCallCount = await loader.callCount
        XCTAssertEqual(cachedCallCount, 1, "an automatic load reuses the completed result")

        let firstRefresh = Task { await model.refresh(endpoint: endpoint) }
        try await waitForCallCount(2, loader: loader)
        XCTAssertEqual(model.state, .loading)
        XCTAssertEqual(model.tags, ["first:vision"], "refresh retains the last usable picker contents")

        let coalescedRefresh = Task { await model.refresh(endpoint: endpoint) }
        for _ in 0..<5 {
            await Task.yield()
        }
        let coalescedCallCount = await loader.callCount
        XCTAssertEqual(coalescedCallCount, 2, "same-endpoint requests share the in-flight discovery")

        await loader.succeed(callAt: 1, tags: ["second:vision"])
        await firstRefresh.value
        await coalescedRefresh.value
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.tags, ["second:vision"])
    }

    func testFailureIsCachedUntilManualRefreshAndMapsErrorsExactly() async throws {
        let loader = ControlledVisionTagLoader()
        let model = VisionTagsModel(loader: { endpoint in
            try await loader.load(endpoint)
        })
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:11434"))
        let sidecarError = SidecarError(
            code: .modelEndpointUnreachable,
            stage: .model,
            message: "connection refused exactly",
            recoverable: true
        )

        let firstLoad = Task { await model.loadIfNeeded(endpoint: endpoint) }
        try await waitForCallCount(1, loader: loader)
        await loader.fail(callAt: 0, error: sidecarError)
        await firstLoad.value

        XCTAssertEqual(model.tags, [])
        XCTAssertEqual(model.state, .failed(message: "connection refused exactly"))

        await model.loadIfNeeded(endpoint: endpoint)
        let cachedCallCount = await loader.callCount
        XCTAssertEqual(cachedCallCount, 1, "automatic loading caches failures until an explicit retry")

        let retry = Task { await model.refresh(endpoint: endpoint) }
        try await waitForCallCount(2, loader: loader)
        await loader.fail(callAt: 1, error: LocalizedLoaderError())
        await retry.value

        XCTAssertEqual(model.tags, [])
        XCTAssertEqual(model.state, .failed(message: "localized loader failure"))
    }

    func testNewEndpointSupersedesInFlightRequestAndIgnoresItsStaleCompletion() async throws {
        let loader = ControlledVisionTagLoader()
        let model = VisionTagsModel(loader: { endpoint in
            try await loader.load(endpoint)
        })
        let oldEndpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:11434"))
        let newEndpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:22468"))

        let oldLoad = Task { await model.loadIfNeeded(endpoint: oldEndpoint) }
        try await waitForCallCount(1, loader: loader)
        let newLoad = Task { await model.loadIfNeeded(endpoint: newEndpoint) }
        try await waitForCallCount(2, loader: loader)

        let endpoints = await loader.endpoints
        XCTAssertEqual(endpoints, [oldEndpoint, newEndpoint])
        await loader.succeed(callAt: 1, tags: ["new:endpoint"])
        await newLoad.value
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.tags, ["new:endpoint"])

        await loader.succeed(callAt: 0, tags: ["stale:endpoint"])
        await oldLoad.value
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.tags, ["new:endpoint"])
    }

    func testExplicitFailureInvalidatesAnInFlightGenerationWithoutCallingLoader() async throws {
        let loader = ControlledVisionTagLoader()
        let model = VisionTagsModel(loader: { endpoint in
            try await loader.load(endpoint)
        })
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:11434"))

        let load = Task { await model.loadIfNeeded(endpoint: endpoint) }
        try await waitForCallCount(1, loader: loader)
        model.fail(message: "Invalid model endpoint.")

        XCTAssertEqual(model.tags, [])
        XCTAssertEqual(model.state, .failed(message: "Invalid model endpoint."))
        let initialCallCount = await loader.callCount
        XCTAssertEqual(initialCallCount, 1)

        await loader.succeed(callAt: 0, tags: ["stale:vision"])
        await load.value
        XCTAssertEqual(model.tags, [])
        XCTAssertEqual(model.state, .failed(message: "Invalid model endpoint."))
        let finalCallCount = await loader.callCount
        XCTAssertEqual(finalCallCount, 1)
    }

    func testSettingsProjectsSharedStateAndApplyingEndpointForcesRefresh() async throws {
        let loader = ControlledVisionTagLoader()
        let discovery = VisionTagsModel(loader: { endpoint in
            try await loader.load(endpoint)
        })
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vision-tags-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let configPath = root.appendingPathComponent("config.json").path
        let settings = SettingsModel(configPath: configPath, environment: [:], visionTagsModel: discovery)
        let configuredModel = settings.model

        let automaticLoad = Task { await settings.loadVisionTagsIfNeeded() }
        try await waitForCallCount(1, loader: loader)
        await loader.succeed(callAt: 0, tags: [configuredModel])
        await automaticLoad.value

        XCTAssertEqual(settings.visionTags, [configuredModel])
        XCTAssertEqual(settings.visionTagState, .loaded)
        XCTAssertFalse(settings.configuredModelUnavailable)

        settings.endpointDraft = settings.endpoint
        settings.applyEndpoint()
        try await waitForCallCount(2, loader: loader)
        XCTAssertEqual(settings.visionTagState, .loading)
        XCTAssertEqual(settings.visionTags, [configuredModel])

        await loader.succeed(callAt: 1, tags: ["another:vision"])
        try await waitForState(.loaded, model: discovery)
        XCTAssertEqual(settings.visionTags, ["another:vision"])
        XCTAssertTrue(settings.configuredModelUnavailable)

        let resolved = try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: configPath)
        XCTAssertEqual(resolved.modelEndpoint.absoluteString, settings.endpoint)
    }

    func testRuntimeAutomaticCheckUsesCacheAndManualCheckForcesRefresh() async throws {
        let loader = ControlledVisionTagLoader()
        let discovery = VisionTagsModel(loader: { endpoint in
            try await loader.load(endpoint)
        })
        let runtime = RuntimeGuidanceModel(configPath: missingConfigPath(), visionTagsModel: discovery)

        runtime.loadIfNeeded(environment: [:])
        try await waitForCallCount(1, loader: loader)
        XCTAssertEqual(runtime.status, .checking)

        await loader.succeed(callAt: 0, tags: ["one:vision", "two:vision"])
        try await waitForRuntimeStatus(.ready(visionTagCount: 2), model: runtime)
        XCTAssertNotNil(runtime.lastChecked)

        runtime.loadIfNeeded(environment: [:])
        for _ in 0..<5 {
            await Task.yield()
        }
        let cachedCallCount = await loader.callCount
        XCTAssertEqual(cachedCallCount, 1)
        XCTAssertEqual(runtime.status, .ready(visionTagCount: 2))

        runtime.check(environment: [:])
        try await waitForCallCount(2, loader: loader)
        XCTAssertEqual(runtime.status, .checking)
        await loader.succeed(callAt: 1, tags: [])
        try await waitForRuntimeStatus(.noVisionModels, model: runtime)
        XCTAssertTrue(runtime.needsAttention)
    }

    func testRuntimeConfigFailureDoesNotCallDiscoveryOrSetLastChecked() async throws {
        let loader = ControlledVisionTagLoader()
        let discovery = VisionTagsModel(loader: { endpoint in
            try await loader.load(endpoint)
        })
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vision-tags-invalid-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let configURL = root.appendingPathComponent("config.json")
        try Data("not json".utf8).write(to: configURL)
        let runtime = RuntimeGuidanceModel(configPath: configURL.path, visionTagsModel: discovery)
        discovery.fail(message: "a prior surface failed without an endpoint")

        runtime.loadIfNeeded(environment: [:])

        XCTAssertEqual(runtime.status, .unknown)
        XCTAssertNil(runtime.lastChecked)
        let callCount = await loader.callCount
        XCTAssertEqual(callCount, 0)
    }

    private func waitForCallCount(
        _ expectedCount: Int,
        loader: ControlledVisionTagLoader
    ) async throws {
        for _ in 0..<200 {
            if await loader.callCount >= expectedCount {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out waiting for \(expectedCount) vision-tag loader call(s)")
        throw VisionTagsTestError.timeout
    }

    private func waitForState(
        _ expectedState: VisionTagState,
        model: VisionTagsModel
    ) async throws {
        for _ in 0..<200 {
            if model.state == expectedState {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out waiting for vision-tag state \(expectedState)")
        throw VisionTagsTestError.timeout
    }

    private func waitForRuntimeStatus(
        _ expectedStatus: RuntimeGuidanceModel.Status,
        model: RuntimeGuidanceModel
    ) async throws {
        for _ in 0..<200 {
            if model.status == expectedStatus {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out waiting for runtime-guidance status \(expectedStatus)")
        throw VisionTagsTestError.timeout
    }

    private func missingConfigPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vision-tags-missing-\(UUID().uuidString).json")
            .path
    }
}

private struct LocalizedLoaderError: LocalizedError, Sendable {
    var errorDescription: String? { "localized loader failure" }
}

private enum VisionTagsTestError: Error {
    case timeout
    case unexpectedLoaderCall
}

private actor ControlledVisionTagLoader {
    private var capturedEndpoints: [URL] = []
    private var continuations: [Int: CheckedContinuation<[String], any Error>] = [:]

    var callCount: Int { capturedEndpoints.count }
    var endpoints: [URL] { capturedEndpoints }

    func load(_ endpoint: URL) async throws -> [String] {
        let callIndex = capturedEndpoints.count
        capturedEndpoints.append(endpoint)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[callIndex] = continuation
        }
    }

    func succeed(callAt index: Int, tags: [String]) {
        guard let continuation = continuations.removeValue(forKey: index) else {
            preconditionFailure("No pending vision-tag call at index \(index)")
        }
        continuation.resume(returning: tags)
    }

    func fail<E: Error & Sendable>(callAt index: Int, error: E) {
        guard let continuation = continuations.removeValue(forKey: index) else {
            preconditionFailure("No pending vision-tag call at index \(index)")
        }
        continuation.resume(throwing: error)
    }
}
