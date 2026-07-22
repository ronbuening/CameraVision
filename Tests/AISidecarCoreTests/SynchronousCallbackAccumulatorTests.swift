import XCTest

@testable import AISidecarCore

final class SynchronousCallbackAccumulatorTests: XCTestCase {
    func testAppendPreservesOrderForGenericValues() {
        let integers = SynchronousCallbackAccumulator<Int>()
        let strings = SynchronousCallbackAccumulator<String>()

        integers.append(2)
        integers.append(1)
        strings.append("first")
        strings.append("second")

        XCTAssertEqual(integers.values, [2, 1])
        XCTAssertEqual(strings.values, ["first", "second"])
    }
}
