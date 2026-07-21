import AISidecarCore
import Foundation
import XCTest

@testable import AISidecarCLI

final class CommandOutputHelpersTests: XCTestCase {
    func testPairedFlagPreservesPositiveNegativeAndUnspecifiedStates() {
        XCTAssertEqual(CommandOutputHelpers.pairedFlag(positive: true, negative: false), true)
        XCTAssertEqual(CommandOutputHelpers.pairedFlag(positive: false, negative: true), false)
        XCTAssertNil(CommandOutputHelpers.pairedFlag(positive: false, negative: false))
        XCTAssertEqual(CommandOutputHelpers.pairedFlag(positive: true, negative: true), true)
    }

    func testChangePlanOutputPreservesDocumentBytesAndTrailingNewline() throws {
        let plan = XMPChangePlanDocument(dryRun: true, targetPlans: [], inputFailures: [])
        let output = try captureOutput { handle in
            try CommandOutputHelpers.writeChangePlan(plan, to: handle)
        }
        var expected = try JSONCoding.documentEncoder(iso8601Dates: false).encode(plan)
        expected.append(contentsOf: Data("\n".utf8))

        XCTAssertEqual(output, expected)
    }

    func testEssentialSummaryOutputPreservesEveryCommandPrefix() throws {
        for prefix in ["XMP export", "normalize", "apply-session"] {
            let output = try captureOutput { handle in
                CommandOutputHelpers.writeEssentialSummary(
                    prefix: prefix,
                    writtenCount: 3,
                    failedCount: 1,
                    to: handle
                )
            }

            XCTAssertEqual(String(decoding: output, as: UTF8.self), "\(prefix) complete: 3 written, 1 failed.\n")
        }
    }

    private func captureOutput(_ body: (FileHandle) throws -> Void) throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("stdout.txt")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        try body(handle)
        try handle.close()
        return try Data(contentsOf: outputURL)
    }
}
