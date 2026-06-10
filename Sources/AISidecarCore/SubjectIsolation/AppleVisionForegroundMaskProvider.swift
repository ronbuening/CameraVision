import CoreImage
import Foundation
import ImageIO
import Vision

/// Apple Vision foreground-instance provider for the production isolation path.
@available(macOS 15.0, *)
public struct AppleVisionForegroundMaskProvider: ForegroundMaskProvider {
    private let context: CIContext

    public init() {
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            self.context = CIContext(options: [
                .workingColorSpace: colorSpace,
                .outputColorSpace: colorSpace
            ])
        } else {
            self.context = CIContext()
        }
    }

    /// Generate per-instance masks and geometry in the whole-image derivative coordinate space.
    public func foregroundMasks(in analysisImage: CIImage, dimensions: PixelDimensions) async throws -> ForegroundMaskResult {
        let handler = ImageRequestHandler(analysisImage, orientation: .up)
        let request = GenerateForegroundInstanceMaskRequest()
        guard let observation = try await handler.perform(request) else {
            return ForegroundMaskResult(instances: [])
        }

        var instances: [ForegroundInstanceMask] = []
        for index in observation.allInstances {
            let maskBuffer = try observation.generateScaledMask(
                for: IndexSet(integer: index),
                scaledToImageFrom: handler
            )
            let maskImage = CIImage(cvPixelBuffer: maskBuffer)
                .cropped(to: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height))
            guard let record = try MaskGeometry.instanceRecord(
                index: index,
                maskImage: maskImage,
                dimensions: dimensions,
                context: context
            ) else {
                continue
            }
            instances.append(ForegroundInstanceMask(record: record, maskImage: maskImage))
        }

        return ForegroundMaskResult(instances: instances)
    }
}
