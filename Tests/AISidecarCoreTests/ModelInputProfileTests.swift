import XCTest
@testable import AISidecarCore

final class ModelInputProfileTests: XCTestCase {
    func testDefaultProfileMatchesMilestonePlan() throws {
        let profile = try ModelInputProfileRegistry.resolve(name: "gemma4-26b-default")

        XCTAssertEqual(profile.name, "gemma4-26b-default")
        XCTAssertEqual(profile.maxLongEdge, 2048)
        XCTAssertEqual(profile.maxTotalPixels, 4_194_304)
        XCTAssertEqual(profile.colorSpace, .sRGB)
        XCTAssertEqual(profile.preferredWholeImageFormat, .jpeg)
        XCTAssertEqual(profile.jpegQuality, 0.9)
        XCTAssertEqual(profile.preferredSubjectFormat, "jpeg-neutral-matte")
        XCTAssertEqual(profile.matteRGB, [128, 128, 128])
        XCTAssertFalse(profile.allowUpscaleSubjectByDefault)
    }

    func testUnknownProfileFailsAsConfigInvalid() {
        XCTAssertThrowsError(try ModelInputProfileRegistry.resolve(name: "unknown")) { error in
            guard let sidecarError = error as? SidecarError else {
                return XCTFail("Expected SidecarError")
            }
            XCTAssertEqual(sidecarError.code, .configInvalid)
            XCTAssertEqual(sidecarError.stage, .configuration)
        }
    }

    func testBenchmarkProfilesUseNamedLongEdgeSweeps() throws {
        let profile1024 = try ModelInputProfileRegistry.resolve(name: "gemma4-26b-benchmark-1024")
        let profile1536 = try ModelInputProfileRegistry.resolve(name: "gemma4-26b-benchmark-1536")

        XCTAssertEqual(profile1024.maxLongEdge, 1_024)
        XCTAssertEqual(profile1024.maxTotalPixels, 1_048_576)
        XCTAssertEqual(profile1536.maxLongEdge, 1_536)
        XCTAssertEqual(profile1536.maxTotalPixels, 2_359_296)
        XCTAssertEqual(profile1024.preferredSubjectFormat, ModelInputProfile.defaultProfile.preferredSubjectFormat)
        XCTAssertEqual(profile1536.matteRGB, ModelInputProfile.defaultProfile.matteRGB)
    }

    func testResizeMathPreservesAspectAndDoesNotUpscale() throws {
        let profile = ModelInputProfile.defaultProfile

        XCTAssertEqual(
            try profile.fittedDimensions(width: 4000, height: 2000),
            PixelDimensions(width: 2048, height: 1024)
        )
        XCTAssertEqual(
            try profile.fittedDimensions(width: 4000, height: 4000),
            PixelDimensions(width: 2048, height: 2048)
        )
        XCTAssertEqual(
            try profile.fittedDimensions(width: 800, height: 600),
            PixelDimensions(width: 800, height: 600)
        )
    }
}
