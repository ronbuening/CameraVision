import XCTest
@testable import AISidecarCore

final class InstanceSelectionPolicyTests: XCTestCase {
    func testSelectsLargestAreaInstance() {
        let decision = InstanceSelectionPolicy(mergeDominanceThreshold: 0.8).select(from: [
            instance(index: 1, area: 100, x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            instance(index: 2, area: 250, x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        ])

        XCTAssertEqual(decision?.selectedInstanceIndices, [2])
        XCTAssertFalse(decision?.mergedInstances ?? true)
    }

    func testTieBreaksByCentroidProximityToFrameCenter() {
        let decision = InstanceSelectionPolicy(mergeDominanceThreshold: 0.8).select(from: [
            instance(index: 1, area: 100, x: 0.0, y: 0.0, width: 0.1, height: 0.1),
            instance(index: 2, area: 100, x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        ])

        XCTAssertEqual(decision?.selectedInstanceIndices, [2])
    }

    func testMergesWhenSelectedBoxDominatesUnionBox() throws {
        let decision = try XCTUnwrap(InstanceSelectionPolicy(mergeDominanceThreshold: 0.8).select(from: [
            instance(index: 1, area: 10_000, x: 0.10, y: 0.10, width: 0.50, height: 0.50),
            instance(index: 2, area: 100, x: 0.56, y: 0.52, width: 0.04, height: 0.04)
        ]))

        XCTAssertTrue(decision.mergedInstances)
        XCTAssertEqual(decision.selectedInstanceIndices, [1, 2])
        XCTAssertGreaterThanOrEqual(decision.selectedToUnionAreaRatio, 0.8)
    }

    func testDoesNotMergeSeparateSubjectsBelowDominanceThreshold() throws {
        let decision = try XCTUnwrap(InstanceSelectionPolicy(mergeDominanceThreshold: 0.8).select(from: [
            instance(index: 1, area: 10_000, x: 0.10, y: 0.10, width: 0.25, height: 0.25),
            instance(index: 2, area: 1_000, x: 0.75, y: 0.75, width: 0.10, height: 0.10)
        ]))

        XCTAssertFalse(decision.mergedInstances)
        XCTAssertEqual(decision.selectedInstanceIndices, [1])
        XCTAssertLessThan(decision.selectedToUnionAreaRatio, 0.8)
    }

    private func instance(
        index: Int,
        area: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> SubjectInstanceRecord {
        SubjectInstanceRecord(
            index: index,
            areaPixels: area,
            normalizedBoundingBox: NormalizedBoundingBox(x: x, y: y, width: width, height: height),
            normalizedCentroid: NormalizedPoint(x: x + width / 2, y: y + height / 2)
        )
    }
}
