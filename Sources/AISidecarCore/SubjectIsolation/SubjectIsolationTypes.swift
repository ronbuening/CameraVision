import CoreGraphics
import CoreImage
import Foundation

/// Normalized rectangle recorded for Vision foreground instances.
///
/// Coordinates are fractions of the analysis image with origin matching Core
/// Image mask coordinates; the service maps them back to full-resolution pixels.
public struct NormalizedBoundingBox: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double {
        x + width
    }

    public var maxY: Double {
        y + height
    }

    public var area: Double {
        max(0, width) * max(0, height)
    }

    public func union(_ other: NormalizedBoundingBox) -> NormalizedBoundingBox {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        let maxX = max(maxX, other.maxX)
        let maxY = max(maxY, other.maxY)
        return NormalizedBoundingBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func scaled(to dimensions: PixelDimensions) -> PixelBoundingBox {
        let minX = max(0, Int(floor(x * Double(dimensions.width))))
        let minY = max(0, Int(floor(y * Double(dimensions.height))))
        let maxX = min(dimensions.width, Int(ceil(maxX * Double(dimensions.width))))
        let maxY = min(dimensions.height, Int(ceil(maxY * Double(dimensions.height))))
        return PixelBoundingBox(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }
}

/// Pixel-space crop rectangle recorded for the full-resolution subject crop.
public struct PixelBoundingBox: Codable, Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var maxX: Int {
        x + width
    }

    public var maxY: Int {
        y + height
    }

    public func expanded(by margin: Int, within dimensions: PixelDimensions) -> PixelBoundingBox {
        let minX = max(0, x - margin)
        let minY = max(0, y - margin)
        let maxX = min(dimensions.width, maxX + margin)
        let maxY = min(dimensions.height, maxY + margin)
        return PixelBoundingBox(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
}

/// Normalized point used for instance centroid tie-breaking.
public struct NormalizedPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func squaredDistance(to other: NormalizedPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}

/// Foreground-instance geometry retained in raw sidecar provenance.
public struct SubjectInstanceRecord: Codable, Sendable, Equatable {
    public var index: Int
    public var areaPixels: Int
    public var normalizedBoundingBox: NormalizedBoundingBox
    public var normalizedCentroid: NormalizedPoint

    enum CodingKeys: String, CodingKey {
        case index
        case areaPixels = "area_pixels"
        case normalizedBoundingBox = "normalized_bounding_box"
        case normalizedCentroid = "normalized_centroid"
    }

    public init(
        index: Int,
        areaPixels: Int,
        normalizedBoundingBox: NormalizedBoundingBox,
        normalizedCentroid: NormalizedPoint
    ) {
        self.index = index
        self.areaPixels = areaPixels
        self.normalizedBoundingBox = normalizedBoundingBox
        self.normalizedCentroid = normalizedCentroid
    }
}

/// Scale factors used when mapping analysis-resolution masks to full-resolution pixels.
public struct SubjectIsolationScaleFactors: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// High-level status for a subject-isolation attempt.
public enum SubjectIsolationStatus: String, Codable, Sendable, Equatable {
    case success
    case noForeground = "no_foreground"
    case failed
}

/// Sidecar payload describing the foreground-mask decision and output crop.
public struct SubjectIsolationRecord: Codable, Sendable, Equatable {
    public var status: SubjectIsolationStatus
    public var instanceCount: Int
    public var selectedInstanceIndices: [Int]
    public var mergedInstances: Bool
    public var instances: [SubjectInstanceRecord]
    public var analysisResolution: PixelDimensions
    public var fullResolution: PixelDimensions
    public var scaleFactors: SubjectIsolationScaleFactors
    public var selectedBoundingBox: NormalizedBoundingBox?
    public var cropBoundingBox: PixelBoundingBox?
    public var cropMarginFraction: Double
    public var cropMarginPixels: Int
    public var mergeDominanceThreshold: Double
    public var selectedToUnionAreaRatio: Double?
    public var matteRGB: [Int]
    public var finalDimensions: PixelDimensions?
    public var upscaled: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case instanceCount = "instance_count"
        case selectedInstanceIndices = "selected_instance_indices"
        case mergedInstances = "merged_instances"
        case instances
        case analysisResolution = "analysis_resolution"
        case fullResolution = "full_resolution"
        case scaleFactors = "scale_factors"
        case selectedBoundingBox = "selected_bounding_box"
        case cropBoundingBox = "crop_bounding_box"
        case cropMarginFraction = "crop_margin_fraction"
        case cropMarginPixels = "crop_margin_pixels"
        case mergeDominanceThreshold = "merge_dominance_threshold"
        case selectedToUnionAreaRatio = "selected_to_union_area_ratio"
        case matteRGB = "matte_rgb"
        case finalDimensions = "final_dimensions"
        case upscaled
    }

    public init(
        status: SubjectIsolationStatus,
        instanceCount: Int,
        selectedInstanceIndices: [Int],
        mergedInstances: Bool,
        instances: [SubjectInstanceRecord],
        analysisResolution: PixelDimensions,
        fullResolution: PixelDimensions,
        scaleFactors: SubjectIsolationScaleFactors,
        selectedBoundingBox: NormalizedBoundingBox?,
        cropBoundingBox: PixelBoundingBox?,
        cropMarginFraction: Double,
        cropMarginPixels: Int,
        mergeDominanceThreshold: Double,
        selectedToUnionAreaRatio: Double?,
        matteRGB: [Int],
        finalDimensions: PixelDimensions?,
        upscaled: Bool
    ) {
        self.status = status
        self.instanceCount = instanceCount
        self.selectedInstanceIndices = selectedInstanceIndices
        self.mergedInstances = mergedInstances
        self.instances = instances
        self.analysisResolution = analysisResolution
        self.fullResolution = fullResolution
        self.scaleFactors = scaleFactors
        self.selectedBoundingBox = selectedBoundingBox
        self.cropBoundingBox = cropBoundingBox
        self.cropMarginFraction = cropMarginFraction
        self.cropMarginPixels = cropMarginPixels
        self.mergeDominanceThreshold = mergeDominanceThreshold
        self.selectedToUnionAreaRatio = selectedToUnionAreaRatio
        self.matteRGB = matteRGB
        self.finalDimensions = finalDimensions
        self.upscaled = upscaled
    }
}

/// One foreground instance mask at analysis resolution.
///
/// `CIImage` is treated as immutable image recipe data while it moves through
/// the isolation worker that requested it.
public struct ForegroundInstanceMask: @unchecked Sendable {
    public var record: SubjectInstanceRecord
    public var maskImage: CIImage

    public init(record: SubjectInstanceRecord, maskImage: CIImage) {
        self.record = record
        self.maskImage = maskImage
    }
}

/// Foreground masks returned from the Apple Vision provider or a test fixture.
///
/// Instances are consumed by the same isolation operation that receives them;
/// this unchecked boundary keeps Core Image details out of the public protocol.
public struct ForegroundMaskResult: @unchecked Sendable {
    public var instances: [ForegroundInstanceMask]

    public init(instances: [ForegroundInstanceMask]) {
        self.instances = instances
    }
}

/// Mask-generation seam that keeps XCTest deterministic while production uses Apple Vision.
public protocol ForegroundMaskProvider: Sendable {
    func foregroundMasks(in analysisImage: CIImage, dimensions: PixelDimensions) async throws -> ForegroundMaskResult
}

/// Result returned by the subject-isolation service for one source image.
public struct SubjectIsolationResult: Sendable {
    public var record: SubjectIsolationRecord
    public var derivative: DerivativeRecord?
    public var error: SidecarError?

    public init(record: SubjectIsolationRecord, derivative: DerivativeRecord?, error: SidecarError?) {
        self.record = record
        self.derivative = derivative
        self.error = error
    }
}
