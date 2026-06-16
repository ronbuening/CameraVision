import Foundation
import ImageIO

/// Read-only affinity metadata extractor for source-image records.
///
/// The persisted `AssetAffinityInputs` intentionally stores presence flags and
/// stable comparison classes, not exact capture timestamps, exact GPS
/// coordinates, or raw serial strings.
public struct AssetAffinityInputExtractor {
    public init() {}

    /// Build privacy-preserving affinity inputs from a resolved source image.
    public func make(
        assetID: String,
        source: SourceImage,
        fileListIndex: Int?
    ) -> AssetAffinityInputs {
        var inputs = AssetAffinityInputBuilder.make(
            assetID: assetID,
            source: source,
            fileListIndex: fileListIndex
        )
        guard
            let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: source.path) as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        else {
            return inputs
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        if stringValue(exif?[kCGImagePropertyExifDateTimeOriginal]) != nil
            || stringValue(tiff?[kCGImagePropertyTIFFDateTime]) != nil {
            inputs.captureTimeStatus = .present
        }
        if properties[kCGImagePropertyGPSDictionary] is [CFString: Any],
           GPSContextExtractor.context(for: source, mode: .coarse)?.gps != nil {
            inputs.gpsStatus = .present
        }

        let make = stringValue(tiff?[kCGImagePropertyTIFFMake])
        let model = stringValue(tiff?[kCGImagePropertyTIFFModel])
        inputs.cameraIdentityClass = normalizedClass([make, model].compactMap { $0 }.joined(separator: " "))
        if let serial = stringValue(metadataValue(exif, named: [
            "BodySerialNumber",
            "SerialNumber",
            "CameraSerialNumber"
        ])) {
            inputs.cameraSerialHash = AssetAffinityInputBuilder.stableSessionHash(serial)
        }
        inputs.lensIdentityClass = normalizedClass(stringValue(metadataValue(exif, named: [
            "LensModel",
            "Lens",
            "LensSpecification"
        ])) ?? "")
        return inputs
    }

    private func metadataValue(_ dictionary: [CFString: Any]?, named names: [String]) -> Any? {
        guard let dictionary else {
            return nil
        }
        let acceptedNames = Set(names)
        for (key, value) in dictionary where acceptedNames.contains(key as String) {
            return value
        }
        return nil
    }

    private func normalizedClass(_ value: String) -> String? {
        let normalized = value
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}
