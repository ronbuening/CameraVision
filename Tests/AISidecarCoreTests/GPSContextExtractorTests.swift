import Foundation
import ImageIO
import XCTest
@testable import AISidecarCore

final class GPSContextExtractorTests: XCTestCase {
    func testExactContextUsesSignedCoordinatesFromRefs() throws {
        let context = try XCTUnwrap(GPSContextExtractor.gpsContext(
            from: gpsDictionary(latitude: 45.1234567, latitudeRef: "N", longitude: 122.6543214, longitudeRef: "W"),
            mode: .exact
        ))

        XCTAssertEqual(context.mode, .exact)
        XCTAssertEqual(context.latitude, 45.123457, accuracy: 0.000001)
        XCTAssertEqual(context.longitude, -122.654321, accuracy: 0.000001)
        XCTAssertNil(context.precisionDegrees)
        XCTAssertTrue(context.promptBlock.contains("latitude: 45.123457"))
        XCTAssertTrue(context.promptBlock.contains("longitude: -122.654321"))
    }

    func testCoarseContextRoundsToOneTenthDegree() throws {
        let context = try XCTUnwrap(GPSContextExtractor.gpsContext(
            from: gpsDictionary(latitude: 45.16, latitudeRef: "S", longitude: 122.64, longitudeRef: "E"),
            mode: .coarse
        ))

        XCTAssertEqual(context.mode, .coarse)
        XCTAssertEqual(context.latitude, -45.2, accuracy: 0.000001)
        XCTAssertEqual(context.longitude, 122.6, accuracy: 0.000001)
        XCTAssertEqual(context.precisionDegrees, 0.1)
        XCTAssertTrue(context.promptBlock.contains("coordinate_precision_degrees: 0.1"))
    }

    func testMissingOffAndMalformedGPSProduceNoContext() {
        XCTAssertNil(GPSContextExtractor.gpsContext(from: gpsDictionary(), mode: .coarse))
        XCTAssertNil(GPSContextExtractor.gpsContext(
            from: gpsDictionary(latitude: 95, latitudeRef: "N", longitude: 122, longitudeRef: "W"),
            mode: .exact
        ))
        XCTAssertNil(GPSContextExtractor.gpsContext(
            from: gpsDictionary(latitude: 45, latitudeRef: "north", longitude: 122, longitudeRef: "W"),
            mode: .exact
        ))
        XCTAssertNil(GPSContextExtractor.gpsContext(
            from: gpsDictionary(latitude: 45, latitudeRef: "N", longitude: 122, longitudeRef: "W"),
            mode: .off
        ))
    }

    private func gpsDictionary(
        latitude: Double? = nil,
        latitudeRef: String? = nil,
        longitude: Double? = nil,
        longitudeRef: String? = nil
    ) -> [CFString: Any] {
        var dictionary: [CFString: Any] = [:]
        if let latitude {
            dictionary[kCGImagePropertyGPSLatitude] = latitude
        }
        if let latitudeRef {
            dictionary[kCGImagePropertyGPSLatitudeRef] = latitudeRef
        }
        if let longitude {
            dictionary[kCGImagePropertyGPSLongitude] = longitude
        }
        if let longitudeRef {
            dictionary[kCGImagePropertyGPSLongitudeRef] = longitudeRef
        }
        return dictionary
    }
}
