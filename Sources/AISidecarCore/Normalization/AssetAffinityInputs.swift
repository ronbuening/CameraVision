import CryptoKit
import Foundation

/// Availability state for an affinity input that may be absent from source metadata.
public enum AssetAffinityInputStatus: String, Codable, Sendable, Equatable {
    case present
    case missing
    case redacted
}

/// Metadata-affinity inputs persisted with Phase 3 sessions.
///
/// Milestone 2 records only values already available from source records and
/// filenames. Later affinity scoring can enrich these fields from read-only
/// image metadata, but the default session path still avoids exact GPS
/// coordinates, exact capture timestamps, and raw camera serials.
public struct AssetAffinityInputs: Codable, Sendable, Equatable {
    public var assetID: String
    public var sourceIdentityHash: String
    public var relativeDirectory: String
    public var fileName: String
    public var filenameStem: String
    public var parsedSequenceNumber: Int?
    public var fileListIndex: Int?
    public var sameBaseNameGroupID: String?
    public var captureTimeStatus: AssetAffinityInputStatus
    public var gpsStatus: AssetAffinityInputStatus
    public var cameraSerialHash: String?
    public var cameraIdentityClass: String?
    public var lensIdentityClass: String?

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case sourceIdentityHash = "source_identity_hash"
        case relativeDirectory = "relative_directory"
        case fileName = "file_name"
        case filenameStem = "filename_stem"
        case parsedSequenceNumber = "parsed_sequence_number"
        case fileListIndex = "file_list_index"
        case sameBaseNameGroupID = "same_base_name_group_id"
        case captureTimeStatus = "capture_time_status"
        case gpsStatus = "gps_status"
        case cameraSerialHash = "camera_serial_hash"
        case cameraIdentityClass = "camera_identity_class"
        case lensIdentityClass = "lens_identity_class"
    }

    public init(
        assetID: String,
        sourceIdentityHash: String,
        relativeDirectory: String,
        fileName: String,
        filenameStem: String,
        parsedSequenceNumber: Int?,
        fileListIndex: Int?,
        sameBaseNameGroupID: String? = nil,
        captureTimeStatus: AssetAffinityInputStatus = .missing,
        gpsStatus: AssetAffinityInputStatus = .missing,
        cameraSerialHash: String? = nil,
        cameraIdentityClass: String? = nil,
        lensIdentityClass: String? = nil
    ) {
        self.assetID = assetID
        self.sourceIdentityHash = sourceIdentityHash
        self.relativeDirectory = relativeDirectory
        self.fileName = fileName
        self.filenameStem = filenameStem
        self.parsedSequenceNumber = parsedSequenceNumber
        self.fileListIndex = fileListIndex
        self.sameBaseNameGroupID = sameBaseNameGroupID
        self.captureTimeStatus = captureTimeStatus
        self.gpsStatus = gpsStatus
        self.cameraSerialHash = cameraSerialHash
        self.cameraIdentityClass = cameraIdentityClass
        self.lensIdentityClass = lensIdentityClass
    }
}

/// Builds the filename-derived portion of affinity inputs.
public enum AssetAffinityInputBuilder {
    public static func make(
        assetID: String,
        source: SourceImage,
        fileListIndex: Int? = nil,
        cameraSerial: String? = nil
    ) -> AssetAffinityInputs {
        let components = source.relativePath.split(separator: "/").map(String.init)
        let directory = Array(components.dropLast()).joined(separator: "/")
        let stem = (source.fileName as NSString).deletingPathExtension
        return AssetAffinityInputs(
            assetID: assetID,
            sourceIdentityHash: source.identity.sha256,
            relativeDirectory: directory,
            fileName: source.fileName,
            filenameStem: stem,
            parsedSequenceNumber: parsedSequenceNumber(from: stem),
            fileListIndex: fileListIndex,
            cameraSerialHash: cameraSerial.map(stableSessionHash)
        )
    }

    /// Parse common camera filename sequence forms without treating arbitrary text as a signal.
    public static func parsedSequenceNumber(from stem: String) -> Int? {
        let upper = stem.uppercased()
        let patterns = ["_DSC", "DSC_", "IMG_", "P"]
        for prefix in patterns where upper.hasPrefix(prefix) {
            let suffix = String(upper.dropFirst(prefix.count))
            guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else {
                continue
            }
            return Int(suffix)
        }
        return nil
    }

    private static func stableSessionHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
