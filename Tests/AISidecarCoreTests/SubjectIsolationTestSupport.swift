import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import AISidecarCore

struct StaticMaskSpec {
    var index: Int
    var rect: CGRect

    init(index: Int, rect: CGRect) {
        self.index = index
        self.rect = rect
    }
}

func testSourceImage(for url: URL) throws -> SourceImage {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let fileName = url.lastPathComponent
    let fileExtension = url.pathExtension
    return SourceImage(
        path: url.standardizedFileURL.path,
        relativePath: fileName,
        fileName: fileName,
        fileExtension: fileExtension,
        fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
        modifiedAt: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0),
        detectedType: try XCTUnwrap(SupportedImageType(fileExtension: fileExtension)),
        identity: try SourceIdentityCalculator.compute(for: url, policy: .sha256)
    )
}

struct StaticForegroundMaskProvider: ForegroundMaskProvider {
    var specs: [StaticMaskSpec]

    init(_ specs: [StaticMaskSpec]) {
        self.specs = specs
    }

    func foregroundMasks(in analysisImage: CIImage, dimensions: PixelDimensions) async throws -> ForegroundMaskResult {
        let instances = specs.map { spec in
            ForegroundInstanceMask(
                record: SubjectInstanceRecord(
                    index: spec.index,
                    areaPixels: Int(spec.rect.width * spec.rect.height),
                    normalizedBoundingBox: NormalizedBoundingBox(
                        x: spec.rect.minX / Double(dimensions.width),
                        y: spec.rect.minY / Double(dimensions.height),
                        width: spec.rect.width / Double(dimensions.width),
                        height: spec.rect.height / Double(dimensions.height)
                    ),
                    normalizedCentroid: NormalizedPoint(
                        x: spec.rect.midX / Double(dimensions.width),
                        y: spec.rect.midY / Double(dimensions.height)
                    )
                ),
                maskImage: Self.maskImage(rect: spec.rect, dimensions: dimensions)
            )
        }
        return ForegroundMaskResult(instances: instances)
    }

    private static func maskImage(rect: CGRect, dimensions: PixelDimensions) -> CIImage {
        let bounds = CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
        let background = CIImage(color: .black).cropped(to: bounds)
        let foreground = CIImage(color: .white).cropped(to: rect)
        return foreground.composited(over: background).cropped(to: bounds)
    }
}
