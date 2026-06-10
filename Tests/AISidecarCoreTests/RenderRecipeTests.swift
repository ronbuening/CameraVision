import Foundation
import CoreImage
import ImageIO
import XCTest
@testable import AISidecarCore

final class RenderRecipeTests: XCTestCase {
    func testAllEightEXIFOrientationsAreAcceptedAndBaked() throws {
        let recipe = RenderRecipe(profile: .defaultProfile)

        for orientation in 1...8 {
            let resolved = try recipe.resolveOrientation(from: [kCGImagePropertyOrientation: orientation])
            let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20))
            let dimensions = recipe.bakeOrientation(image, orientation: resolved).extent.integral
            if [5, 6, 7, 8].contains(orientation) {
                XCTAssertEqual(Int(dimensions.width), 20)
                XCTAssertEqual(Int(dimensions.height), 40)
            } else {
                XCTAssertEqual(Int(dimensions.width), 40)
                XCTAssertEqual(Int(dimensions.height), 20)
            }
        }
    }

    func testAbsentOrientationDefaultsToOne() throws {
        let recipe = RenderRecipe(profile: .defaultProfile)

        XCTAssertEqual(try recipe.resolveOrientation(from: [:]).exifValue, 1)
    }

    func testInvalidOrientationFailsWithStructuredError() {
        let recipe = RenderRecipe(profile: .defaultProfile)

        XCTAssertThrowsError(try recipe.resolveOrientation(from: [kCGImagePropertyOrientation: 9])) { error in
            guard let sidecarError = error as? SidecarError else {
                return XCTFail("Expected SidecarError")
            }
            XCTAssertEqual(sidecarError.code, .orientationUnresolved)
            XCTAssertEqual(sidecarError.stage, .render)
        }
    }
}
