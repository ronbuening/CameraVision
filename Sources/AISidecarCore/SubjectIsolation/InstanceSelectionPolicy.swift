import Foundation

/// Applies Phase 1's foreground instance selection and merge policy.
public struct InstanceSelectionPolicy: Sendable, Equatable {
    public var mergeDominanceThreshold: Double

    public init(mergeDominanceThreshold: Double) {
        self.mergeDominanceThreshold = mergeDominanceThreshold
    }

    public func select(from instances: [SubjectInstanceRecord]) -> InstanceSelectionDecision? {
        guard let selected = instances.sorted(by: compareInstances).first else {
            return nil
        }

        let allBoundingBox = instances
            .map(\.normalizedBoundingBox)
            .reduce(selected.normalizedBoundingBox) { $0.union($1) }
        let ratio = allBoundingBox.area > 0 ? selected.normalizedBoundingBox.area / allBoundingBox.area : 1
        let shouldMerge = instances.count > 1 && ratio >= mergeDominanceThreshold
        let selectedIndices = shouldMerge
            ? instances.map(\.index).sorted()
            : [selected.index]
        let subjectBoundingBox = instances
            .filter { selectedIndices.contains($0.index) }
            .map(\.normalizedBoundingBox)
            .reduce(selected.normalizedBoundingBox) { $0.union($1) }

        return InstanceSelectionDecision(
            selectedInstanceIndices: selectedIndices,
            mergedInstances: shouldMerge,
            selectedBoundingBox: subjectBoundingBox,
            selectedToUnionAreaRatio: ratio
        )
    }

    private func compareInstances(_ lhs: SubjectInstanceRecord, _ rhs: SubjectInstanceRecord) -> Bool {
        if lhs.areaPixels != rhs.areaPixels {
            return lhs.areaPixels > rhs.areaPixels
        }

        let center = NormalizedPoint(x: 0.5, y: 0.5)
        let lhsDistance = lhs.normalizedCentroid.squaredDistance(to: center)
        let rhsDistance = rhs.normalizedCentroid.squaredDistance(to: center)
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }
        return lhs.index < rhs.index
    }
}

/// Selection result consumed by the crop/mask stage.
public struct InstanceSelectionDecision: Sendable, Equatable {
    public var selectedInstanceIndices: [Int]
    public var mergedInstances: Bool
    public var selectedBoundingBox: NormalizedBoundingBox
    public var selectedToUnionAreaRatio: Double

    public init(
        selectedInstanceIndices: [Int],
        mergedInstances: Bool,
        selectedBoundingBox: NormalizedBoundingBox,
        selectedToUnionAreaRatio: Double
    ) {
        self.selectedInstanceIndices = selectedInstanceIndices
        self.mergedInstances = mergedInstances
        self.selectedBoundingBox = selectedBoundingBox
        self.selectedToUnionAreaRatio = selectedToUnionAreaRatio
    }
}
