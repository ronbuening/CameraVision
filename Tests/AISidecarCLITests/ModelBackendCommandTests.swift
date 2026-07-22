import XCTest

@testable import AISidecarCLI

final class ModelBackendCommandTests: XCTestCase {
    func testSharedModelBackendFlagForwardsToAnalyzeAndAssessQuality() throws {
        let analyze = try AnalyzeCommand.parse(["Photos", "--model-backend", "apple"])
        XCTAssertEqual(analyze.shared.overrides.modelBackend, .apple)

        let quality = try AssessQualityCommand.parse(["Photos", "--model-backend", "auto"])
        XCTAssertEqual(quality.shared.overrides.modelBackend, .auto)
    }

    func testAnalyzeModeCommandsForwardModelBackendToRunOverrides() throws {
        let write = try WriteXMPCommand.parse(["Photos", "--model-backend", "apple"])
        XCTAssertEqual(write.modelBackend, .apple)

        let normalize = try NormalizeCommand.parse(["Photos", "--model-backend", "auto"])
        XCTAssertEqual(normalize.modelBackend, .auto)
    }

    func testBenchmarkAcceptsOnlyOllamaBackend() throws {
        let ollama = try BenchmarkCommand.parse(["--model-backend", "ollama", "--self-test"])
        XCTAssertEqual(ollama.modelBackend, .ollama)

        for backend in ["apple", "auto"] {
            XCTAssertThrowsError(try BenchmarkCommand.parse(["--model-backend", backend, "--self-test"])) { error in
                XCTAssertTrue(
                    String(describing: error).contains("benchmark currently supports only --model-backend ollama")
                )
            }
        }
    }

    func testModelBackendFlagAppearsOnlyOnCommandsWithModelSelection() {
        for help in [
            AnalyzeCommand.helpMessage(),
            AssessQualityCommand.helpMessage(),
            WriteXMPCommand.helpMessage(),
            NormalizeCommand.helpMessage(),
            BenchmarkCommand.helpMessage(),
        ] {
            XCTAssertTrue(help.contains("--model-backend"))
        }
    }
}
