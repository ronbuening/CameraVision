import Foundation
import ArgumentParser
import AISidecarCore

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct BenchmarkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Run Phase 1 Milestone 9 benchmark specs."
    )

    @Option(help: "Sample manifest path.")
    var samples = "benchmarks/samples/manifest.json"

    @Option(help: "Directory where benchmark result folders are written.")
    var outputDir = "benchmarks"

    @Option(help: "Ollama model tag to benchmark.")
    var model = "gemma4:26b-a4b-it-qat"

    @Option(help: "Number of matrix repetitions.")
    var iterations = 1

    @Option(help: "Scratch copies for source-identity specs.")
    var maxHashCopies = 2_000

    @Option(name: .customLong("spec"), help: "Run one named spec; repeat for multiple specs.")
    var specs: [String] = []

    @Option(help: "Executable to benchmark. Defaults to .build/release/aisidecar after build.")
    var binary: String?

    @Flag(help: "Use the existing benchmark binary without running swift build -c release first.")
    var skipBuild = false

    @Flag(help: "Run the offline aggregation self-test without Ollama or images.")
    var selfTest = false

    mutating func validate() throws {
        guard iterations > 0 else {
            throw ValidationError("--iterations must be a positive integer")
        }
        guard maxHashCopies > 0 else {
            throw ValidationError("--max-hash-copies must be a positive integer")
        }
    }

    mutating func run() throws {
        let result = try Milestone9BenchmarkRunner().run(options: BenchmarkOptions(
            samplesPath: samples,
            outputDir: outputDir,
            model: model,
            iterations: iterations,
            maxHashCopies: maxHashCopies,
            specNames: specs,
            skipBuild: skipBuild,
            selfTest: selfTest,
            binaryPath: binary
        ))
        if result.selfTest {
            FileHandle.standardOutput.write(Data("Self-test passed: \(result.outputRootPath)\n".utf8))
        } else {
            FileHandle.standardOutput.write(Data("Wrote \(result.jsonPath)\n".utf8))
            FileHandle.standardOutput.write(Data("Wrote \(result.markdownPath)\n".utf8))
        }
    }
}
