import XCTest

@testable import AISidecarCore

final class CollectionUtilitiesTests: XCTestCase {
    func testStableUniquePreservesFirstOccurrenceOrder() {
        XCTAssertEqual(stableUnique(["beta", "alpha", "beta", "gamma", "alpha"]), ["beta", "alpha", "gamma"])
    }

    func testFrequencyCountsCountsGenericHashableValues() {
        XCTAssertEqual(frequencyCounts([2, 1, 2, 3, 2, 1]), [1: 2, 2: 3, 3: 1])
    }

    func testSortingBeforeStableUniquePreservesSortedVocabularySynonyms() {
        let terms = ["zebra", "Antelope", "zebra", "antelope"]

        XCTAssertEqual(stableUnique(terms.sorted()), ["Antelope", "antelope", "zebra"])
    }
}
