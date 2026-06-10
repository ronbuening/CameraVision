import CoreGraphics
import CoreImage
import Foundation

enum MaskGeometry {
    static func instanceRecord(
        index: Int,
        maskImage: CIImage,
        dimensions: PixelDimensions,
        context: CIContext
    ) throws -> SubjectInstanceRecord? {
        guard dimensions.width > 0, dimensions.height > 0 else {
            throw isolationFailed("Invalid mask dimensions \(dimensions.width)x\(dimensions.height).")
        }

        let bounds = CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
        var pixels = [UInt8](repeating: 0, count: dimensions.width * dimensions.height)
        context.render(
            maskImage,
            toBitmap: &pixels,
            rowBytes: dimensions.width,
            bounds: bounds,
            format: .R8,
            colorSpace: nil
        )

        var area = 0
        var minX = dimensions.width
        var minY = dimensions.height
        var maxX = -1
        var maxY = -1
        var sumX = 0
        var sumY = 0

        for y in 0..<dimensions.height {
            for x in 0..<dimensions.width {
                let value = pixels[y * dimensions.width + x]
                guard value > 0 else {
                    continue
                }
                area += 1
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                sumX += x
                sumY += y
            }
        }

        guard area > 0 else {
            return nil
        }

        return SubjectInstanceRecord(
            index: index,
            areaPixels: area,
            normalizedBoundingBox: NormalizedBoundingBox(
                x: Double(minX) / Double(dimensions.width),
                y: Double(minY) / Double(dimensions.height),
                width: Double(maxX - minX + 1) / Double(dimensions.width),
                height: Double(maxY - minY + 1) / Double(dimensions.height)
            ),
            normalizedCentroid: NormalizedPoint(
                x: (Double(sumX) / Double(area) + 0.5) / Double(dimensions.width),
                y: (Double(sumY) / Double(area) + 0.5) / Double(dimensions.height)
            )
        )
    }

    static func isolationFailed(_ message: String) -> SidecarError {
        SidecarError(
            code: .subjectIsolationFailed,
            stage: .isolate,
            message: message,
            recoverable: true
        )
    }
}
