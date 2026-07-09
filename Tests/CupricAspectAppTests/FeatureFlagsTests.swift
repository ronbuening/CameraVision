import XCTest
@testable import CupricAspectApp

/// The hidden vocabulary-UI gate: off unless the environment opts in, so the
/// vocabulary surface stays hidden by default and the normalize/export copy
/// falls back to its vocabulary-free wording.
final class FeatureFlagsTests: XCTestCase {
    private let key = "CUPRIC_VOCABULARY_UI"

    func testAbsentValueReadsAsOff() {
        XCTAssertFalse(FeatureFlags.isEnabled(key, in: [:]))
    }

    func testEmptyValueReadsAsOff() {
        XCTAssertFalse(FeatureFlags.isEnabled(key, in: [key: ""]))
    }

    func testTruthyValuesReadAsOn() {
        for value in ["1", "true", "yes", "on", "TRUE", "On", " 1 "] {
            XCTAssertTrue(FeatureFlags.isEnabled(key, in: [key: value]), "expected \(value.debugDescription) on")
        }
    }

    func testNonTruthyValuesReadAsOff() {
        for value in ["0", "false", "no", "off", "enabled", "2"] {
            XCTAssertFalse(FeatureFlags.isEnabled(key, in: [key: value]), "expected \(value.debugDescription) off")
        }
    }
}
