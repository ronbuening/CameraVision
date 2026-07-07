import XCTest
@testable import AISidecarCore

/// WI-2 groundwork: the resource locator must find every bundled resource
/// class in the dev/test shape (the relocated shapes are proven
/// out-of-process by `Scripts/wi2-relocation-check.sh`).
final class AISidecarResourceBundleTests: XCTestCase {
    func testLocatorResolvesPromptsSchemasAndVocabulary() throws {
        XCTAssertNoThrow(try PromptRegistry.prompt(for: .wholeImage))
        XCTAssertNoThrow(try ResponseSchemas.schema(for: .wholeImage))
        XCTAssertNoThrow(try DefaultVocabulary.load())
    }
}
