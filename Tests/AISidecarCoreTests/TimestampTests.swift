import XCTest

@testable import AISidecarCore

final class TimestampTests: XCTestCase {
    func testFilenameSafeContainsNoReservedCharacters() {
        let value = Timestamp.filenameSafe(Date(timeIntervalSince1970: 1_782_000_000))

        XCTAssertFalse(value.contains(":"))
        XCTAssertTrue(value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
    }

    func testInternetDateTimeRemainsUnchangedForProvenanceFields() {
        XCTAssertEqual(
            Timestamp.internetDateTime(Date(timeIntervalSince1970: 0)),
            "1970-01-01T00:00:00Z"
        )
    }

    func testFilenameTokensDeCollideRunsStartedInTheSameSecond() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(Timestamp.filenameToken(date, suffix: "a3f2"), "2027-01-15T080000Z-a3f2")
        XCTAssertNotEqual(
            Timestamp.filenameToken(date, suffix: "a3f2"),
            Timestamp.filenameToken(date, suffix: "beef")
        )
    }

    func testRandomFilenameSuffixIsFourLowercaseHexCharacters() {
        let suffix = Timestamp.randomFilenameSuffix()

        XCTAssertEqual(suffix.count, 4)
        XCTAssertTrue(suffix.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) })
    }

    func testDurationMillisecondsRoundsToNearestMillisecond() {
        let start = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(Timestamp.durationMs(from: start, to: start.addingTimeInterval(0.0014)), 1)
        XCTAssertEqual(Timestamp.durationMs(from: start, to: start.addingTimeInterval(0.0016)), 2)
    }

    func testDurationMillisecondsIsZeroForZeroAndNegativeIntervals() {
        let start = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(Timestamp.durationMs(from: start, to: start), 0)
        XCTAssertEqual(Timestamp.durationMs(from: start, to: start.addingTimeInterval(-1)), 0)
    }

    func testCleanupClassifiesLegacyAndFilesystemSafeArtifactNames() {
        XCTAssertEqual(
            ArtifactCleanup.classify(fileName: "batch-progress-2026-07-07T18:00:00Z.jsonl"),
            .analyzeProgressLog
        )
        XCTAssertEqual(
            ArtifactCleanup.classify(fileName: "batch-progress-2026-07-07T180000Z-a3f2.jsonl"),
            .analyzeProgressLog
        )
    }
}
