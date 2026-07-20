import XCTest

@testable import AISidecarCore

/// Packaging plan D5: one non-placeholder product version feeds every surface.
final class AISidecarVersionTests: XCTestCase {
    func testCurrentVersionIsNonPlaceholderSemver() {
        XCTAssertNotEqual(AISidecarVersion.current, "0.0.0")
        let pattern = #"^\d+\.\d+\.\d+(-[0-9A-Za-z.\-]+)?$"#
        XCTAssertNotNil(
            AISidecarVersion.current.range(of: pattern, options: .regularExpression),
            "product version must be semver with optional pre-release suffix"
        )
    }
}
