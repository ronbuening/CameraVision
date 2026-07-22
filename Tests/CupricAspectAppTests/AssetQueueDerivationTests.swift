import AISidecarCore
import XCTest

@testable import CupricAspectApp

final class AssetQueueDerivationTests: XCTestCase {
    func testCoreDerivedStatesMapToPresentationStates() {
        let cases: [(QueueDerivedState, AssetRecord.StateKind, AssetQueueState)] = [
            (.discovered, .discovered, .discovered),
            (.analyzed, .analyzed, .analyzed),
            (.exported, .exported, .exported),
            (.xmpPresentExternal, .xmpPresentExternal, .xmpPresentExternal),
            (.xmpMissingWasExported, .xmpMissingWasExported, .xmpMissingWasExported),
        ]

        for (derived, expectedKind, expectedState) in cases {
            var record = makeRecord()
            record.stateKind = AssetRecord.StateKind(derivedState: derived)
            XCTAssertEqual(record.stateKind, expectedKind)
            XCTAssertEqual(record.state, expectedState)
        }
    }

    func testFailedStateRemainsTransientGUIPresentationState() {
        var record = makeRecord()
        record.stateKind = .failed
        record.failureCode = "E_TEST"

        XCTAssertEqual(record.state, .failed(code: "E_TEST"))
        XCTAssertEqual(record.state.displayName, "failed · E_TEST")
    }

    private func makeRecord() -> AssetRecord {
        AssetRecord(
            path: "/photos/Bird.NEF",
            relativePath: "Bird.NEF",
            fileName: "Bird.NEF",
            fileExtension: "nef",
            fileSize: 1,
            stateKind: .discovered,
            failureCode: nil,
            failureMessage: nil
        )
    }
}
