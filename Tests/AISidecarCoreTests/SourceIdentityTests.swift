import XCTest
@testable import AISidecarCore

final class SourceIdentityTests: XCTestCase {
    func testFullSha256PolicyHashesEntireFile() throws {
        let file = try writeFile(name: "sample.nef", data: Data("hello".utf8))

        let identity = try SourceIdentityCalculator.compute(for: file, policy: .sha256)

        XCTAssertEqual(identity.policy, .sha256)
        XCTAssertEqual(identity.sha256, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func testFastPolicyIsDeterministicForSmallFiles() throws {
        let file = try writeFile(name: "small.nef", data: Data("small file".utf8))
        try setModifiedAt(Date(timeIntervalSince1970: 1_700_000_000), for: file)

        let first = try SourceIdentityCalculator.compute(for: file, policy: .fast)
        let second = try SourceIdentityCalculator.compute(for: file, policy: .fast)

        XCTAssertEqual(first.policy, .fast)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.sha256.count, 64)
    }

    func testFastPolicyUsesFirstAndLastFourMiBForLargeFiles() throws {
        let size = (8 * 1024 * 1024) + 123
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_100)
        var data = Data(count: size)
        for index in data.indices {
            data[index] = UInt8(index % 251)
        }
        let file = try writeFile(name: "large.nef", data: data)
        try setModifiedAt(modifiedAt, for: file)

        let baseline = try SourceIdentityCalculator.compute(for: file, policy: .fast)

        // This byte is outside the first and last 4 MiB windows, so the fast
        // identity should remain stable even though the full file changed.
        data[(4 * 1024 * 1024) + 10] ^= 0xff
        try data.write(to: file)
        try setModifiedAt(modifiedAt, for: file)
        let middleChanged = try SourceIdentityCalculator.compute(for: file, policy: .fast)

        data[size - 1] ^= 0xff
        try data.write(to: file)
        try setModifiedAt(modifiedAt, for: file)
        let lastChunkChanged = try SourceIdentityCalculator.compute(for: file, policy: .fast)

        XCTAssertEqual(middleChanged, baseline)
        XCTAssertNotEqual(lastChunkChanged, baseline)
    }

    private func writeFile(name: String, data: Data) throws -> URL {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }

    private func setModifiedAt(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aisidecar-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
