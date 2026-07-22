import XCTest

@testable import AISidecarCore

final class VocabularyTextFolderTests: XCTestCase {
    func testFoldsCaseWhitespaceAndNFCWithoutRemovingDiacritics() {
        XCTAssertEqual(VocabularyTextFolder.fold("  White\tHERON\n"), "white heron")
        XCTAssertEqual(VocabularyTextFolder.fold("Cafe\u{301}"), VocabularyTextFolder.fold("Café"))
        XCTAssertNotEqual(VocabularyTextFolder.fold("résumé"), VocabularyTextFolder.fold("resume"))
    }

    func testVariantKeyCollapsesNumberPunctuationAndPossessiveVariants() {
        let expected = VocabularyTextFolder.variantKey(for: "White Heron")

        XCTAssertEqual(VocabularyTextFolder.variantKey(for: "white-herons"), expected)
        XCTAssertEqual(VocabularyTextFolder.variantKey(for: "white heron's"), expected)
    }

    func testObservedKeyForwardsToSharedVariantKey() {
        let term = "White-Herons"

        XCTAssertEqual(ObservedTagVocabulary.observedKey(for: term), VocabularyTextFolder.variantKey(for: term))
    }
}
