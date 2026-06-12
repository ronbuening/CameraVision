import Foundation

/// Phase 2 source class used by same-base-name pair-scope selection.
public enum XMPSourcePairKind: String, Codable, Sendable, Equatable {
    case rawLike = "raw_like"
    case jpeg
    case other
}

/// Stable key for exact same-base-name grouping before case-insensitive collision checks.
public struct SameBaseNameGroupKey: Hashable, Sendable, Equatable {
    public var directory: String
    public var basename: String

    public init(directory: String, basename: String) {
        self.directory = directory
        self.basename = basename
    }
}

/// One named source member prepared for group-level XMP planning.
public struct SameBaseNameGroupMember: Sendable, Equatable {
    public var input: ResolvedRawSidecarInput
    public var destination: XMPNamingDestination
    public var extractionResult: CandidateExtractionResult
    public var pairKind: XMPSourcePairKind

    public init(
        input: ResolvedRawSidecarInput,
        destination: XMPNamingDestination,
        extractionResult: CandidateExtractionResult,
        pairKind: XMPSourcePairKind
    ) {
        self.input = input
        self.destination = destination
        self.extractionResult = extractionResult
        self.pairKind = pairKind
    }
}

/// Exact same-base-name group that maps to a single XMP sidecar target.
public struct SameBaseNameGroup: Sendable, Equatable {
    public var key: SameBaseNameGroupKey
    public var targetXMPPath: String
    public var targetRelativePath: String
    public var members: [SameBaseNameGroupMember]

    public init(
        key: SameBaseNameGroupKey,
        targetXMPPath: String,
        targetRelativePath: String,
        members: [SameBaseNameGroupMember]
    ) {
        self.key = key
        self.targetXMPPath = targetXMPPath
        self.targetRelativePath = targetRelativePath
        self.members = members
    }
}

/// Group selection result after applying `--pair-scope`.
public struct SameBaseNameSelectedGroup: Sendable, Equatable {
    public var group: SameBaseNameGroup
    public var selectedMembers: [SameBaseNameGroupMember]
    public var skippedMembers: [SameBaseNameGroupMember]
    public var warnings: [SidecarError]
    public var failures: [SidecarError]

    public init(
        group: SameBaseNameGroup,
        selectedMembers: [SameBaseNameGroupMember],
        skippedMembers: [SameBaseNameGroupMember],
        warnings: [SidecarError],
        failures: [SidecarError]
    ) {
        self.group = group
        self.selectedMembers = selectedMembers
        self.skippedMembers = skippedMembers
        self.warnings = warnings
        self.failures = failures
    }
}

/// Resolves Phase 2 shared-XMP groups before the writer milestone exists.
public struct SameBaseNameGroupResolver {
    public init() {}

    /// Build exact same-base-name groups and apply pair-scope filtering.
    ///
    /// Groups are keyed by source-relative directory plus basename. A later
    /// case-insensitive pass marks case-only target differences as collisions
    /// without preventing legitimate RAW+JPEG pairs from sharing one target.
    public func resolve(
        entries: [XMPNamingEntry],
        extractionResults: [String: CandidateExtractionResult],
        pairScope: XMPPairScope
    ) -> [SameBaseNameSelectedGroup] {
        let members = entries.compactMap { entry -> SameBaseNameGroupMember? in
            let sidecarPath = entry.input.sidecarPath.standardizedFileURL.path
            guard let extractionResult = extractionResults[sidecarPath] else {
                return nil
            }
            return SameBaseNameGroupMember(
                input: entry.input,
                destination: entry.destination,
                extractionResult: extractionResult,
                pairKind: XMPSourcePairKind(sourceType: entry.input.document.sidecar.source.detectedType)
            )
        }
        let groupedMembers = Dictionary(grouping: members) { member in
            SameBaseNameGroupKey(
                directory: member.destination.groupDirectory,
                basename: member.destination.groupBasename
            )
        }

        let exactGroups = groupedMembers.map { key, members in
            let sortedMembers = members.sorted { compareMembers($0, $1) }
            let first = sortedMembers[0]
            return SameBaseNameGroup(
                key: key,
                targetXMPPath: first.destination.targetXMPPath,
                targetRelativePath: first.destination.targetRelativePath,
                members: sortedMembers
            )
        }
        .sorted { compareGroups($0, $1) }

        // Exact basename grouping permits RAW/JPEG pairs to share a sidecar.
        // A separate case-insensitive pass catches case-only paths that would
        // alias on common photo-library filesystems.
        let collisionKeys = Set(
            Dictionary(grouping: exactGroups) { $0.targetXMPPath.lowercased() }
                .filter { $0.value.count > 1 }
                .keys
        )

        return exactGroups.map { group in
            var warnings = groupWarnings(for: group, pairScope: pairScope)
            var failures: [SidecarError] = []

            let selectedMembers: [SameBaseNameGroupMember]
            let skippedMembers: [SameBaseNameGroupMember]
            switch pairScope {
            case .union:
                selectedMembers = group.members
                skippedMembers = []
            case .rawOnly:
                selectedMembers = group.members.filter { $0.pairKind == .rawLike }
                skippedMembers = group.members.filter { $0.pairKind != .rawLike }
            case .jpegOnly:
                selectedMembers = group.members.filter { $0.pairKind == .jpeg }
                skippedMembers = group.members.filter { $0.pairKind != .jpeg }
            }

            if collisionKeys.contains(group.targetXMPPath.lowercased()) {
                failures.append(collisionError(for: group))
            }
            if selectedMembers.isEmpty {
                failures.append(emptySelectionError(for: group, pairScope: pairScope))
            }
            if !skippedMembers.isEmpty, pairScope != .union {
                warnings.append(restrictiveScopeWarning(for: group, pairScope: pairScope))
            }

            return SameBaseNameSelectedGroup(
                group: group,
                selectedMembers: selectedMembers,
                skippedMembers: skippedMembers,
                warnings: warnings,
                failures: failures
            )
        }
    }

    private func groupWarnings(for group: SameBaseNameGroup, pairScope: XMPPairScope) -> [SidecarError] {
        guard group.members.count > 1 else {
            return []
        }
        return [
            SidecarError(
                code: .validationFailed,
                stage: .write,
                message: "Same-base-name group detected for \(group.targetRelativePath) using pair scope \(pairScope.rawValue).",
                recoverable: true
            )
        ]
    }

    private func restrictiveScopeWarning(for group: SameBaseNameGroup, pairScope: XMPPairScope) -> SidecarError {
        SidecarError(
            code: .validationFailed,
            stage: .write,
            message: "Pair scope \(pairScope.rawValue) skipped \(group.members.count - selectedCount(group, pairScope: pairScope)) member(s) for \(group.targetRelativePath).",
            recoverable: true
        )
    }

    private func selectedCount(_ group: SameBaseNameGroup, pairScope: XMPPairScope) -> Int {
        switch pairScope {
        case .union:
            return group.members.count
        case .rawOnly:
            return group.members.filter { $0.pairKind == .rawLike }.count
        case .jpegOnly:
            return group.members.filter { $0.pairKind == .jpeg }.count
        }
    }

    private func collisionError(for group: SameBaseNameGroup) -> SidecarError {
        let sources = group.members.map { $0.input.document.sidecar.source.relativePath }.joined(separator: ", ")
        return SidecarError(
            code: .sidecarCollision,
            stage: .write,
            message: "Case-insensitive XMP target collision for \(group.targetXMPPath): \(sources)",
            recoverable: true
        )
    }

    private func emptySelectionError(for group: SameBaseNameGroup, pairScope: XMPPairScope) -> SidecarError {
        SidecarError(
            code: .validationFailed,
            stage: .write,
            message: "Pair scope \(pairScope.rawValue) selected no source members for \(group.targetRelativePath).",
            recoverable: true
        )
    }
}

public extension XMPSourcePairKind {
    init(sourceType: SupportedImageType) {
        switch sourceType {
        case .nef, .nrw, .cr3, .cr2, .arw, .raf, .orf, .rw2, .dng:
            self = .rawLike
        case .jpg, .jpeg:
            self = .jpeg
        case .tif, .tiff, .heic, .png:
            self = .other
        }
    }
}

private func compareMembers(_ lhs: SameBaseNameGroupMember, _ rhs: SameBaseNameGroupMember) -> Bool {
    comparePaths(lhs.input.document.sidecar.source.relativePath, rhs.input.document.sidecar.source.relativePath)
}

private func compareGroups(_ lhs: SameBaseNameGroup, _ rhs: SameBaseNameGroup) -> Bool {
    comparePaths(lhs.targetRelativePath, rhs.targetRelativePath)
}

private func comparePaths(_ lhs: String, _ rhs: String) -> Bool {
    let lowerLHS = lhs.lowercased()
    let lowerRHS = rhs.lowercased()
    if lowerLHS == lowerRHS {
        return lhs < rhs
    }
    return lowerLHS < lowerRHS
}
