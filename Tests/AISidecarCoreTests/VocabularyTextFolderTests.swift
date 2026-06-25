import XCTest
@testable import AISidecarCore

final class VocabularyTextFolderTests: XCTestCase {
    func testFoldsCaseWhitespaceAndNFCWithoutRemovingDiacritics() {
        XCTAssertEqual(VocabularyTextFolder.fold("  White\tHERON\n"), "white heron")
        XCTAssertEqual(VocabularyTextFolder.fold("Cafe\u{301}"), VocabularyTextFolder.fold("Café"))
        XCTAssertNotEqual(VocabularyTextFolder.fold("résumé"), VocabularyTextFolder.fold("resume"))
    }
}
