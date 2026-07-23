import XCTest

@testable import AISidecarCore

final class DisplayTermRankingTests: XCTestCase {
    func testPreferredTermUsesFrequencyBeforeOtherTieBreaks() {
        XCTAssertEqual(DisplayTermRanking.preferredTerm(in: ["Rare", "frequent", "frequent"]), "frequent")
    }

    func testPreferredTermUsesTitleCaseWordCountAfterFrequency() {
        XCTAssertEqual(DisplayTermRanking.preferredTerm(in: ["red fox", "Red Fox"]), "Red Fox")
    }

    func testPreferredTermUsesShortestCharacterCountAfterTitleCaseScore() {
        XCTAssertEqual(DisplayTermRanking.preferredTerm(in: ["Blue Crane", "Blue Jay"]), "Blue Jay")
    }

    func testPreferredTermUsesLowercasedOrderingAfterLength() {
        XCTAssertEqual(DisplayTermRanking.preferredTerm(in: ["zebra", "otter"]), "otter")
    }

    func testPreferredTermUsesLiteralOrderingForCaseOnlyTie() {
        XCTAssertEqual(DisplayTermRanking.preferredTerm(in: ["eagle", "EAGLE"]), "EAGLE")
    }

    func testPreferredTermReturnsEmptyForNoTerms() {
        XCTAssertEqual(DisplayTermRanking.preferredTerm(in: []), "")
    }
}
