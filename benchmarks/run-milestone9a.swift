#!/usr/bin/env swift

import Foundation

struct SampleManifest: Decodable {
    var schemaVersion: String
    var samples: [BenchmarkSample]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case samples
    }
}

struct BenchmarkSample: Codable {
    var path: String
    var format: String
    var description: String?
    var rights: String?
}

struct BenchmarkDocument: Codable {
    var schemaVersion: String
    var createdAt: String
    var hardware: [String: String]
    var runtime: [String: String]
    var samples: [BenchmarkSample]
    var runs: [BenchmarkRun]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case hardware
        case runtime
        case samples
        case runs
    }
}

struct BenchmarkRun: Codable {
    var name: String
    var axis: String
    var mode: String?
    var profile: String?
    var modelKeepAlive: String?
    var stageConcurrency: Int?
    var sourceIdentityPolicy: String?
    var command: [String]
    var exitCode: Int32
    var elapsedMs: Int
    var peakRSSBytes: Int64?
    var xmpFileCount: Int
    var metrics: AggregatedMetrics

    enum CodingKeys: String, CodingKey {
        case name
        case axis
        case mode
        case profile
        case modelKeepAlive = "model_keep_alive"
        case stageConcurrency = "stage_concurrency"
        case sourceIdentityPolicy = "source_identity_policy"
        case command
        case exitCode = "exit_code"
        case elapsedMs = "elapsed_ms"
        case peakRSSBytes = "peak_rss_bytes"
        case xmpFileCount = "xmp_file_count"
        case metrics
    }
}

struct AggregatedMetrics: Codable {
    var sidecarCount: Int = 0
    var failedSidecarCount: Int = 0
    var modelRunCount: Int = 0
    var validModelRunCount: Int = 0
    var repairAttemptCount: Int = 0
    var schemaViolationCount: Int = 0
    var invalidJSONCount: Int = 0
    var medianPipelineMs: Int?
    var medianRenderMs: Int?
    var medianSubjectIsolationMs: Int?
    var medianModelMs: Int?
    var medianWriteMs: Int?
    var medianModelRunMs: Int?
    var totalOllamaLoadDurationNs: Int64 = 0

    enum CodingKeys: String, CodingKey {
        case sidecarCount = "sidecar_count"
        case failedSidecarCount = "failed_sidecar_count"
        case modelRunCount = "model_run_count"
        case validModelRunCount = "valid_model_run_count"
        case repairAttemptCount = "repair_attempt_count"
        case schemaViolationCount = "schema_violation_count"
        case invalidJSONCount = "invalid_json_count"
        case medianPipelineMs = "median_pipeline_ms"
        case medianRenderMs = "median_render_ms"
        case medianSubjectIsolationMs = "median_subject_isolation_ms"
        case medianModelMs = "median_model_ms"
        case medianWriteMs = "median_write_ms"
        case medianModelRunMs = "median_model_run_ms"
        case totalOllamaLoadDurationNs = "total_ollama_load_duration_ns"
    }
}

struct RunSpec {
    var name: String
    var axis: String
    var mode: String?
    var profile: String?
    var modelKeepAlive: String?
    var stageConcurrency: Int?
    var sourceIdentityPolicy: String?
    var dryScan: Bool
}

struct Options {
    var samplesPath = "benchmarks/samples/manifest.json"
    var outputDir = "benchmarks"
    var model = "gemma4:26b-a4b-it-qat"
    var iterations = 1
    var maxHashCopies = 2_000
    var specNames: [String] = []
    var skipBuild = false
    var selfTest = false
}

let fileManager = FileManager.default
let isoFormatter = ISO8601DateFormatter()

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("benchmark failed: \(error)\n".utf8))
    exit(1)
}

func main() throws {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    if options.selfTest {
        try runSelfTest(outputDir: options.outputDir)
        return
    }

    let repoRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    let manifestURL = URL(fileURLWithPath: options.samplesPath, relativeTo: repoRoot).standardizedFileURL
    let manifest = try loadManifest(at: manifestURL)
    let sampleURLs = try validateSamples(manifest.samples, manifestURL: manifestURL)
    guard !sampleURLs.isEmpty else {
        throw BenchmarkError("No benchmark samples listed in \(manifestURL.path). Add rights-cleared images first.")
    }

    if !options.skipBuild {
        let build = try runProcess(["swift", "build", "-c", "release"], workingDirectory: repoRoot, captureOutput: false)
        guard build.exitCode == 0 else {
            throw BenchmarkError("swift build -c release failed with exit code \(build.exitCode)")
        }
    }

    let binary = repoRoot.appendingPathComponent(".build/release/aisidecar").path
    let stamp = runStamp()
    let outputRoot = URL(fileURLWithPath: options.outputDir, relativeTo: repoRoot)
        .standardizedFileURL
        .appendingPathComponent("milestone9a-\(stamp)")
    try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)

    let specs = try selectedSpecs(
        from: benchmarkSpecs(defaultProfile: "gemma4-26b-default"),
        requestedNames: options.specNames
    )
    var runs: [BenchmarkRun] = []
    for iteration in 1...max(1, options.iterations) {
        for spec in specs {
            let input = spec.axis == "source_identity"
                ? try expandedHashInput(samples: sampleURLs, count: options.maxHashCopies, outputRoot: outputRoot)
                : try benchmarkInput(samples: sampleURLs, outputRoot: outputRoot)
            let run = try execute(
                spec: spec,
                iteration: iteration,
                binary: binary,
                input: input,
                outputRoot: outputRoot,
                model: options.model
            )
            runs.append(run)
        }
    }

    let document = BenchmarkDocument(
        schemaVersion: "aisidecar-benchmark-results/1.0",
        createdAt: isoFormatter.string(from: Date()),
        hardware: hardwareMetadata(),
        runtime: runtimeMetadata(model: options.model),
        samples: manifest.samples,
        runs: runs
    )
    let jsonURL = outputRoot.appendingPathComponent("benchmark-results-\(stamp).json")
    let markdownURL = outputRoot.appendingPathComponent("benchmark-results-\(stamp).md")
    try writeJSON(document, to: jsonURL)
    try writeMarkdown(document, to: markdownURL)
    try cleanupScratchInputs(outputRoot: outputRoot)
    print("Wrote \(jsonURL.path)")
    print("Wrote \(markdownURL.path)")
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--samples":
            index += 1
            options.samplesPath = try value(arguments, at: index, for: argument)
        case "--output-dir":
            index += 1
            options.outputDir = try value(arguments, at: index, for: argument)
        case "--model":
            index += 1
            options.model = try value(arguments, at: index, for: argument)
        case "--iterations":
            index += 1
            options.iterations = try positiveInt(value(arguments, at: index, for: argument), name: argument)
        case "--max-hash-copies":
            index += 1
            options.maxHashCopies = try positiveInt(value(arguments, at: index, for: argument), name: argument)
        case "--spec":
            index += 1
            options.specNames.append(try value(arguments, at: index, for: argument))
        case "--skip-build":
            options.skipBuild = true
        case "--self-test":
            options.selfTest = true
        case "--help", "-h":
            print(helpText())
            exit(0)
        default:
            throw BenchmarkError("Unknown argument: \(argument)")
        }
        index += 1
    }
    return options
}

func selectedSpecs(from specs: [RunSpec], requestedNames: [String]) throws -> [RunSpec] {
    guard !requestedNames.isEmpty else {
        return specs
    }
    let requested = Set(requestedNames)
    let selected = specs.filter { requested.contains($0.name) }
    let found = Set(selected.map(\.name))
    let missing = requested.subtracting(found).sorted()
    guard missing.isEmpty else {
        throw BenchmarkError("Unknown benchmark spec(s): \(missing.joined(separator: ", "))")
    }
    return selected
}

func benchmarkSpecs(defaultProfile: String) -> [RunSpec] {
    var specs: [RunSpec] = []
    for profile in ["gemma4-26b-benchmark-1024", "gemma4-26b-benchmark-1536", defaultProfile] {
        for mode in ["whole", "subject"] {
            specs.append(RunSpec(
                name: "profile-\(profile)-\(mode)",
                axis: "profile",
                mode: mode,
                profile: profile,
                modelKeepAlive: "30m",
                stageConcurrency: nil,
                sourceIdentityPolicy: "sha256",
                dryScan: false
            ))
        }
    }
    for keepAlive in ["0", "5m", "30m"] {
        specs.append(RunSpec(
            name: "keep-alive-\(keepAlive)",
            axis: "keep_alive",
            mode: "both",
            profile: defaultProfile,
            modelKeepAlive: keepAlive,
            stageConcurrency: nil,
            sourceIdentityPolicy: "sha256",
            dryScan: false
        ))
    }
    for concurrency in [2, 4, 6, 8] {
        specs.append(RunSpec(
            name: "stage-concurrency-\(concurrency)",
            axis: "stage_concurrency",
            mode: "both",
            profile: defaultProfile,
            modelKeepAlive: "30m",
            stageConcurrency: concurrency,
            sourceIdentityPolicy: "sha256",
            dryScan: false
        ))
    }
    specs.append(RunSpec(
        name: "stage-concurrency-default",
        axis: "stage_concurrency",
        mode: "both",
        profile: defaultProfile,
        modelKeepAlive: "30m",
        stageConcurrency: nil,
        sourceIdentityPolicy: "sha256",
        dryScan: false
    ))
    for policy in ["sha256", "fast"] {
        specs.append(RunSpec(
            name: "source-identity-\(policy)",
            axis: "source_identity",
            mode: nil,
            profile: defaultProfile,
            modelKeepAlive: "30m",
            stageConcurrency: nil,
            sourceIdentityPolicy: policy,
            dryScan: true
        ))
    }
    return specs
}

func execute(
    spec: RunSpec,
    iteration: Int,
    binary: String,
    input: URL,
    outputRoot: URL,
    model: String
) throws -> BenchmarkRun {
    let runDir = outputRoot.appendingPathComponent("iter-\(iteration)-\(safeName(spec.name))")
    let sidecarDir = runDir.appendingPathComponent("sidecars")
    let cacheDir = runDir.appendingPathComponent("cache")
    try fileManager.createDirectory(at: runDir, withIntermediateDirectories: true)
    var cacheCleaned = false
    defer {
        if !cacheCleaned {
            try? removeIfExists(cacheDir)
        }
    }
    let configURL = runDir.appendingPathComponent("config.json")
    try writeConfig(spec: spec, model: model, cacheDir: cacheDir, to: configURL)

    var command = [binary, "analyze", input.path, "--recursive", "--existing", "overwrite", "--config", configURL.path]
    if let mode = spec.mode {
        command.append(contentsOf: ["--mode", mode])
    }
    if !spec.dryScan {
        command.append(contentsOf: ["--output-dir", sidecarDir.path, "--log-format", "json"])
    } else {
        command.append("--dry-scan")
    }

    let started = Date()
    let result = try runProcess(["/usr/bin/time", "-l"] + command, workingDirectory: nil, captureOutput: true)
    let elapsed = Int(Date().timeIntervalSince(started) * 1_000)
    try result.stdout.write(to: runDir.appendingPathComponent("stdout.txt"))
    try result.stderr.write(to: runDir.appendingPathComponent("stderr.txt"))

    let metrics = spec.dryScan ? AggregatedMetrics() : try aggregateSidecars(in: sidecarDir)
    let xmpCount = try countFiles(withExtension: "xmp", in: runDir)
    if xmpCount > 0 {
        throw BenchmarkError("XMP files were created in \(runDir.path)")
    }
    try removeIfExists(cacheDir)
    cacheCleaned = true

    return BenchmarkRun(
        name: "iter-\(iteration)-\(spec.name)",
        axis: spec.axis,
        mode: spec.mode,
        profile: spec.profile,
        modelKeepAlive: spec.modelKeepAlive,
        stageConcurrency: spec.stageConcurrency,
        sourceIdentityPolicy: spec.sourceIdentityPolicy,
        command: command,
        exitCode: result.exitCode,
        elapsedMs: elapsed,
        peakRSSBytes: peakRSSBytes(from: String(decoding: result.stderr, as: UTF8.self)),
        xmpFileCount: xmpCount,
        metrics: metrics
    )
}

func writeConfig(spec: RunSpec, model: String, cacheDir: URL, to url: URL) throws {
    var object: [String: Any] = [
        "model": model,
        "derivative_cache_dir": cacheDir.path,
        "clear_derivative_cache_on_start": true,
        "clear_derivative_cache_after_success": true
    ]
    if let profile = spec.profile { object["profile"] = profile }
    if let keepAlive = spec.modelKeepAlive { object["model_keep_alive"] = keepAlive }
    if let stageConcurrency = spec.stageConcurrency { object["stage_concurrency"] = stageConcurrency }
    if let sourceIdentityPolicy = spec.sourceIdentityPolicy { object["source_identity_policy"] = sourceIdentityPolicy }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

func aggregateSidecars(in directory: URL) throws -> AggregatedMetrics {
    var metrics = AggregatedMetrics()
    var pipelineMs: [Int] = []
    var renderMs: [Int] = []
    var subjectMs: [Int] = []
    var modelMs: [Int] = []
    var writeMs: [Int] = []
    var modelRunMs: [Int] = []

    for url in try files(in: directory) where url.lastPathComponent.hasSuffix(".ai.json") {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        metrics.sidecarCount += 1
        let errors = object["errors"] as? [[String: Any]] ?? []
        if !errors.isEmpty { metrics.failedSidecarCount += 1 }
        countErrorCodes(errors, metrics: &metrics)
        if let timing = object["timing"] as? [String: Any] {
            appendInt(timing["pipeline_elapsed_ms"], to: &pipelineMs)
            appendInt(timing["render_ms"], to: &renderMs)
            appendInt(timing["subject_isolation_ms"], to: &subjectMs)
            appendInt(timing["model_ms"], to: &modelMs)
            appendInt(timing["write_ms"], to: &writeMs)
        }
        for run in object["model_runs"] as? [[String: Any]] ?? [] {
            metrics.modelRunCount += 1
            if run["json_valid"] as? Bool == true {
                metrics.validModelRunCount += 1
            }
            appendInt(run["duration_ms"], to: &modelRunMs)
            if let runtimeMetrics = run["runtime_metrics"] as? [String: Any] {
                metrics.totalOllamaLoadDurationNs += int64Value(runtimeMetrics["load_duration_ns"]) ?? 0
            }
            if let attempts = run["response_attempts"] as? [[String: Any]] {
                metrics.repairAttemptCount += max(0, attempts.count - 1)
                for attempt in attempts {
                    if let error = attempt["error"] as? [String: Any] {
                        countErrorCodes([error], metrics: &metrics)
                    }
                }
            }
            if let error = run["error"] as? [String: Any] {
                countErrorCodes([error], metrics: &metrics)
            }
        }
    }

    metrics.medianPipelineMs = median(pipelineMs)
    metrics.medianRenderMs = median(renderMs)
    metrics.medianSubjectIsolationMs = median(subjectMs)
    metrics.medianModelMs = median(modelMs)
    metrics.medianWriteMs = median(writeMs)
    metrics.medianModelRunMs = median(modelRunMs)
    return metrics
}

func countErrorCodes(_ errors: [[String: Any]], metrics: inout AggregatedMetrics) {
    for error in errors {
        switch error["code"] as? String {
        case "E_MODEL_SCHEMA_VIOLATION":
            metrics.schemaViolationCount += 1
        case "E_MODEL_INVALID_JSON":
            metrics.invalidJSONCount += 1
        default:
            break
        }
    }
}

func runSelfTest(outputDir: String) throws {
    let root = URL(fileURLWithPath: outputDir).standardizedFileURL
        .appendingPathComponent("milestone9a-self-test-\(UUID().uuidString)")
    let sidecars = root.appendingPathComponent("sidecars")
    try fileManager.createDirectory(at: sidecars, withIntermediateDirectories: true)
    let sidecar = """
    {
      "schema_version": "ai-sidecar-json/1.1",
      "errors": [],
      "timing": {
        "pipeline_elapsed_ms": 10,
        "render_ms": 2,
        "subject_isolation_ms": 3,
        "model_ms": 4,
        "write_ms": 1
      },
      "model_runs": [
        {
          "json_valid": true,
          "duration_ms": 4,
          "runtime_metrics": { "load_duration_ns": 1000 },
          "response_attempts": []
        }
      ]
    }
    """
    try Data(sidecar.utf8).write(to: sidecars.appendingPathComponent("self.JPG.ai.json"))
    let metrics = try aggregateSidecars(in: sidecars)
    guard metrics.sidecarCount == 1,
          metrics.validModelRunCount == 1,
          metrics.medianPipelineMs == 10,
          metrics.totalOllamaLoadDurationNs == 1000
    else {
        throw BenchmarkError("Self-test aggregation did not match expected metrics: \(metrics)")
    }
    let document = BenchmarkDocument(
        schemaVersion: "aisidecar-benchmark-results/1.0",
        createdAt: isoFormatter.string(from: Date()),
        hardware: ["self_test": "true"],
        runtime: ["self_test": "true"],
        samples: [],
        runs: [
            BenchmarkRun(
                name: "self-test",
                axis: "self_test",
                mode: nil,
                profile: nil,
                modelKeepAlive: nil,
                stageConcurrency: nil,
                sourceIdentityPolicy: nil,
                command: [],
                exitCode: 0,
                elapsedMs: 0,
                peakRSSBytes: nil,
                xmpFileCount: 0,
                metrics: metrics
            )
        ]
    )
    try writeJSON(document, to: root.appendingPathComponent("benchmark-results-self-test.json"))
    try writeMarkdown(document, to: root.appendingPathComponent("benchmark-results-self-test.md"))
    let scratchInput = root.appendingPathComponent("input-samples")
    let hashInput = root.appendingPathComponent("hash-input-3")
    let cache = root.appendingPathComponent("iter-1-test/cache")
    try fileManager.createDirectory(at: scratchInput, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: hashInput, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
    try cleanupScratchInputs(outputRoot: root)
    try removeIfExists(cache)
    guard !fileManager.fileExists(atPath: scratchInput.path),
          !fileManager.fileExists(atPath: hashInput.path),
          !fileManager.fileExists(atPath: cache.path)
    else {
        throw BenchmarkError("Self-test cleanup left scratch/cache directories behind")
    }
    print("Self-test passed: \(root.path)")
}

func loadManifest(at url: URL) throws -> SampleManifest {
    let decoder = JSONDecoder()
    let manifest = try decoder.decode(SampleManifest.self, from: Data(contentsOf: url))
    guard manifest.schemaVersion == "aisidecar-benchmark-samples/1.0" else {
        throw BenchmarkError("Unsupported sample manifest schema: \(manifest.schemaVersion)")
    }
    return manifest
}

func validateSamples(_ samples: [BenchmarkSample], manifestURL: URL) throws -> [URL] {
    let root = manifestURL.deletingLastPathComponent()
    return try samples.map { sample in
        let url = URL(fileURLWithPath: sample.path, relativeTo: root).standardizedFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            throw BenchmarkError("Sample does not exist: \(url.path)")
        }
        return url
    }
}

func benchmarkInput(samples: [URL], outputRoot: URL) throws -> URL {
    let root = outputRoot.appendingPathComponent("input-samples")
    if fileManager.fileExists(atPath: root.path) {
        return root
    }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    for source in samples {
        let destination = root.appendingPathComponent(source.lastPathComponent)
        try fileManager.copyItem(at: source, to: destination)
    }
    return root
}

func expandedHashInput(samples: [URL], count: Int, outputRoot: URL) throws -> URL {
    let root = outputRoot.appendingPathComponent("hash-input-\(count)")
    if fileManager.fileExists(atPath: root.path) {
        return root
    }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    for index in 0..<count {
        let source = samples[index % samples.count]
        let extensionText = source.pathExtension.isEmpty ? "img" : source.pathExtension
        let destination = root.appendingPathComponent(String(format: "sample-%04d.%@", index, extensionText))
        try fileManager.copyItem(at: source, to: destination)
    }
    return root
}

func cleanupScratchInputs(outputRoot: URL) throws {
    try removeIfExists(outputRoot.appendingPathComponent("input-samples"))
    guard fileManager.fileExists(atPath: outputRoot.path) else {
        return
    }
    let children = try fileManager.contentsOfDirectory(
        at: outputRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    for child in children where child.lastPathComponent.hasPrefix("hash-input-") {
        let values = try child.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            try removeIfExists(child)
        }
    }
}

func removeIfExists(_ url: URL) throws {
    guard fileManager.fileExists(atPath: url.path) else {
        return
    }
    try fileManager.removeItem(at: url)
}

func hardwareMetadata() -> [String: String] {
    [
        "cpu": commandOutput(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"]) ?? "unknown",
        "memory_bytes": commandOutput(["/usr/sbin/sysctl", "-n", "hw.memsize"]) ?? "unknown",
        "performance_cores": commandOutput(["/usr/sbin/sysctl", "-n", "hw.perflevel0.physicalcpu"]) ?? "unknown"
    ]
}

func runtimeMetadata(model: String) -> [String: String] {
    [
        "ollama_version": commandOutput(["ollama", "--version"]) ?? "unknown",
        "model": model
    ]
}

func commandOutput(_ command: [String]) -> String? {
    guard let result = try? runProcess(command, workingDirectory: nil, captureOutput: true),
          result.exitCode == 0
    else {
        return nil
    }
    return String(decoding: result.stdout, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func runProcess(_ command: [String], workingDirectory: URL?, captureOutput: Bool) throws -> ProcessResult {
    guard let executable = command.first else { throw BenchmarkError("Empty command") }
    let process = Process()
    if executable.contains("/") {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
    }
    process.currentDirectoryURL = workingDirectory
    let stdout = Pipe()
    let stderr = Pipe()
    if captureOutput {
        process.standardOutput = stdout
        process.standardError = stderr
    }
    try process.run()
    process.waitUntilExit()
    return ProcessResult(
        exitCode: process.terminationStatus,
        stdout: captureOutput ? stdout.fileHandleForReading.readDataToEndOfFile() : Data(),
        stderr: captureOutput ? stderr.fileHandleForReading.readDataToEndOfFile() : Data()
    )
}

struct ProcessResult {
    var exitCode: Int32
    var stdout: Data
    var stderr: Data
}

func writeJSON(_ document: BenchmarkDocument, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(document).write(to: url)
}

func writeMarkdown(_ document: BenchmarkDocument, to url: URL) throws {
    var lines: [String] = []
    lines.append("# Milestone 9a Benchmark Results")
    lines.append("")
    lines.append("- Created: \(document.createdAt)")
    lines.append("- CPU: \(document.hardware["cpu"] ?? "unknown")")
    lines.append("- Memory bytes: \(document.hardware["memory_bytes"] ?? "unknown")")
    lines.append("- Ollama: \(document.runtime["ollama_version"] ?? "unknown")")
    lines.append("- Model: \(document.runtime["model"] ?? "unknown")")
    lines.append("")
    lines.append("| Run | Axis | Exit | Sidecars | Valid model runs | Median pipeline ms | Median model run ms | Peak RSS bytes | XMP files |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for run in document.runs {
        lines.append("| \(run.name) | \(run.axis) | \(run.exitCode) | \(run.metrics.sidecarCount) | \(run.metrics.validModelRunCount) | \(run.metrics.medianPipelineMs.map(String.init) ?? "") | \(run.metrics.medianModelRunMs.map(String.init) ?? "") | \(run.peakRSSBytes.map(String.init) ?? "") | \(run.xmpFileCount) |")
    }
    lines.append("")
    lines.append("Quality scoring, foreground-mask failure classification, and instance-selection accuracy are deferred to Milestone 9b.")
    try lines.joined(separator: "\n").data(using: .utf8)!.write(to: url)
}

func files(in directory: URL) throws -> [URL] {
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }
    return try enumerator.compactMap { item in
        guard let url = item as? URL else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        return values.isRegularFile == true ? url : nil
    }
}

func countFiles(withExtension fileExtension: String, in directory: URL) throws -> Int {
    try files(in: directory).filter { $0.pathExtension.lowercased() == fileExtension.lowercased() }.count
}

func appendInt(_ value: Any?, to values: inout [Int]) {
    if let int = intValue(value) {
        values.append(int)
    }
}

func intValue(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    if let int = value as? Int { return int }
    if let string = value as? String { return Int(string) }
    return nil
}

func int64Value(_ value: Any?) -> Int64? {
    if let number = value as? NSNumber { return number.int64Value }
    if let int64 = value as? Int64 { return int64 }
    if let string = value as? String { return Int64(string) }
    return nil
}

func median(_ values: [Int]) -> Int? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

func peakRSSBytes(from text: String) -> Int64? {
    for line in text.split(separator: "\n") where line.contains("maximum resident set size") {
        return Int64(line.split(separator: " ").first ?? "")
    }
    return nil
}

func runStamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: Date())
}

func safeName(_ value: String) -> String {
    value.map { character in
        character.isLetter || character.isNumber || character == "-" ? character : "-"
    }.reduce(into: "") { $0.append($1) }
}

func value(_ arguments: [String], at index: Int, for option: String) throws -> String {
    guard arguments.indices.contains(index) else {
        throw BenchmarkError("Missing value for \(option)")
    }
    return arguments[index]
}

func positiveInt(_ value: String, name: String) throws -> Int {
    guard let int = Int(value), int > 0 else {
        throw BenchmarkError("\(name) must be a positive integer")
    }
    return int
}

func helpText() -> String {
    """
    Usage:
      swift benchmarks/run-milestone9a.swift [options]

    Options:
      --samples PATH          Sample manifest path. Default: benchmarks/samples/manifest.json
      --output-dir PATH       Output directory. Default: benchmarks
      --model TAG             Ollama model tag. Default: gemma4:26b-a4b-it-qat
      --iterations N          Matrix repetitions. Default: 1
      --max-hash-copies N     Scratch copies for source-identity sweep. Default: 2000
      --spec NAME             Run one named spec; repeat for multiple specs
      --skip-build            Use existing .build/release/aisidecar
      --self-test             Run offline aggregation self-test without Ollama or images

    Useful small-run specs:
      profile-gemma4-26b-benchmark-1024-whole
      keep-alive-30m
      source-identity-sha256
    """
}

struct BenchmarkError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
