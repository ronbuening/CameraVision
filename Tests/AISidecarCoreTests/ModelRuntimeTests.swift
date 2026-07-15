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

        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelTimeoutSeconds = 42
        let context = try await runner.prepare(configuration: configuration)

        XCTAssertEqual(context.model, "gemma4:26b-a4b-it-qat")
        XCTAssertEqual(context.modelDigest, "sha256:abc123")
        XCTAssertEqual(context.runtime, "ollama")
        XCTAssertEqual(context.runtimeVersion, "0.12.6")
        XCTAssertEqual(context.installedVisionTags, ["gemma4:26b-a4b-it-qat"])
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.map(\.path), ["/api/tags", "/api/show", "/api/show", "/api/version"])
        XCTAssertEqual(requests.map(\.timeoutSeconds), [42, 42, 42, 42])
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

    func testPrepareTagDiagnosticDistinguishesUnprobedInstalledModels() async throws {
        let transport = RecordingOllamaTransport([
            .success(jsonResponse("""
            {
              "models": [
                {"name":"vision:model","model":"vision:model","digest":"111"},
                {"name":"flaky:model","model":"flaky:model","digest":"222"}
              ]
            }
            """)),
            .success(jsonResponse(#"{"capabilities":["completion","vision"]}"#)),
            .failure(OllamaHTTPTransportError.unreachable("probe failed"))
        ])
        let runner = OllamaVisionRunner(transport: transport)
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.model = "missing:model"

        do {
            _ = try await runner.prepare(configuration: configuration)
            XCTFail("Expected E_MODEL_TAG_NOT_FOUND")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelTagNotFound)
            XCTAssertTrue(error.message.contains("vision:model"))
            XCTAssertTrue(error.message.contains("1 installed tag(s) could not be probed"))
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

    func testPrepareRetriesMalformedSuccessfulResponseOnce() async throws {
        let transport = RecordingOllamaTransport([
            .success(jsonResponse("{")),
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
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.map(\.path), ["/api/tags", "/api/tags", "/api/show", "/api/show", "/api/version"])
    }

    func testPrepareClassifiesRepeatedMalformedSuccessfulResponse() async {
        let transport = RecordingOllamaTransport([
            .success(jsonResponse("{")),
            .success(jsonResponse("{"))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        do {
            _ = try await runner.prepare(configuration: .builtInDefaults)
            XCTFail("Expected E_MODEL_RESPONSE_INVALID")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelResponseInvalid)
            XCTAssertTrue(error.message.contains("/api/tags"))
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
            .success(chatResponse(
                content: rawResponse,
                totalDuration: 21_000_000,
                loadDuration: 2_000_000,
                promptEvalCount: 31,
                promptEvalDuration: 3_000_000,
                evalCount: 41,
                evalDuration: 4_000_000
            ))
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
        XCTAssertEqual(record.responseSchemaVersion, "urn:aisidecar:response:whole-image:1.5.0")
        XCTAssertEqual(record.runtimeMetrics?.totalDurationNs, 21_000_000)
        XCTAssertEqual(record.runtimeMetrics?.loadDurationNs, 2_000_000)
        XCTAssertEqual(record.runtimeMetrics?.promptEvalCount, 31)
        XCTAssertEqual(record.runtimeMetrics?.promptEvalDurationNs, 3_000_000)
        XCTAssertEqual(record.runtimeMetrics?.evalCount, 41)
        XCTAssertEqual(record.runtimeMetrics?.evalDurationNs, 4_000_000)
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
        XCTAssertEqual(body["format"], OllamaWireSchema.wireSchema(from: schema.schema))
        let message = try XCTUnwrap(body["messages"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(message["content"]?.stringValue, prompt.text)
        XCTAssertEqual(message["images"]?.arrayValue?.first?.stringValue, inputData.base64EncodedString())
        let requestOptions = try XCTUnwrap(body["options"]?.objectValue)
        XCTAssertEqual(requestOptions["temperature"]?.numberValue, 0)
        XCTAssertEqual(requestOptions["seed"]?.numberValue, 42)
        XCTAssertEqual(requestOptions["num_ctx"]?.numberValue, 4096)
        XCTAssertEqual(requestOptions["num_predict"]?.numberValue, 2048)
    }

    func testAnalyzeRequestCarriesGPSContextInPromptText() async throws {
        let imageURL = try writeModelInput()
        let transport = RecordingOllamaTransport([
            .success(chatResponse(content: wholeImageModelResponseJSON()))
        ])
        let runner = OllamaVisionRunner(transport: transport)
        let prompt = try PromptRegistry.prompt(
            for: .wholeImage,
            context: ModelInputContext(gps: GPSModelInputContext(
                mode: .coarse,
                latitude: 45.1,
                longitude: -122.7,
                precisionDegrees: 0.1
            ))
        )

        _ = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: prompt,
            schema: try ResponseSchemas.schema(for: .wholeImage),
            options: .default,
            runtime: runtimeContext()
        )

        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try decodeJSONObject(from: try XCTUnwrap(request.body))
        let message = try XCTUnwrap(body["messages"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(message["content"]?.stringValue, prompt.text)
        XCTAssertTrue(message["content"]?.stringValue?.contains("MODEL INPUT CONTEXT") == true)
        XCTAssertTrue(message["content"]?.stringValue?.contains("latitude: 45.1") == true)
        XCTAssertTrue(message["content"]?.stringValue?.contains("longitude: -122.7") == true)
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

    func testAnalyzeAcceptsMaximumRetryLimitWithoutOverflowingAttemptCount() async throws {
        let imageURL = try writeModelInput()
        let transport = RecordingOllamaTransport([
            .success(chatResponse(content: #"{"summary":"Immediate success"}"#))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: .max),
            runtime: runtimeContext()
        )

        XCTAssertTrue(record.jsonValid)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testAnalyzeDoesNotRetryHTTP4xxAndIncludesOllamaErrorBody() async throws {
        let imageURL = try writeModelInput()
        let transport = RecordingOllamaTransport([
            .success(jsonResponse(#"{"error":"model requires more memory"}"#, statusCode: 400))
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

        XCTAssertEqual(record.error?.code, .modelEndpointUnreachable)
        XCTAssertTrue(record.error?.message.contains("model requires more memory") == true)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testAnalyzeRetriesHTTP5xxAndIncludesOllamaErrorBody() async throws {
        let imageURL = try writeModelInput()
        let transport = RecordingOllamaTransport([
            .success(jsonResponse(#"{"error":"server overloaded"}"#, statusCode: 503)),
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
        XCTAssertEqual(requests.count, 2)
    }

    func testAnalyzeReportsLastHTTP5xxErrorBodyAfterRetriesAreExhausted() async throws {
        let imageURL = try writeModelInput()
        let transport = RecordingOllamaTransport([
            .success(jsonResponse(#"{"error":"warming up"}"#, statusCode: 503)),
            .success(jsonResponse(#"{"error":"still overloaded"}"#, statusCode: 503))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: 1),
            runtime: runtimeContext()
        )

        XCTAssertEqual(record.error?.code, .modelEndpointUnreachable)
        XCTAssertTrue(record.error?.message.contains("still overloaded") == true)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
    }

    func testAnalyzeDoesNotEmbedOversizedOllamaErrorBody() async throws {
        let imageURL = try writeModelInput()
        let oversizedDetail = String(repeating: "private-diagnostic-", count: 4_000)
        let body = try JSONEncoder().encode(["error": oversizedDetail])
        let transport = RecordingOllamaTransport([
            .success(OllamaHTTPResponse(statusCode: 400, data: body))
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

        XCTAssertEqual(record.error?.code, .modelEndpointUnreachable)
        XCTAssertFalse(record.error?.message.contains("private-diagnostic") == true)
        XCTAssertTrue(record.error?.message.contains("HTTP 400 from /api/chat") == true)
    }

    func testAnalyzeRetriesMalformedSuccessfulResponseOnce() async throws {
        let imageURL = try writeModelInput()
        let transport = RecordingOllamaTransport([
            .success(jsonResponse(#"{"unexpected":true}"#)),
            .success(chatResponse(content: #"{"summary":"Recovered"}"#))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: 0),
            runtime: runtimeContext()
        )

        XCTAssertTrue(record.jsonValid)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
    }

    func testAnalyzeInterruptionPreventsMalformedResponseRetry() async throws {
        let imageURL = try writeModelInput()
        let monitor = InterruptionMonitor()
        let transport = RecordingOllamaTransport(
            [
                .success(jsonResponse(#"{"unexpected":true}"#)),
                .success(chatResponse(content: #"{"summary":"never reached"}"#))
            ],
            onSend: { requestCount in
                if requestCount == 1 {
                    monitor.requestInterruption()
                }
            }
        )
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: 2),
            runtime: runtimeContext(),
            isInterrupted: { monitor.isInterrupted }
        )

        XCTAssertEqual(record.error?.code, .interrupted)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testAnalyzeClassifiesRepeatedMalformedSuccessfulResponse() async throws {
        let imageURL = try writeModelInput()
        let transport = RecordingOllamaTransport([
            .success(jsonResponse(#"{"unexpected":true}"#)),
            .success(jsonResponse(#"{"unexpected":true}"#))
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

        XCTAssertEqual(record.error?.code, .modelResponseInvalid)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
    }

    func testAnalyzeStopsRetryingWhenInterruptedBetweenAttempts() async throws {
        let imageURL = try writeModelInput()
        let monitor = InterruptionMonitor()
        let transport = RecordingOllamaTransport(
            [
                .failure(OllamaHTTPTransportError.unreachable("first failure")),
                .success(chatResponse(content: #"{"summary":"never reached"}"#))
            ],
            onSend: { requestCount in
                if requestCount == 1 {
                    monitor.requestInterruption()
                }
            }
        )
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: 2),
            runtime: runtimeContext(),
            isInterrupted: { monitor.isInterrupted }
        )

        XCTAssertEqual(record.error?.code, .interrupted)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testAnalyzeStartsNoRequestWhenAlreadyInterrupted() async throws {
        let imageURL = try writeModelInput()
        let transport = RecordingOllamaTransport([
            .success(chatResponse(content: #"{"summary":"never reached"}"#))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(retryLimit: 2),
            runtime: runtimeContext(),
            isInterrupted: { true }
        )

        XCTAssertEqual(record.error?.code, .interrupted)
        let requests = await transport.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testAnalyzeMapsTransportCancellationToInterruptionWithoutRetrying() async throws {
        let imageURL = try writeModelInput()
        let transport = RecordingOllamaTransport([
            .failure(CancellationError()),
            .success(chatResponse(content: #"{"summary":"never reached"}"#))
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

        XCTAssertEqual(record.error?.code, .interrupted)
        XCTAssertEqual(record.error?.message, "Model request cancelled.")
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testInFlightRequestCancellationStopsHangingTransport() async throws {
        let imageURL = try writeModelInput()
        let monitor = InterruptionMonitor()
        let transport = CancellationAwareHangingTransport()
        let runner = OllamaVisionRunner(transport: transport)
        let prompt = VersionedPrompt(version: "prompt/1.0", text: "Prompt")
        let schema = try summarySchema()
        let image = derivative(cachePath: imageURL.path)
        let runtime = runtimeContext()
        let task = Task {
            await runner.analyze(
                image: image,
                inputRole: .wholeImage,
                prompt: prompt,
                schema: schema,
                options: ModelRunOptions(retryLimit: 2),
                runtime: runtime,
                isInterrupted: { monitor.isInterrupted }
            )
        }
        let registration = monitor.onInterruption { task.cancel() }

        await transport.waitUntilStarted()
        monitor.requestInterruption()
        let record = await task.value
        registration.cancel()

        XCTAssertEqual(record.error?.code, .interrupted)
        let requestCount = await transport.requestCount
        let wasCancelled = await transport.wasCancelled
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(wasCancelled)
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

    func testAnalyzeInvalidJSONAndSchemaViolationDoNotRepairWhenDisabled() async throws {
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
            options: ModelRunOptions(retryLimit: 2, responseRepairAttempts: 0),
            runtime: runtimeContext()
        )

        XCTAssertFalse(invalidRecord.jsonValid)
        XCTAssertEqual(invalidRecord.error?.code, .modelInvalidJSON)
        XCTAssertEqual(invalidRecord.rawResponseText, "not json")
        XCTAssertNil(invalidRecord.parsedResponseJSON)
        XCTAssertNil(invalidRecord.responseAttempts)
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
            options: ModelRunOptions(retryLimit: 2, responseRepairAttempts: 0),
            runtime: runtimeContext()
        )

        XCTAssertFalse(violationRecord.jsonValid)
        XCTAssertEqual(violationRecord.error?.code, .modelSchemaViolation)
        XCTAssertEqual(violationRecord.parsedResponseJSON?.objectValue?["summary"]?.numberValue, 5)
        XCTAssertNil(violationRecord.responseAttempts)
        let violationRequests = await violationTransport.capturedRequests()
        XCTAssertEqual(violationRequests.count, 1)
    }

    func testAnalyzeRepairsInvalidJSONWithSchemaConstrainedNoImageRequest() async throws {
        let imageURL = try writeModelInput()
        let repairedJSON = #"{"summary":"Recovered JSON"}"#
        let transport = RecordingOllamaTransport([
            .success(chatResponse(content: "not json")),
            .success(chatResponse(content: repairedJSON))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(responseRepairAttempts: 1),
            runtime: runtimeContext()
        )

        XCTAssertTrue(record.jsonValid)
        XCTAssertNil(record.error)
        XCTAssertEqual(record.rawResponseText, repairedJSON)
        XCTAssertEqual(record.parsedResponseJSON?.objectValue?["summary"]?.stringValue, "Recovered JSON")
        let attempts = try XCTUnwrap(record.responseAttempts)
        XCTAssertEqual(attempts.map(\.kind), [.primary, .repair])
        XCTAssertEqual(attempts.map(\.jsonValid), [false, true])
        XCTAssertEqual(attempts.first?.error?.code, .modelInvalidJSON)
        XCTAssertEqual(attempts.last?.requestOptions.temperature, 0)
        XCTAssertEqual(attempts.last?.requestOptions.thinkingEnabled, false)

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        let primaryBody = try decodeJSONObject(from: try XCTUnwrap(requests.first?.body))
        let primaryMessage = try XCTUnwrap(primaryBody["messages"]?.arrayValue?.first?.objectValue)
        XCTAssertNotNil(primaryMessage["images"]?.arrayValue)
        let repairBody = try decodeJSONObject(from: try XCTUnwrap(requests.last?.body))
        let repairMessage = try XCTUnwrap(repairBody["messages"]?.arrayValue?.first?.objectValue)
        XCTAssertNil(repairMessage["images"])
        XCTAssertTrue(repairMessage["content"]?.stringValue?.contains("not json") == true)
        XCTAssertEqual(repairBody["format"], OllamaWireSchema.wireSchema(from: try summarySchema().schema))
    }

    func testAnalyzeRepairsTruncatedQualityResponseWithQualitySchema() async throws {
        let imageURL = try writeModelInput()
        let truncated = String(decoding: try fixtureData(named: "whole_image_quality_truncated", extension: "txt"), as: UTF8.self)
        let repairedJSON = String(decoding: try fixtureData(named: "whole_image_with_quality_valid", extension: "json"), as: UTF8.self)
        let transport = RecordingOllamaTransport([
            .success(chatResponse(content: truncated)),
            .success(chatResponse(content: repairedJSON))
        ])
        let runner = OllamaVisionRunner(transport: transport)
        let prompt = try PromptRegistry.prompt(for: .wholeImage, task: .taggingWithQuality)
        let schema = try ResponseSchemas.schema(for: .wholeImage, task: .taggingWithQuality)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: prompt,
            schema: schema,
            options: ModelRunOptions(responseRepairAttempts: 1),
            runtime: runtimeContext()
        )

        XCTAssertTrue(record.jsonValid)
        XCTAssertNil(record.error)
        XCTAssertEqual(record.promptVersion, "aisidecar.prompt.whole_image/1.6.0")
        XCTAssertEqual(record.responseSchemaVersion, "urn:aisidecar:response:whole-image:1.6.0")
        XCTAssertEqual(
            record.parsedResponseJSON?.objectValue?["quality_assessment"]?.objectValue?["overall_effectiveness"]?.stringValue,
            "strong"
        )
        let attempts = try XCTUnwrap(record.responseAttempts)
        XCTAssertEqual(attempts.map(\.kind), [.primary, .repair])
        XCTAssertEqual(attempts.first?.error?.code, .modelInvalidJSON)
        XCTAssertEqual(attempts.last?.jsonValid, true)

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        let expectedWireSchema = OllamaWireSchema.wireSchema(from: schema.schema)
        let primaryBody = try decodeJSONObject(from: try XCTUnwrap(requests.first?.body))
        let repairBody = try decodeJSONObject(from: try XCTUnwrap(requests.last?.body))
        XCTAssertEqual(primaryBody["format"], expectedWireSchema)
        XCTAssertEqual(repairBody["format"], expectedWireSchema)
    }

    func testRepairInputTruncationBoundsEmbeddedOutput() {
        let short = String(repeating: "a", count: 100)
        XCTAssertEqual(OllamaVisionRunner.truncatedRepairInput(short), short)

        let head = String(repeating: "h", count: OllamaVisionRunner.repairInputHeadCharacters)
        let middle = String(repeating: "m", count: 40_000)
        let tail = String(repeating: "t", count: OllamaVisionRunner.repairInputTailCharacters)
        let truncated = OllamaVisionRunner.truncatedRepairInput(head + middle + tail)

        XCTAssertTrue(truncated.hasPrefix(head))
        XCTAssertTrue(truncated.hasSuffix(tail))
        XCTAssertTrue(truncated.contains("[... output truncated for repair ...]"))
        XCTAssertLessThan(
            truncated.count,
            OllamaVisionRunner.repairInputHeadCharacters + OllamaVisionRunner.repairInputTailCharacters + 100
        )
    }

    func testWireSchemaInlinesRefsAndStripsUnsupportedKeywords() throws {
        // Probing Ollama 0.30.10 + gemma4 showed $ref/$defs and pattern
        // silently disable grammar enforcement; the wire schema must never
        // contain them while keeping the enforceable core, including the
        // string length bounds that stop in-string repetition loops.
        for role in ModelInputRole.allCases {
            let schema = try ResponseSchemas.schema(for: role)
            let wire = OllamaWireSchema.wireSchema(from: schema.schema)
            let encoded = String(decoding: try JSONEncoder().encode(wire), as: UTF8.self)
            for forbidden in ["$ref", "$defs", "pattern", "description", "$schema", "$id", "title"] {
                XCTAssertFalse(encoded.contains("\"\(forbidden)\""), "\(role.rawValue) wire schema contains \(forbidden)")
            }

            let root = try XCTUnwrap(wire.objectValue)
            let required = try XCTUnwrap(root["required"]?.arrayValue?.compactMap(\.stringValue))
            XCTAssertTrue(required.contains("species"))
            XCTAssertEqual(root["additionalProperties"], .bool(false))

            // Candidate defs are inlined with their required keys and the
            // grammar-enforceable array bounds intact.
            let properties = try XCTUnwrap(root["properties"]?.objectValue)
            let species = try XCTUnwrap(properties["species"]?.objectValue)
            XCTAssertEqual(species["maxItems"]?.numberValue, 6)
            let item = try XCTUnwrap(species["items"]?.objectValue)
            XCTAssertEqual(
                item["required"]?.arrayValue?.compactMap(\.stringValue).sorted(),
                ["confidence", "evidence", "term"]
            )
            let evidence = try XCTUnwrap(item["properties"]?.objectValue?["evidence"]?.objectValue)
            XCTAssertEqual(evidence["maxLength"]?.numberValue, 220)
            let genre = try XCTUnwrap(properties["genre_or_photography_type"]?.objectValue)
            XCTAssertEqual(genre["minItems"]?.numberValue, 1)
            let genreTerm = try XCTUnwrap(genre["items"]?.objectValue?["properties"]?.objectValue?["term"]?.objectValue)
            XCTAssertNotNil(genreTerm["enum"]?.arrayValue)
        }
    }

    func testQualityWireSchemasPreserveGrammarBounds() throws {
        let contracts: [(ModelInputRole, ModelTaskProfile)] = [
            (.wholeImage, .taggingWithQuality), (.subjectIsolated, .taggingWithQuality),
            (.wholeImage, .qualityOnly), (.subjectIsolated, .qualityOnly),
        ]

        for (role, task) in contracts {
            let wire = OllamaWireSchema.wireSchema(from: try ResponseSchemas.schema(for: role, task: task).schema)
            let encoded = String(decoding: try JSONEncoder().encode(wire), as: UTF8.self)
            for forbidden in ["$ref", "$defs", "pattern", "description", "$schema", "$id", "title"] {
                XCTAssertFalse(encoded.contains("\"\(forbidden)\""), "\(role.rawValue)/\(task.rawValue) contains \(forbidden)")
            }
            let root = try XCTUnwrap(wire.objectValue)
            XCTAssertTrue(try XCTUnwrap(root["required"]?.arrayValue?.compactMap(\.stringValue)).contains("quality_assessment"))
            let assessment = try XCTUnwrap(root["properties"]?.objectValue?["quality_assessment"]?.objectValue)
            XCTAssertEqual(assessment["additionalProperties"], .bool(false))
            let properties = try XCTUnwrap(assessment["properties"]?.objectValue)
            for name in ["strengths", "concerns"] {
                let notes = try XCTUnwrap(properties[name]?.objectValue)
                XCTAssertEqual(notes["maxItems"]?.numberValue, 2)
                let item = try XCTUnwrap(notes["items"]?.objectValue)
                XCTAssertEqual(item["minLength"]?.numberValue, 1)
                XCTAssertEqual(item["maxLength"]?.numberValue, 160)
            }
        }
    }

    func testQualityResponseFixturesValidateAgainstTheirContracts() throws {
        let fixtures: [(String, ModelInputRole, ModelTaskProfile)] = [
            ("whole_image_with_quality_valid", .wholeImage, .taggingWithQuality),
            ("subject_isolated_with_quality_valid", .subjectIsolated, .taggingWithQuality),
            ("whole_image_quality_only_valid", .wholeImage, .qualityOnly),
        ]
        for (name, role, task) in fixtures {
            let value = try JSONDecoder().decode(JSONValue.self, from: fixtureData(named: name, extension: "json"))
            try JSONSchemaValidator.validate(value, against: ResponseSchemas.schema(for: role, task: task))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(JSONValue.self, from: fixtureData(named: "whole_image_quality_truncated", extension: "txt")))
    }

    func testAnalyzeRepairsSyntheticVisibleTextTermFragmentFixture() async throws {
        let imageURL = try writeModelInput()
        let malformed = try malformedVisibleTextTermFragmentFixture()
        let repairedJSON = wholeImageModelResponseJSON()
        let transport = RecordingOllamaTransport([
            .success(chatResponse(content: malformed)),
            .success(chatResponse(content: repairedJSON))
        ])
        let runner = OllamaVisionRunner(transport: transport)
        let prompt = try PromptRegistry.prompt(for: .wholeImage)
        let schema = try ResponseSchemas.schema(for: .wholeImage)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: prompt,
            schema: schema,
            options: ModelRunOptions(responseRepairAttempts: 1),
            runtime: runtimeContext()
        )

        XCTAssertTrue(record.jsonValid)
        XCTAssertNil(record.error)
        XCTAssertEqual(record.responseSchemaVersion, "urn:aisidecar:response:whole-image:1.5.0")
        let attempts = try XCTUnwrap(record.responseAttempts)
        XCTAssertEqual(attempts.map(\.kind), [.primary, .repair])
        XCTAssertEqual(attempts.first?.rawResponseText, malformed)
        XCTAssertEqual(attempts.first?.error?.code, .modelInvalidJSON)
        XCTAssertEqual(attempts.last?.jsonValid, true)
    }

    func testAnalyzeRepairsSchemaViolation() async throws {
        let imageURL = try writeModelInput()
        let repairedJSON = #"{"summary":"Recovered schema"}"#
        let transport = RecordingOllamaTransport([
            .success(chatResponse(content: #"{"summary":5}"#)),
            .success(chatResponse(content: repairedJSON))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(responseRepairAttempts: 1),
            runtime: runtimeContext()
        )

        XCTAssertTrue(record.jsonValid)
        XCTAssertNil(record.error)
        XCTAssertEqual(record.parsedResponseJSON?.objectValue?["summary"]?.stringValue, "Recovered schema")
        let attempts = try XCTUnwrap(record.responseAttempts)
        XCTAssertEqual(attempts.map(\.kind), [.primary, .repair])
        XCTAssertEqual(attempts.first?.error?.code, .modelSchemaViolation)
        XCTAssertEqual(attempts.first?.parsedResponseJSON?.objectValue?["summary"]?.numberValue, 5)
    }

    func testAnalyzeRecordsRepairFailureAsFinalModelError() async throws {
        let imageURL = try writeModelInput()
        let repairRaw = #"{"summary":5}"#
        let transport = RecordingOllamaTransport([
            .success(chatResponse(content: "not json")),
            .success(chatResponse(content: repairRaw))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let record = await runner.analyze(
            image: derivative(cachePath: imageURL.path),
            inputRole: .wholeImage,
            prompt: VersionedPrompt(version: "prompt/1.0", text: "Prompt"),
            schema: try summarySchema(),
            options: ModelRunOptions(responseRepairAttempts: 1),
            runtime: runtimeContext()
        )

        XCTAssertFalse(record.jsonValid)
        XCTAssertEqual(record.error?.code, .modelSchemaViolation)
        XCTAssertEqual(record.rawResponseText, repairRaw)
        XCTAssertEqual(record.parsedResponseJSON?.objectValue?["summary"]?.numberValue, 5)
        let attempts = try XCTUnwrap(record.responseAttempts)
        XCTAssertEqual(attempts.map(\.kind), [.primary, .repair])
        XCTAssertEqual(attempts.map { $0.error?.code }, [.modelInvalidJSON, .modelSchemaViolation])
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
            recipeVersion: "render-v2-test",
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
          "species": [
            {
              "term": "great blue heron",
              "confidence": "medium",
              "evidence": "large gray-blue wading bird"
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

    private func malformedVisibleTextTermFragmentFixture() throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "visible_text_term_fragment",
                withExtension: "txt"
            )
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func fixedDateProvider(_ date: Date) -> @Sendable () -> Date {
        { date }
    }

    // MARK: - CORE-8: standalone vision-tag listing (Phase 4 Settings)

    func testListInstalledVisionTagsFiltersNonVisionModels() async throws {
        let transport = RecordingOllamaTransport([
            .success(jsonResponse("""
            {"models":[
              {"name":"qwen2.5vl:7b","model":"qwen2.5vl:7b","digest":"a"},
              {"name":"llama3:8b","model":"llama3:8b","digest":"b"},
              {"name":"gemma4:26b-a4b-it-qat","model":"gemma4:26b-a4b-it-qat","digest":"c"}
            ]}
            """)),
            .success(jsonResponse(#"{"capabilities":["completion","vision"]}"#)),
            .success(jsonResponse(#"{"capabilities":["completion"]}"#)),
            .success(jsonResponse(#"{"capabilities":["completion","vision"]}"#))
        ])
        let runner = OllamaVisionRunner(transport: transport)

        let tags = try await runner.listInstalledVisionTags(
            endpoint: URL(string: "http://localhost:11434")!
        )

        XCTAssertEqual(tags, ["gemma4:26b-a4b-it-qat", "qwen2.5vl:7b"], "sorted, non-vision excluded")
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.map(\.path), ["/api/tags", "/api/show", "/api/show", "/api/show"])
    }
}

private actor RecordingOllamaTransport: OllamaHTTPTransport {
    private var responses: [Result<OllamaHTTPResponse, Error>]
    private var requests: [OllamaHTTPRequest] = []
    private let onSend: (@Sendable (Int) -> Void)?

    init(
        _ responses: [Result<OllamaHTTPResponse, Error>],
        onSend: (@Sendable (Int) -> Void)? = nil
    ) {
        self.responses = responses
        self.onSend = onSend
    }

    func capturedRequests() -> [OllamaHTTPRequest] {
        requests
    }

    func send(_ request: OllamaHTTPRequest, endpoint _: URL) async throws -> OllamaHTTPResponse {
        requests.append(request)
        onSend?(requests.count)
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

private actor CancellationAwareHangingTransport: OllamaHTTPTransport {
    private var started = false
    private var cancelled = false
    private var requests = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    var requestCount: Int { requests }
    var wasCancelled: Bool { cancelled }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func send(_: OllamaHTTPRequest, endpoint _: URL) async throws -> OllamaHTTPResponse {
        requests += 1
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return OllamaHTTPResponse(statusCode: 500, data: Data())
        } catch is CancellationError {
            cancelled = true
            throw CancellationError()
        }
    }
}

private func jsonResponse(_ json: String, statusCode: Int = 200) -> OllamaHTTPResponse {
    OllamaHTTPResponse(statusCode: statusCode, data: Data(json.utf8))
}

private func chatResponse(
    content: String,
    statusCode: Int = 200,
    totalDuration: Int64? = nil,
    loadDuration: Int64? = nil,
    promptEvalCount: Int? = nil,
    promptEvalDuration: Int64? = nil,
    evalCount: Int? = nil,
    evalDuration: Int64? = nil
) -> OllamaHTTPResponse {
    let escaped = content
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    var fields = [#""message":{"content":""# + escaped + #""}"#]
    if let totalDuration {
        fields.append(#""total_duration":"# + "\(totalDuration)")
    }
    if let loadDuration {
        fields.append(#""load_duration":"# + "\(loadDuration)")
    }
    if let promptEvalCount {
        fields.append(#""prompt_eval_count":"# + "\(promptEvalCount)")
    }
    if let promptEvalDuration {
        fields.append(#""prompt_eval_duration":"# + "\(promptEvalDuration)")
    }
    if let evalCount {
        fields.append(#""eval_count":"# + "\(evalCount)")
    }
    if let evalDuration {
        fields.append(#""eval_duration":"# + "\(evalDuration)")
    }
    return jsonResponse("{\(fields.joined(separator: ","))}", statusCode: statusCode)
}

private func decodeJSONObject(from data: Data) throws -> [String: JSONValue] {
    guard let object = try JSONDecoder().decode(JSONValue.self, from: data).objectValue else {
        throw XCTSkip("Expected JSON object")
    }
    return object
}

private func fixtureData(named name: String, extension fileExtension: String) throws -> Data {
    let url = try XCTUnwrap(
        Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "model-responses")
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
    )
    return try Data(contentsOf: url)
}
