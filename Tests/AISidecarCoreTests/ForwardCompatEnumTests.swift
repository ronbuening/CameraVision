import Foundation
import XCTest

@testable import AISidecarCore

final class ForwardCompatEnumTests: XCTestCase {
    func testKnownValueMutationChangesEncodedRawValue() throws {
        var field = try JSONDecoder().decode(
            ForwardCompatEnum<TestValue>.self,
            from: Data(#""first""#.utf8)
        )

        XCTAssertEqual(field.value, .first)
        XCTAssertFalse(field.hasUnknownRawValue)

        field.setValue(.second)

        XCTAssertEqual(try JSONEncoder().encode(field), Data(#""second""#.utf8))
    }

    func testUnknownRawValueSurvivesFallbackAndVisibleMutation() throws {
        var field = try JSONDecoder().decode(
            ForwardCompatEnum<TestValue>.self,
            from: Data(#""future-value""#.utf8)
        )

        XCTAssertNil(field.value)
        XCTAssertEqual(field.unknownRawValue, "future-value")
        field.useFallbackForUnknown(.first)
        XCTAssertEqual(field.value, .first)

        field.setValue(.second)

        XCTAssertEqual(field.value, .second)
        XCTAssertEqual(try JSONEncoder().encode(field), Data(#""future-value""#.utf8))
    }

    func testFailClosedOverridePreservesKnownEncodedRawValue() throws {
        var field = ForwardCompatEnum(TestValue.first)

        field.overrideValuePreservingEncodedRaw(.second)

        XCTAssertEqual(field.value, .second)
        XCTAssertFalse(field.hasUnknownRawValue)
        XCTAssertEqual(try JSONEncoder().encode(field), Data(#""first""#.utf8))
    }

    func testOptionalUpdateDistinguishesAbsentFromUnknown() throws {
        let absent = ForwardCompatEnum<TestValue>.updatingOptional(nil, to: nil)
        var unknown = try JSONDecoder().decode(
            ForwardCompatEnum<TestValue>.self,
            from: Data(#""future-value""#.utf8)
        )
        unknown.useFallbackForUnknown(.first)

        let clearedUnknown = ForwardCompatEnum.updatingOptional(unknown, to: nil)

        XCTAssertNil(absent)
        XCTAssertNil(clearedUnknown?.value)
        XCTAssertEqual(try JSONEncoder().encode(clearedUnknown), Data(#""future-value""#.utf8))
    }

    func testNonStringInputRemainsInvalid() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ForwardCompatEnum<TestValue>.self,
                from: Data("1".utf8)
            )
        )
    }
}

private enum TestValue: String, Sendable {
    case first
    case second
}
