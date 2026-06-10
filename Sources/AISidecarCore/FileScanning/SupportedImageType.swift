import Foundation

public enum SupportedImageType: String, Codable, CaseIterable, Sendable {
    case nef
    case nrw
    case cr3
    case cr2
    case arw
    case raf
    case orf
    case rw2
    case dng
    case jpg
    case jpeg
    case tif
    case tiff
    case heic
    case png

    public init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }
}
