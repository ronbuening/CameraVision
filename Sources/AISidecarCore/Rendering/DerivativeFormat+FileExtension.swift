extension DerivativeFormat {
    var fileExtension: String {
        switch self {
        case .jpeg:
            return "jpg"
        case .tiff:
            return "tiff"
        }
    }
}
