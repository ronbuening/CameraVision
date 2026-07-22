import Darwin
import XCTest

@testable import AISidecarCore

final class NormalizationInputResolverTests: XCTestCase {
    func testAnalyzeInputHashingIsBoundedAndPreservesOrderingAndErrors() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("normalization-input-resolver-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        for name in ["E.NEF", "C.NEF", "A.NEF", "D.NEF", "B.NEF"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }

        let probe = ResolverIdentityConcurrencyProbe()
        let scanner = ImageScanner(
            identityCalculator: { url, policy, fileManager in
                try probe.compute(url: url, policy: policy, fileManager: fileManager)
            }
        )
        let resolver = NormalizationInputResolver(imageScanner: scanner)
        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.stageConcurrency = 2

        let batch = try await resolver.resolve(
            mode: .analyze(inputPath: root.path),
            configuration: configuration
        )

        XCTAssertEqual(probe.invocationCount, 5)
        XCTAssertEqual(probe.maximumActiveCount, 2)
        XCTAssertEqual(batch.workflow, .analyze)
        XCTAssertEqual(batch.sourceAssets.map(\.sourceRelativePath), ["A.NEF", "B.NEF", "D.NEF", "E.NEF"])
        XCTAssertEqual(batch.failures.map(\.relativePath), ["C.NEF"])
        let failure = try XCTUnwrap(batch.failures.first)
        XCTAssertEqual(failure.path, root.appendingPathComponent("C.NEF").standardizedFileURL.path)
        XCTAssertEqual(failure.error.code, .validationFailed)
        XCTAssertEqual(failure.error.stage, .scan)
        XCTAssertTrue(failure.error.recoverable)
        XCTAssertEqual(
            failure.error.message,
            "Unable to read source image metadata or identity for C.NEF: injected identity failure"
        )
    }

    func testAnalyzeInputWithNilConcurrencyUsesRunDomainHardwareDefault() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("normalization-input-resolver-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let expectedConcurrency = ResolvedRunConfiguration.defaultStageConcurrency()
        let fileCount = expectedConcurrency + 1
        for index in 0..<fileCount {
            try Data("image-\(index)".utf8).write(to: root.appendingPathComponent("IMG_\(index).NEF"))
        }

        let probe = ResolverIdentityConcurrencyProbe()
        let scanner = ImageScanner(
            identityCalculator: { url, policy, fileManager in
                try probe.compute(url: url, policy: policy, fileManager: fileManager)
            }
        )
        let resolver = NormalizationInputResolver(imageScanner: scanner)

        let batch = try await resolver.resolve(
            mode: .analyze(inputPath: root.path),
            configuration: .builtInDefaults
        )

        XCTAssertEqual(probe.invocationCount, fileCount)
        XCTAssertEqual(probe.maximumActiveCount, expectedConcurrency)
        XCTAssertEqual(batch.sourceAssets.count, fileCount)
        XCTAssertTrue(batch.failures.isEmpty)
    }
}

private final class ResolverIdentityConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private var storedInvocationCount = 0
    private var storedMaximumActiveCount = 0

    var invocationCount: Int {
        lock.withLock { storedInvocationCount }
    }

    var maximumActiveCount: Int {
        lock.withLock { storedMaximumActiveCount }
    }

    func compute(
        url: URL,
        policy: SourceIdentityPolicy,
        fileManager _: FileManager
    ) throws -> SourceIdentity {
        lock.withLock {
            activeCount += 1
            storedInvocationCount += 1
            storedMaximumActiveCount = max(storedMaximumActiveCount, activeCount)
        }
        defer {
            lock.withLock {
                activeCount -= 1
            }
        }

        usleep(20_000)
        if url.lastPathComponent == "C.NEF" {
            throw ResolverIdentityProbeError.expectedFailure
        }
        return SourceIdentity(policy: policy, sha256: String(repeating: "a", count: 64))
    }
}

private enum ResolverIdentityProbeError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "injected identity failure"
    }
}
