import Foundation
import ImageIO

/// Policy for passing EXIF GPS capture context to model prompts.
public enum GPSContextMode: String, Codable, CaseIterable, Sendable {
    case off
    case coarse
    case exact
}

/// GPS capture context that was actually supplied to a model run.
///
/// Values are persisted because they were sent to the model. `coarse` records
/// one-decimal-degree coordinates and `exact` records the deterministic
/// six-decimal-degree values used in the prompt.
public struct GPSModelInputContext: Codable, Sendable, Equatable {
    public var mode: GPSContextMode
    public var latitude: Double
    public var longitude: Double
    public var precisionDegrees: Double?

    enum CodingKeys: String, CodingKey {
        case mode
        case latitude
        case longitude
        case precisionDegrees = "precision_degrees"
    }

    public init(
        mode: GPSContextMode,
        latitude: Double,
        longitude: Double,
        precisionDegrees: Double? = nil
    ) {
        self.mode = mode
        self.latitude = latitude
        self.longitude = longitude
        self.precisionDegrees = precisionDegrees
    }

    /// Deterministic prompt block appended only when GPS context is available.
    ///
    /// Since prompt v1.5.0 the base prompts carry no GPS or external-context
    /// language, so this block is the model's only source for both the
    /// coordinates and the rules governing them. The instructions keep GPS as
    /// external context, not output metadata or candidate evidence; XMP export
    /// has a separate guard for model mistakes.
    public var promptBlock: String {
        let precisionLine = precisionDegrees.map {
            "\n- coordinate_precision_degrees: \(Self.format($0, fractionDigits: 1))"
        } ?? ""
        return """
        MODEL INPUT CONTEXT

        GPS capture context from the image file's EXIF data, not from the image itself:
        - mode: \(mode.rawValue)
        - latitude: \(Self.format(latitude, fractionDigits: mode == .coarse ? 1 : 6))
        - longitude: \(Self.format(longitude, fractionDigits: mode == .coarse ? 1 : 6))\(precisionLine)

        Use this context only to narrow an identification that visible image evidence already supports.
        Never use this context as the sole reason for a location, species, subject, behavior, habitat, or keyword.
        Never cite GPS, coordinates, EXIF, geotagging, range, or commonness in evidence strings; evidence stays visual.
        Never output coordinates, GPS labels, latitude/longitude, geotag terms, or exact-location keywords.
        """
    }

    private static func format(_ value: Double, fractionDigits: Int) -> String {
        String(format: "%.\(fractionDigits)f", locale: Locale(identifier: "en_US_POSIX"), normalizedZero(value))
    }

    private static func normalizedZero(_ value: Double) -> Double {
        value == 0 ? 0 : value
    }
}

/// External, non-visual context attached to one submitted model input.
public struct ModelInputContext: Codable, Sendable, Equatable {
    public var gps: GPSModelInputContext?

    public init(gps: GPSModelInputContext? = nil) {
        self.gps = gps
    }

    public var isEmpty: Bool {
        gps == nil
    }

    public var promptBlock: String? {
        gps?.promptBlock
    }
}

/// Extracts GPS context from Image I/O metadata without mutating source files.
public enum GPSContextExtractor {
    public static let coarsePrecisionDegrees = 0.1
    /// Exact mode is rounded to the same precision that is serialized into the prompt.
    private static let exactPrecisionDegrees = 0.000001

    /// Read and normalize EXIF GPS context for the configured model-context mode.
    public static func context(for source: SourceImage, mode: GPSContextMode) -> ModelInputContext? {
        guard mode != .off else {
            return nil
        }
        let url = URL(fileURLWithPath: source.path)
        guard
            let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
            let gpsDictionary = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let gps = gpsContext(from: gpsDictionary, mode: mode)
        else {
            return nil
        }
        return ModelInputContext(gps: gps)
    }

    static func gpsContext(from gpsDictionary: [CFString: Any], mode: GPSContextMode) -> GPSModelInputContext? {
        guard mode != .off,
              let latitude = coordinate(
                value: gpsDictionary[kCGImagePropertyGPSLatitude],
                ref: gpsDictionary[kCGImagePropertyGPSLatitudeRef],
                positiveRef: "N",
                negativeRef: "S"
              ),
              let longitude = coordinate(
                value: gpsDictionary[kCGImagePropertyGPSLongitude],
                ref: gpsDictionary[kCGImagePropertyGPSLongitudeRef],
                positiveRef: "E",
                negativeRef: "W"
              ),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else {
            return nil
        }

        switch mode {
        case .off:
            return nil
        case .coarse:
            return GPSModelInputContext(
                mode: .coarse,
                latitude: rounded(latitude, increment: coarsePrecisionDegrees),
                longitude: rounded(longitude, increment: coarsePrecisionDegrees),
                precisionDegrees: coarsePrecisionDegrees
            )
        case .exact:
            return GPSModelInputContext(
                mode: .exact,
                latitude: rounded(latitude, increment: exactPrecisionDegrees),
                longitude: rounded(longitude, increment: exactPrecisionDegrees)
            )
        }
    }

    private static func coordinate(
        value: Any?,
        ref: Any?,
        positiveRef: String,
        negativeRef: String
    ) -> Double? {
        guard let rawCoordinate = doubleValue(value), rawCoordinate.isFinite else {
            return nil
        }
        let normalizedRef = stringValue(ref)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalizedRef {
        case positiveRef:
            return abs(rawCoordinate)
        case negativeRef:
            return -abs(rawCoordinate)
        case nil:
            return rawCoordinate
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        case let value as Int:
            return Double(value)
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let value as NSString:
            return value as String
        default:
            return nil
        }
    }

    private static func rounded(_ value: Double, increment: Double) -> Double {
        let rounded = (value / increment).rounded() * increment
        return rounded == 0 ? 0 : rounded
    }
}
