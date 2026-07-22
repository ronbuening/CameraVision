import Foundation
import XCTest

@testable import AISidecarCore

final class VisionBackendDescriptorTests: XCTestCase {
    func testOllamaAvailabilityMapsTransportFailureToGuidance() async {
        let descriptor = OllamaBackendDescriptor(
            runner: OllamaVisionRunner(
                transport: DescriptorOllamaTransport([
                    .failure(OllamaHTTPTransportError.unreachable("connection refused"))
                ])))

        let availability = await descriptor.availability(configuration: .builtInDefaults)

        XCTAssertEqual(
            availability,
            .unavailable(
                reason: "Unable to reach Ollama endpoint: connection refused",
                guidance: descriptor.guidance
            ))
        XCTAssertEqual(descriptor.guidance.downloadURL?.absoluteString, "https://ollama.com/download")
        XCTAssertEqual(descriptor.guidance.serveCommand, "ollama serve")
        XCTAssertEqual(descriptor.guidance.pullCommand(for: "starter:latest"), "ollama pull starter:latest")
    }

    func testOllamaAvailabilityTreatsReachableEmptyInventoryAsAvailable() async {
        let descriptor = OllamaBackendDescriptor(
            runner: OllamaVisionRunner(
                transport: DescriptorOllamaTransport([
                    .success(response(#"{"models":[]}"#))
                ])))

        let availability = await descriptor.availability(configuration: .builtInDefaults)

        XCTAssertEqual(availability, .available)
    }

    func testOllamaDiscoveryPassesThroughSortedVisionChoices() async throws {
        let descriptor = OllamaBackendDescriptor(
            runner: OllamaVisionRunner(
                transport: DescriptorOllamaTransport([
                    .success(
                        response(
                            """
                            {"models":[
                              {"name":"z-vision:latest","model":"z-vision:latest","digest":"a"},
                              {"name":"text-only:latest","model":"text-only:latest","digest":"b"},
                              {"name":"a-vision:latest","model":"a-vision:latest","digest":"c"}
                            ]}
                            """)),
                    .success(response(#"{"capabilities":["vision"]}"#)),
                    .success(response(#"{"capabilities":["completion"]}"#)),
                    .success(response(#"{"capabilities":["completion","vision"]}"#)),
                ])))

        let choices = try await descriptor.discoverModels(configuration: .builtInDefaults)

        XCTAssertEqual(
            choices,
            [
                BackendModelChoice(id: "a-vision:latest", displayName: "a-vision:latest"),
                BackendModelChoice(id: "z-vision:latest", displayName: "z-vision:latest"),
            ])
    }

    func testOllamaDescriptorExposesAllCurrentTuningControlsAndRunner() {
        let descriptor = OllamaBackendDescriptor()

        XCTAssertEqual(descriptor.id, .ollama)
        XCTAssertEqual(descriptor.displayName, "Ollama")
        XCTAssertEqual(descriptor.supportedTuningKnobs, Set(ModelTuningKnob.allCases))
        XCTAssertTrue(descriptor.makeRunner() is OllamaVisionRunner)
    }

    func testRegistryPreservesDeclaredOrderAndLooksUpConcreteBackend() {
        let first = OllamaBackendDescriptor()
        let second = OllamaBackendDescriptor()
        let registry = VisionBackendRegistry(descriptors: [first, second])

        XCTAssertEqual(registry.descriptors.map(\.id), [.ollama, .ollama])
        XCTAssertEqual(registry.descriptor(for: .ollama)?.displayName, "Ollama")
        XCTAssertNil(registry.descriptor(for: .auto))
    }

    private func response(_ json: String) -> OllamaHTTPResponse {
        OllamaHTTPResponse(statusCode: 200, data: Data(json.utf8))
    }
}

private actor DescriptorOllamaTransport: OllamaHTTPTransport {
    private var responses: [Result<OllamaHTTPResponse, Error>]

    init(_ responses: [Result<OllamaHTTPResponse, Error>]) {
        self.responses = responses
    }

    func send(_ request: OllamaHTTPRequest, endpoint: URL) async throws -> OllamaHTTPResponse {
        guard !responses.isEmpty else {
            throw OllamaHTTPTransportError.unreachable("No stubbed response for \(request.path) at \(endpoint).")
        }
        return try responses.removeFirst().get()
    }
}
