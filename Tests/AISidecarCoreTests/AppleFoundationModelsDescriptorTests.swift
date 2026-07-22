import Foundation
import XCTest

@testable import AISidecarCore

final class AppleFoundationModelsDescriptorTests: XCTestCase {
    private let expectedReason =
        "requires a vision-capable Apple on-device model; current macOS/FoundationModels does not provide image input for this workload (expected in a future macOS release)"

    func testDescriptorIsAlwaysUnavailableForVisionWork() async {
        let descriptor = AppleFoundationModelsDescriptor()

        XCTAssertEqual(descriptor.id, .apple)
        XCTAssertEqual(descriptor.displayName, "Apple on-device")
        XCTAssertEqual(descriptor.supportedTuningKnobs, [])
        let availability = await descriptor.availability(configuration: .builtInDefaults)
        XCTAssertEqual(
            availability,
            .unavailable(reason: expectedReason, guidance: descriptor.guidance)
        )
        XCTAssertTrue(descriptor.makeRunner() is AppleFoundationModelsRunner)
    }

    func testDescriptorDiscoveryAndStubPrepareFailSafely() async {
        let descriptor = AppleFoundationModelsDescriptor()

        do {
            _ = try await descriptor.discoverModels(configuration: .builtInDefaults)
            XCTFail("expected dark adapter discovery to fail")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelBackendUnavailable)
            XCTAssertEqual(error.stage, .model)
            XCTAssertEqual(error.message, expectedReason)
            XCTAssertTrue(error.recoverable)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        do {
            _ = try await AppleFoundationModelsRunner().prepare(configuration: .builtInDefaults)
            XCTFail("expected dark adapter prepare to fail")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelBackendUnavailable)
            XCTAssertEqual(error.stage, .model)
            XCTAssertEqual(error.message, "Model backend 'apple' is unavailable: \(expectedReason)")
            XCTAssertTrue(error.recoverable)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAppleProvenanceIdentifiersArePinned() {
        XCTAssertEqual(AppleFoundationModelsRunner.runtimeIdentifier, "apple-foundation-models")
        XCTAssertEqual(AppleFoundationModelsRunner.modelIdentifier, "system-language-model")
        XCTAssertEqual(
            AppleFoundationModelsRunner.runtimeVersion(
                for: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
            ),
            "26.0"
        )
        XCTAssertEqual(
            AppleFoundationModelsRunner.runtimeVersion(
                for: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 2)
            ),
            "26.1.2"
        )
        XCTAssertEqual(AppleFoundationModelsRunner.modelDigest(osBuild: "25A123"), "system:25A123")
        XCTAssertFalse(AppleFoundationModelsRunner.currentRuntimeVersion.isEmpty)
        XCTAssertTrue(AppleFoundationModelsRunner.currentModelDigest.hasPrefix("system:"))
    }

    func testLiveRegistryListsAppleBeforeOllamaAndAutoSkipsDarkAdapter() async throws {
        XCTAssertEqual(VisionBackendRegistry.live.descriptors.map(\.id), [.apple, .ollama])

        let fallback = AvailableFallbackDescriptor()
        let registry = VisionBackendRegistry(descriptors: [AppleFoundationModelsDescriptor(), fallback])
        let factory = VisionModelRunnerFactory(registry: registry)
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .auto

        let selected = try await factory.resolveBackend(for: configuration)

        XCTAssertEqual(selected.id, .ollama)
    }
}

private struct AvailableFallbackDescriptor: VisionBackendDescriptor {
    let id = ModelBackend.ollama
    let displayName = "Offline fallback"
    let guidance = BackendGuidance(runtimeUnavailableMessage: "offline test")
    let supportedTuningKnobs: Set<ModelTuningKnob> = []

    func availability(configuration _: ResolvedRunConfiguration) async -> BackendAvailability {
        .available
    }

    func discoverModels(configuration _: ResolvedRunConfiguration) async throws -> [BackendModelChoice] {
        []
    }

    func makeRunner() -> any VisionModelRunner {
        AppleFoundationModelsRunner()
    }
}
