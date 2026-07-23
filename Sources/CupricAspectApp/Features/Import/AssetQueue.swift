import AISidecarCore
import Foundation

/// Between-launch queue states derived from files on disk, per the binding
/// table in the plan's M1 (requirements FR4-011 in-memory form + FR4-049).
/// Transient in-run states (rendering, analyzing, …) arrive with M2's job
/// engine; do not add derived states beyond this table.
enum AssetQueueState: Equatable {
    case discovered
    case analyzed
    case exported
    case xmpPresentExternal
    case xmpMissingWasExported
    case failed(code: String)

    var displayName: String {
        switch self {
        case .discovered: "discovered"
        case .analyzed: "analyzed"
        case .exported: "exported"
        case .xmpPresentExternal: "XMP present (external)"
        case .xmpMissingWasExported: "XMP missing (was exported)"
        case .failed(let code): "failed · \(code)"
        }
    }
}

/// One row of the in-memory asset queue (FR4-046: no persistence).
struct AssetRecord: Identifiable, Equatable, Sendable {
    var path: String
    var relativePath: String
    var fileName: String
    var fileExtension: String
    var fileSize: Int64
    var stateKind: StateKind
    var failureCode: String?
    var failureMessage: String?

    var id: String { path }

    /// Sendable-friendly flat mirror of `AssetQueueState`.
    enum StateKind: String, Sendable {
        case discovered
        case analyzed
        case exported
        case xmpPresentExternal
        case xmpMissingWasExported
        case failed

        init(derivedState: QueueDerivedState) {
            switch derivedState {
            case .discovered: self = .discovered
            case .analyzed: self = .analyzed
            case .exported: self = .exported
            case .xmpPresentExternal: self = .xmpPresentExternal
            case .xmpMissingWasExported: self = .xmpMissingWasExported
            }
        }
    }

    var state: AssetQueueState {
        switch stateKind {
        case .discovered: .discovered
        case .analyzed: .analyzed
        case .exported: .exported
        case .xmpPresentExternal: .xmpPresentExternal
        case .xmpMissingWasExported: .xmpMissingWasExported
        case .failed: .failed(code: failureCode ?? "unknown")
        }
    }
}
