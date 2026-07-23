import XCTest

@testable import AISidecarCLI

final class NormalizeCommandTests: XCTestCase {
    func testStageConcurrencyForwardsIntoNormalizationOverrides() throws {
        let command = try NormalizeCommand.parse([
            "Photos",
            "--stage-concurrency", "3",
        ])

        XCTAssertEqual(command.stageConcurrency, 3)
        XCTAssertEqual(command.normalizationOverrides.stageConcurrency, 3)
    }
}
