import Foundation
import XCTest
@testable import AISidecarCore

final class ModelRuntimeTests: XCTestCase {
    func testPrepareResolvesTagDigestRuntimeVersionAndVisionTags() async throws {
        let transport = RecordingOllamaTransport([
            .success(jsonResponse("""
            {"models":[{"name":"gemma4:26b-a4b-it-qat","model":"gemma4:26b-a4b-it-qat","digest":"abc123"}]}
            """)),
            .success(jsonResponse(#"{"capabilities":["completion","vision"]}"#)),
            .success(jsonResponse(#"{"capabilities":["completion","vision"]}"#)),
            .success(jsonResponse(#"{"version":"0.12.6"}"#))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let context = try await runner.prepare(configuration: .builtInDefaults)

        XCTAssertEqual(context.model, "gemma4:26b-a4b-it-qat")
        XCTAssertEqual(context.modelDigest, "sha256:abc123")
        XCTAssertEqual(context.runtime, "ollama")
        XCTAssertEqual(context.runtimeVersion, "0.12.6")
        XCTAssertEqual(context.installedVisionTags, ["gemma4:26b-a4b-it-qat"])
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.map(\.path), ["/api/tags", "/api/show", "/api/show", "/api/version"])
    }

    func testPrepareMissingTagFailsWithVisionCapableSuggestions() async throws {
        let transport = RecordingOllamaTransport([
            .success(jsonResponse("""
            {
              "models": [
                {"name":"text:model","model":"text:model","digest":"111"},
                {"name":"vision:model","model":"vision:model","digest":"222"}
              ]
            }
            """)),
            .success(jsonResponse(#"{"capabilities":["completion"]}"#)),
            .success(jsonResponse(#"{"capabilities":["completion","vision"]}"#))
        ])
        let runner = OllamaVisionRunner(transport: transport)
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.model = "missing:model"

        do {
            _ = try await runner.prepare(configuration: configuration)
            XCTFail("Expected E_MODEL_TAG_NOT_FOUND")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelTagNotFound)
            XCTAssertEqual(error.stage, .model)
            XCTAssertFalse(error.recoverable)
            XCTAssertTrue(error.message.contains("vision:model"))
            XCTAssertFalse(error.message.contains("text:model,"))
        }
    }

    func testPrepareInstalledNonVisionTagFailsWithVisionCapableSuggestions() async throws {
        let transport = RecordingOllamaTransport([
            .success(jsonResponse("""
            {
              "models": [
                {"name":"text:model","model":"text:model","digest":"111"},
                {"name":"vision:model","model":"vision:model","digest":"222"}
              ]
            }
            """)),
            .success(jsonResponse(#"{"capabilities":["completion"]}"#)),
            .success(jsonResponse(#"{"capabilities":["completion","vision"]}"#)),
            .success(jsonResponse(#"{"capabilities":["completion"]}"#))
        ])
        let runner = OllamaVisionRunner(transport: transport)
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.model = "text:model"

        do {
            _ = try await runner.prepare(configuration: configuration)
            XCTFail("Expected E_MODEL_TAG_NOT_FOUND")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelTagNotFound)
            XCTAssertTrue(error.message.contains("vision:model"))
        }
    }

    func testPrepareEndpointFailureMapsToStructuredError() async {
        let transport = RecordingOllamaTransport([
            .failure(OllamaHTTPTransportError.unreachable("connection refused"))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        do {
            _ = try await runner.prepare(configuration: .builtInDefaults)
            XCTFail("Expected E_MODEL_ENDPOINT_UNREACHABLE")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelEndpointUnreachable)
            XCTAssertEqual(error.stage, .model)
        } catch {
            XCTFail("Expected SidecarError")
        }
    }

    func testAnalyzeEncodesOllamaChatRequestAndValidResponseRecord() async throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let inputData = Data("image-bytes".utf8)
        let imageURL = root.appendingPathComponent("whole.jpg")
        try inputData.write(to: imageURL)
        let rawResponse = wholeImageModelResponseJSON()
        let transport = RecordingOllamaTransport([
            .success(chatResponse(content: rawResponse))
        ])
        let runner = OllamaVisionRunner(
            transport: transport,
            now: fixedDateProvider(Date(timeIntervalSince1970: 1_900_000_000))
        )
        let options = ModelRunOptions(temperature: 0, seed: 42, keepAlive: "30m", timeoutSeconds: 12, contextWindow: 4096)
        let prompt = try PromptRegistry.prompt(for: .wholeImage)
        let schema = try ResponseSchemas.schema(for: .wholeImage)
        let image = derivative(cachePath: imageURL.path, sha256: "image-sha")

        let record = await runner.analyze(
            image: image,
            inputRole: .wholeImage,
            prompt: prompt,
            schema: schema,
            options: options,
            runtime: runtimeContext()
        )

        XCTAssertTrue(record.jsonValid)
        XCTAssertNil(record.error)
        XCTAssertEqual(record.rawResponseText, rawResponse)
        XCTAssertEqual(record.inputDerivativeSHA256, "image-sha")
        XCTAssertEqual(record.responseSchemaVersion, "urn:aisidecar:response:whole-image:1.1.0")
        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/api/chat")
        XCTAssertEqual(request.timeoutSeconds, 12)
        let body = try decodeJSONObject(from: try XCTUnwrap(request.body))
        XCTAssertEqual(body["model"]?.stringValue, "gemma4:26b-a4b-it-qat")
        XCTAssertEqual(body["stream"]?.boolValue, false)
        XCTAssertEqual(body["think"]?.boolValue, false)
        XCTAssertEqual(body["keep_alive"]?.stringValue, "30m")
        XCTAssertEqual(body["format"], schema.schema)
        let message = try XCTUnwrap(body["messages"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(message["content"]?.stringValue, prompt.text)
        XCTAssertEqual(message["images"]?.arrayValue?.first?.stringValue, inputData.base64EncodedString())
        let requestOptions = try XCTUnwrap(body["options"]?.objectValue)
        XCTAssertEqual(requestOptions["temperature"]?.numberValue, 0)
        XCTAssertEqual(requestOptions["seed"]?.numberValue, 42)
        XCTAssertEqual(requestOptions["num_ctx"]?.numberValue, 4096)
    }

    func testAnalyzeRetriesTimeoutsAndTransportErrorsOnly() async throws {
        let imageURL = try writeModelInput()
        let transport = RecordingOllamaTransport([
            .failure(OllamaHTTPTransportError.timeout("first timeout")),
            .failure(OllamaHTTPTransportError.unreachable("temporary transport failure")),
            .success(chatResponse(content: #"{"summary":"Recovered"}"#))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: 2),
            runtime: runtimeContext()
        )

        XCTAssertTrue(record.jsonValid)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 3)
    }

    func testAnalyzeClassifiesExhaustedTimeoutAndEndpointFailures() async throws {
        let imageURL = try writeModelInput()
        let timeoutTransport = RecordingOllamaTransport([
            .failure(OllamaHTTPTransportError.timeout("a")),
            .failure(OllamaHTTPTransportError.timeout("b")),
            .failure(OllamaHTTPTransportError.timeout("c"))
        ])
        let timeoutRunner = OllamaVisionRunner(transport: timeoutTransport)

        let timeoutRecord = await timeoutRunner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: 2),
            runtime: runtimeContext()
        )

        XCTAssertEqual(timeoutRecord.error?.code, .modelTimeout)
        let timeoutRequests = await timeoutTransport.capturedRequests()
        XCTAssertEqual(timeoutRequests.count, 3)

        let endpointTransport = RecordingOllamaTransport([
            .failure(OllamaHTTPTransportError.unreachable("a")),
            .failure(OllamaHTTPTransportError.unreachable("b")),
            .failure(OllamaHTTPTransportError.unreachable("c"))
        ])
        let endpointRunner = OllamaVisionRunner(transport: endpointTransport)

        let endpointRecord = await endpointRunner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: 2),
            runtime: runtimeContext()
        )

        XCTAssertEqual(endpointRecord.error?.code, .modelEndpointUnreachable)
        let endpointRequests = await endpointTransport.capturedRequests()
        XCTAssertEqual(endpointRequests.count, 3)
    }

    func testAnalyzePreservesFencedJSONWithoutError() async throws {
        let imageURL = try writeModelInput()
        let raw = """
        ```json
        {"summary":"Fenced response"}
        ```
        """
        let transport = RecordingOllamaTransport([
            .success(chatResponse(content: raw))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: .default,
            runtime: runtimeContext()
        )

        XCTAssertTrue(record.jsonValid)
        XCTAssertNil(record.error)
        XCTAssertEqual(record.rawResponseText, raw)
        XCTAssertEqual(record.parsedResponseJSON?.objectValue?["summary"]?.stringValue, "Fenced response")
    }

    func testAnalyzeInvalidJSONAndSchemaViolationDoNotRetry() async throws {
        let imageURL = try writeModelInput()
        let invalidTransport = RecordingOllamaTransport([
            .success(chatResponse(content: "not json"))
        ])
        let invalidRunner = OllamaVisionRunner(transport: invalidTransport)

        let invalidRecord = await invalidRunner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: 2),
            runtime: runtimeContext()
        )

        XCTAssertFalse(invalidRecord.jsonValid)
        XCTAssertEqual(invalidRecord.error?.code, .modelInvalidJSON)
        XCTAssertEqual(invalidRecord.rawResponseText, "not json")
        XCTAssertNil(invalidRecord.parsedResponseJSON)
        let invalidRequests = await invalidTransport.capturedRequests()
        XCTAssertEqual(invalidRequests.count, 1)

        let violationTransport = RecordingOllamaTransport([
            .success(chatResponse(content: #"{"summary":5}"#))
        ])
        let violationRunner = OllamaVisionRunner(transport: violationTransport)

        let violationRecord = await violationRunner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: 2),
            runtime: runtimeContext()
        )

        XCTAssertFalse(violationRecord.jsonValid)
        XCTAssertEqual(violationRecord.error?.code, .modelSchemaViolation)
        XCTAssertEqual(violationRecord.parsedResponseJSON?.objectValue?["summary"]?.numberValue, 5)
        let violationRequests = await violationTransport.capturedRequests()
        XCTAssertEqual(violationRequests.count, 1)
    }

    func testSidecarSerializesConcreteModelRunRecords() throws {
        let record = modelRunRecord()
        let sidecar = RawJSONSidecar(
            source: makeSource(fileName: "Bird.NEF", relativePath: "Bird.NEF"),
            runConfiguration: .builtInDefaults,
            modelRuns: [record],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let data = try encoder.encode(sidecar)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""model_runs":[{"#))
        XCTAssertTrue(json.contains(#""prompt_sha256":"#))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RawJSONSidecar.self, from: data)
        XCTAssertEqual(decoded.modelRuns, [record])
    }

    func testMockAndRecordedFixtureRunnersReturnIdenticalRecords() async throws {
        let context = runtimeContext()
        let record = modelRunRecord()
        let image = derivative(cachePath: "/tmp/whole.jpg", sha256: record.inputDerivativeSHA256)
        let prompt = VersionedPrompt(version: "prompt/1.0", text: "Prompt")
        let schema = try summarySchema()
        let mock = MockVisionModelRunner(context: context, record: record)
        let fixture = RecordedFixtureRunner(fixture: RecordedModelFixture(context: context, records: [record]))

        let mockContext = try await mock.prepare(configuration: .builtInDefaults)
        let fixtureContext = try await fixture.prepare(configuration: .builtInDefaults)
        let mockRecord = await mock.analyze(
            image: image,
            inputRole: .wholeImage,
            prompt: prompt,
            schema: schema,
            options: .default,
            runtime: mockContext
        )
        let fixtureRecord = await fixture.analyze(
            image: image,
            inputRole: .wholeImage,
            prompt: prompt,
            schema: schema,
            options: .default,
            runtime: fixtureContext
        )

        XCTAssertEqual(mockContext, fixtureContext)
        XCTAssertEqual(mockRecord, fixtureRecord)
    }

    func testLiveOllamaPrepareWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["AISIDECAR_RUN_LIVE_OLLAMA_TESTS"] == "1" else {
            throw XCTSkip("Set AISIDECAR_RUN_LIVE_OLLAMA_TESTS=1 to run the live Ollama smoke test.")
        }

        let context = try await OllamaVisionRunner().prepare(configuration: .builtInDefaults)

        XCTAssertEqual(context.runtime, "ollama")
        XCTAssertFalse(context.modelDigest.isEmpty)
    }

    private func summarySchema() throws -> JSONSchemaDocument {
        try JSONSchemaDocument(
            version: "test-summary-schema/1.0",
            schemaJSON: """
            {
              "type": "object",
              "required": ["summary"],
              "properties": {
                "summary": { "type": "string", "minLength": 1, "maxLength": 80 }
              },
              "additionalProperties": false
            }
            """
        )
    }

    private func runtimeContext() -> ModelRuntimeContext {
        ModelRuntimeContext(
            model: "gemma4:26b-a4b-it-qat",
            modelDigest: "sha256:abc123",
            runtimeVersion: "0.12.6",
            endpoint: URL(string: "http://localhost:11434")!,
            installedVisionTags: ["gemma4:26b-a4b-it-qat"]
        )
    }

    private func derivative(cachePath: String, sha256: String = "derivative-sha") -> DerivativeRecord {
        DerivativeRecord(
            role: .wholeImage,
            cachePath: cachePath,
            format: .jpeg,
            width: 64,
            height: 32,
            colorSpace: .sRGB,
            appliedOrientation: AppliedOrientation(exifValue: 1),
            recipeVersion: "render-v1-test",
            sha256: sha256,
            sourceIdentity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
        )
    }

    private func modelRunRecord() -> ModelRunRecord {
        let prompt = VersionedPrompt(version: "prompt/1.0", text: "Prompt")
        return ModelRunRecord(
            inputRole: .wholeImage,
            model: "gemma4:26b-a4b-it-qat",
            modelDigest: "sha256:abc123",
            runtime: "ollama",
            runtimeVersion: "0.12.6",
            promptVersion: prompt.version,
            promptSHA256: prompt.sha256,
            responseSchemaVersion: "test-summary-schema/1.0",
            requestOptions: .default,
            inputDerivativeSHA256: "derivative-sha",
            rawResponseText: #"{"summary":"A heron"}"#,
            parsedResponseJSON: .object(["summary": .string("A heron")]),
            jsonValid: true,
            durationMs: 12,
            error: nil
        )
    }

    private func writeModelInput() throws -> URL {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("whole.jpg")
        try Data("image-bytes".utf8).write(to: imageURL)
        return imageURL
    }

    private func wholeImageModelResponseJSON() -> String {
        """
        {
          "summary": "A great blue heron stands in shallow wetland water.",
          "genre_or_photography_type": [
            {
              "term": "bird_photography",
              "confidence": "high",
              "evidence": "large wading bird dominates frame"
            }
          ],
          "main_subjects": [
            {
              "term": "great blue heron",
              "confidence": "medium",
              "evidence": "large gray-blue wading bird"
            }
          ],
          "secondary_subjects": [
            {
              "term": "shallow water",
              "confidence": "high",
              "evidence": "ripples around the bird's legs"
            }
          ],
          "scene_context": [
            {
              "term": "outdoor wildlife scene",
              "confidence": "high"
            }
          ],
          "habitat_or_setting": [
            {
              "term": "wetland",
              "confidence": "medium"
            }
          ],
          "behavior_or_action": [
            {
              "term": "standing",
              "confidence": "high"
            }
          ],
          "visible_text": [],
          "proposed_keywords": [
            {
              "term": "wading bird",
              "confidence": "high",
              "evidence": "long legs in shallow water"
            }
          ],
          "uncertainty_notes": ""
        }
        """
    }

    private func fixedDateProvider(_ date: Date) -> @Sendable () -> Date {
        { date }
    }
}

private actor RecordingOllamaTransport: OllamaHTTPTransport {
    private var responses: [Result<OllamaHTTPResponse, Error>]
    private var requests: [OllamaHTTPRequest] = []

    init(_ responses: [Result<OllamaHTTPResponse, Error>]) {
        self.responses = responses
    }

    func capturedRequests() -> [OllamaHTTPRequest] {
        requests
    }

    func send(_ request: OllamaHTTPRequest, endpoint _: URL) async throws -> OllamaHTTPResponse {
        requests.append(request)
        let response = responses.isEmpty
            ? .failure(OllamaHTTPTransportError.unreachable("No stubbed Ollama response."))
            : responses.removeFirst()

        switch response {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

private func jsonResponse(_ json: String, statusCode: Int = 200) -> OllamaHTTPResponse {
    OllamaHTTPResponse(statusCode: statusCode, data: Data(json.utf8))
}

private func chatResponse(content: String, statusCode: Int = 200) -> OllamaHTTPResponse {
    let escaped = content
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return jsonResponse(#"{"message":{"content":""# + escaped + #""}}"#, statusCode: statusCode)
}

private func decodeJSONObject(from data: Data) throws -> [String: JSONValue] {
    guard let object = try JSONDecoder().decode(JSONValue.self, from: data).objectValue else {
        throw XCTSkip("Expected JSON object")
    }
    return object
}
