import Foundation

/// Project-owned XMP sidecar engine for Phase 2 managed keyword fields.
public struct OwnedXMPSidecarEngine: MetadataWriteEngine {
    /// Stable engine name recorded in future Phase 2 export reports.
    public static let engineName = "owned-xmp-sidecar"

    /// Phase 2 engine implementation version.
    public static let engineVersion = "1.0"

    /// Serialization recipe version for XMP packets emitted by this engine.
    public static let writerRecipeVersion = "owned-xmp-sidecar-writer/1.0"

    private let fileManagerBox: SendableFileManager
    private let preWriteCache: XMPPreWriteCache
    private let parseObserver: (@Sendable (XMPDocumentParsePurpose) -> Void)?

    public init(fileManager: FileManager = .default) {
        self.init(fileManager: fileManager, parseObserver: nil)
    }

    init(
        fileManager: FileManager = .default,
        parseObserver: (@Sendable (XMPDocumentParsePurpose) -> Void)?
    ) {
        self.fileManagerBox = SendableFileManager(fileManager)
        self.preWriteCache = XMPPreWriteCache(fileManager: fileManager, parseObserver: parseObserver)
        self.parseObserver = parseObserver
    }

    public func prepare(configuration _: ResolvedXMPExportConfiguration) throws -> MetadataWriteEngineContext {
        preWriteCache.beginInvocation()
        return MetadataWriteEngineContext(
            engineName: Self.engineName,
            engineVersion: Self.engineVersion,
            writerRecipeVersion: Self.writerRecipeVersion
        )
    }

    public func readSnapshot(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        let targetPath = URL(fileURLWithPath: targetXMPPath).standardizedFileURL.path
        guard fileManagerBox.value.fileExists(atPath: targetPath) else {
            preWriteCache.invalidate(targetPath: targetPath)
            return .empty(targetPath: targetPath, exists: false)
        }
        return try preWriteCache.state(at: targetPath, sourceFileNames: []).snapshot
    }

    public func preview(_ request: XMPWriteRequest) throws -> XMPWritePreview {
        try validateExecutablePlan(request.plan)
        let state = try preWriteState(for: request.plan)
        let snapshot = state.snapshot
        try validateScalarPreconditions(in: request, against: snapshot)
        let parsed = state.parsed
        let outcome = try XMPKeywordMerger().merge(plan: request.plan, into: parsed)
        let resultingSnapshot = try applyPlannedScalars(
            from: request,
            preWriteSnapshot: snapshot,
            to: parsed
        )
        return XMPWritePreview(
            targetXMPPath: request.plan.targetXMPPath,
            wouldCreate: !snapshot.exists,
            existingFlatKeywords: snapshot.flatKeywords,
            existingHierarchicalKeywords: snapshot.hierarchicalKeywords,
            resultingFlatKeywords: outcome.resultingFlatKeywords,
            resultingHierarchicalKeywords: outcome.resultingHierarchicalKeywords,
            flatKeywordsToAdd: outcome.addedFlatKeywords,
            hierarchicalKeywordsToAdd: outcome.addedHierarchicalKeywords,
            warnings: request.plan.sourceVerificationWarnings + request.plan.groupWarnings,
            existingRating: snapshot.rating,
            resultingRating: resultingSnapshot.rating,
            existingLabel: snapshot.label,
            resultingLabel: resultingSnapshot.label,
            existingUrgency: snapshot.urgency,
            resultingUrgency: resultingSnapshot.urgency,
            existingPick: snapshot.pick,
            resultingPick: resultingSnapshot.pick,
            existingGood: snapshot.good,
            resultingGood: resultingSnapshot.good
        )
    }

    public func apply(_ request: XMPWriteRequest) throws -> XMPWriteResult {
        try validateExecutablePlan(request.plan)
        let targetURL = URL(fileURLWithPath: request.plan.targetXMPPath).standardizedFileURL
        let targetPath = targetURL.path
        let state = try preWriteState(for: request.plan)
        let preSnapshot = state.snapshot
        let existed = preSnapshot.exists
        try validateScalarPreconditions(in: request, against: preSnapshot)

        let parsed = state.parsed
        let outcome = try XMPKeywordMerger().merge(plan: request.plan, into: parsed)
        let resultingSnapshot = try applyPlannedScalars(
            from: request,
            preWriteSnapshot: preSnapshot,
            to: parsed
        )
        let shouldWrite =
            !existed
            || !outcome.addedFlatKeywords.isEmpty
            || !outcome.addedHierarchicalKeywords.isEmpty
            || managedScalarsDiffer(preSnapshot, resultingSnapshot)

        guard shouldWrite else {
            return XMPWriteResult(
                targetXMPPath: targetPath,
                created: false,
                modified: false,
                preWriteSnapshot: preSnapshot,
                postWriteSnapshot: preSnapshot,
                addedFlatKeywords: [],
                addedHierarchicalKeywords: [],
                warnings: request.plan.sourceVerificationWarnings + request.plan.groupWarnings,
                existingRating: preSnapshot.rating,
                resultingRating: preSnapshot.rating,
                existingLabel: preSnapshot.label,
                resultingLabel: preSnapshot.label,
                existingUrgency: preSnapshot.urgency,
                resultingUrgency: preSnapshot.urgency,
                existingPick: preSnapshot.pick,
                resultingPick: preSnapshot.pick,
                existingGood: preSnapshot.good,
                resultingGood: preSnapshot.good
            )
        }

        let data = try XMPDocumentWriter().data(for: parsed)
        try AtomicFileWriter.writeFile(to: targetURL, fileManager: fileManagerBox.value) { temporaryURL in
            try data.write(to: temporaryURL)
            // FR2-026: validate the sibling temp sidecar before atomic replacement.
            _ = try validateReadable(at: temporaryURL.path)
        }

        preWriteCache.invalidate(targetPath: targetPath)
        let postSnapshot = try freshSnapshot(at: targetPath)
        return XMPWriteResult(
            targetXMPPath: targetPath,
            created: !existed,
            modified: existed,
            preWriteSnapshot: preSnapshot,
            postWriteSnapshot: postSnapshot,
            addedFlatKeywords: outcome.addedFlatKeywords,
            addedHierarchicalKeywords: outcome.addedHierarchicalKeywords,
            warnings: request.plan.sourceVerificationWarnings + request.plan.groupWarnings,
            existingRating: preSnapshot.rating,
            resultingRating: postSnapshot.rating,
            existingLabel: preSnapshot.label,
            resultingLabel: postSnapshot.label,
            existingUrgency: preSnapshot.urgency,
            resultingUrgency: postSnapshot.urgency,
            existingPick: preSnapshot.pick,
            resultingPick: postSnapshot.pick,
            existingGood: preSnapshot.good,
            resultingGood: postSnapshot.good
        )
    }

    public func validateReadable(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        let targetPath = URL(fileURLWithPath: targetXMPPath).standardizedFileURL.path
        return try freshSnapshot(at: targetPath)
    }

    public func shutdown() throws {
        preWriteCache.endInvocation()
    }

    func beginPreWriteInvocation() {
        preWriteCache.beginInvocation()
    }

    private func preWriteState(
        for plan: XMPChangePlan
    ) throws -> (snapshot: XMPMetadataSnapshot, parsed: XMPParsedDocument) {
        let targetPath = URL(fileURLWithPath: plan.targetXMPPath).standardizedFileURL.path
        if fileManagerBox.value.fileExists(atPath: targetPath) {
            return try preWriteCache.state(
                at: targetPath,
                sourceFileNames: plan.sourceMembers.map(\.sourceFileName)
            )
        }
        preWriteCache.invalidate(targetPath: targetPath)
        return (
            .empty(targetPath: targetPath, exists: false),
            XMPDocumentWriter().makeNewDocument(
                targetPath: targetPath,
                includeHierarchicalBag: !plan.hierarchicalKeywordsToAdd.isEmpty
            )
        )
    }

    private func freshSnapshot(at targetPath: String) throws -> XMPMetadataSnapshot {
        let parsed = try XMPDocumentParser(fileManager: fileManagerBox.value).parseFile(at: targetPath)
        parseObserver?(.validation)
        return try XMPMetadataSnapshot.make(targetPath: targetPath, exists: true, parsed: parsed)
    }

    private func validateExecutablePlan(_ plan: XMPChangePlan) throws {
        guard plan.status == .planned, plan.failures.isEmpty else {
            throw plan.failures.first
                ?? SidecarError(
                    code: .validationFailed,
                    stage: .write,
                    message: "Cannot execute failed XMP change plan for \(plan.targetXMPPath).",
                    recoverable: true
                )
        }
    }

    private func applyPlannedScalars(
        from request: XMPWriteRequest,
        preWriteSnapshot: XMPMetadataSnapshot,
        to parsed: XMPParsedDocument
    ) throws -> XMPMetadataSnapshot {
        let merger = XMPScalarMerger()
        try apply(
            request.ratingWrite,
            to: .rating,
            existingValue: preWriteSnapshot.rating,
            with: merger,
            in: parsed
        )
        try apply(
            request.labelWrite,
            to: .label,
            existingValue: preWriteSnapshot.label,
            with: merger,
            in: parsed
        )
        try apply(
            request.urgencyWrite,
            to: .urgency,
            existingValue: preWriteSnapshot.urgency,
            with: merger,
            in: parsed
        )
        try apply(
            request.pickWrite,
            to: .pick,
            existingValue: preWriteSnapshot.pick,
            with: merger,
            in: parsed
        )
        try apply(
            request.goodWrite,
            to: .good,
            existingValue: preWriteSnapshot.good,
            with: merger,
            in: parsed
        )

        let resultingSnapshot = try XMPMetadataSnapshot.make(
            targetPath: parsed.targetPath,
            exists: true,
            parsed: parsed
        )
        if try appliedValue(for: .urgency, write: request.urgencyWrite) != nil,
            resultingSnapshot.label?.isEmpty != false
        {
            throw SidecarError(
                code: .validationFailed,
                stage: .write,
                message: "Cannot write photoshop:Urgency without a resulting xmp:Label value.",
                recoverable: true
            )
        }
        let appliedPick = try appliedValue(for: .pick, write: request.pickWrite)
        let appliedGood = try appliedValue(for: .good, write: request.goodWrite)
        if appliedPick != nil || appliedGood != nil {
            // Lightroom treats pick/good as one flag: picked = 1/true,
            // rejected = -1/false. A split pair would round-trip wrong.
            let consistentPairs: [(String, String)] = [("1", "true"), ("-1", "false")]
            let resultingPair = (resultingSnapshot.pick ?? "", resultingSnapshot.good ?? "")
            guard consistentPairs.contains(where: { $0 == resultingPair }) else {
                throw SidecarError(
                    code: .validationFailed,
                    stage: .write,
                    message:
                        "Cannot write an inconsistent xmpDM:pick/xmpDM:good flag pair "
                        + "(\(resultingPair.0)/\(resultingPair.1)).",
                    recoverable: true
                )
            }
        }
        return resultingSnapshot
    }

    private func validateScalarPreconditions(
        in request: XMPWriteRequest,
        against snapshot: XMPMetadataSnapshot
    ) throws {
        try validateScalarPrecondition(request.ratingWrite, for: .rating, currentValue: snapshot.rating)
        try validateScalarPrecondition(request.labelWrite, for: .label, currentValue: snapshot.label)
        try validateScalarPrecondition(request.urgencyWrite, for: .urgency, currentValue: snapshot.urgency)
        try validateScalarPrecondition(request.pickWrite, for: .pick, currentValue: snapshot.pick)
        try validateScalarPrecondition(request.goodWrite, for: .good, currentValue: snapshot.good)
        try validateUrgencyLabelPrecondition(in: request, against: snapshot)
    }

    private func validateScalarPrecondition(
        _ write: PlannedScalarWrite?,
        for scalar: XMPManagedScalar,
        currentValue: String?
    ) throws {
        guard try appliedValue(for: scalar, write: write) != nil, write?.existingValue != currentValue else {
            return
        }
        throw XMPScalarWritePreconditionFailure(scalar: scalar)
    }

    private func validateUrgencyLabelPrecondition(
        in request: XMPWriteRequest,
        against snapshot: XMPMetadataSnapshot
    ) throws {
        guard try appliedValue(for: .urgency, write: request.urgencyWrite) != nil,
            let labelWrite = request.labelWrite
        else {
            return
        }
        let resultingLabel = try appliedValue(for: .label, write: labelWrite) ?? snapshot.label
        guard resultingLabel == labelWrite.plannedValue else {
            throw XMPScalarWritePreconditionFailure(scalar: .label)
        }
    }

    private func apply(
        _ write: PlannedScalarWrite?,
        to scalar: XMPManagedScalar,
        existingValue: String?,
        with merger: XMPScalarMerger,
        in parsed: XMPParsedDocument
    ) throws {
        guard let value = try appliedValue(for: scalar, write: write), value != existingValue else {
            return
        }
        try merger.setScalar(scalar, to: value, in: parsed)
    }

    private func appliedValue(for scalar: XMPManagedScalar, write: PlannedScalarWrite?) throws -> String? {
        guard let write else {
            return nil
        }
        guard write.field == scalar.qualifiedPropertyName else {
            throw SidecarError(
                code: .validationFailed,
                stage: .write,
                message:
                    "Scalar plan slot for \(scalar.qualifiedPropertyName) contains mismatched field \(write.field).",
                recoverable: true
            )
        }
        switch write.action {
        case .write, .overwrite:
            return write.plannedValue
        case .skipExisting:
            return nil
        }
    }

    private func managedScalarsDiffer(_ lhs: XMPMetadataSnapshot, _ rhs: XMPMetadataSnapshot) -> Bool {
        lhs.rating != rhs.rating || lhs.label != rhs.label || lhs.urgency != rhs.urgency
            || lhs.pick != rhs.pick || lhs.good != rhs.good
    }
}

enum XMPDocumentParsePurpose: Hashable, Sendable {
    case preWrite
    case validation
}

/// Retains immutable parse bases only while an engine invocation is active.
/// Each merge receives a deep copy, while file identity changes force a fresh
/// parse before any mutation can use the cached snapshot.
private final class XMPPreWriteCache: @unchecked Sendable {
    private struct FileIdentity: Equatable {
        let inode: UInt64
        let modificationDate: Date
        let size: UInt64
    }

    private struct Entry {
        let identity: FileIdentity
        let parsed: XMPParsedDocument
        let snapshot: XMPMetadataSnapshot
    }

    private let fileManagerBox: SendableFileManager
    private let parseObserver: (@Sendable (XMPDocumentParsePurpose) -> Void)?
    private let lock = NSLock()
    private var invocationDepth = 0
    private var entriesByPath: [String: Entry] = [:]

    init(
        fileManager: FileManager,
        parseObserver: (@Sendable (XMPDocumentParsePurpose) -> Void)?
    ) {
        self.fileManagerBox = SendableFileManager(fileManager)
        self.parseObserver = parseObserver
    }

    func beginInvocation() {
        lock.withLock {
            if invocationDepth == 0 {
                entriesByPath.removeAll(keepingCapacity: false)
            }
            invocationDepth += 1
        }
    }

    func endInvocation() {
        lock.withLock {
            guard invocationDepth > 0 else {
                entriesByPath.removeAll(keepingCapacity: false)
                return
            }
            invocationDepth -= 1
            if invocationDepth == 0 {
                entriesByPath.removeAll(keepingCapacity: false)
            }
        }
    }

    func state(
        at targetPath: String,
        sourceFileNames: [String]
    ) throws -> (snapshot: XMPMetadataSnapshot, parsed: XMPParsedDocument) {
        try lock.withLock {
            let shouldCache = invocationDepth > 0
            for _ in 0..<2 {
                let identityBeforeParse = try fileIdentity(at: targetPath)
                let entry: Entry
                if shouldCache,
                    let cached = entriesByPath[targetPath],
                    cached.identity == identityBeforeParse
                {
                    entry = cached
                } else {
                    let parsed = try XMPDocumentParser(fileManager: fileManagerBox.value).parseFile(at: targetPath)
                    parseObserver?(.preWrite)
                    let identityAfterParse = try fileIdentity(at: targetPath)
                    guard identityBeforeParse == identityAfterParse else {
                        entriesByPath.removeValue(forKey: targetPath)
                        continue
                    }
                    entry = Entry(
                        identity: identityAfterParse,
                        parsed: parsed,
                        snapshot: try XMPMetadataSnapshot.make(
                            targetPath: targetPath,
                            exists: true,
                            parsed: parsed
                        )
                    )
                    if shouldCache {
                        entriesByPath[targetPath] = entry
                    }
                }

                return (
                    entry.snapshot,
                    try XMPDocumentParser(fileManager: fileManagerBox.value).copy(
                        entry.parsed,
                        sourceFileNames: sourceFileNames
                    )
                )
            }

            throw XMPXML.sidecarError(
                code: .xmpParseFailed,
                message: "XMP sidecar \(targetPath) changed while it was being read."
            )
        }
    }

    func invalidate(targetPath: String) {
        _ = lock.withLock {
            entriesByPath.removeValue(forKey: targetPath)
        }
    }

    private func fileIdentity(at targetPath: String) throws -> FileIdentity {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManagerBox.value.attributesOfItem(atPath: targetPath)
        } catch {
            throw XMPXML.sidecarError(
                code: .xmpParseFailed,
                message: "Unable to inspect XMP sidecar \(targetPath): \(error.localizedDescription)"
            )
        }
        guard let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            let modificationDate = attributes[.modificationDate] as? Date,
            let size = (attributes[.size] as? NSNumber)?.uint64Value
        else {
            throw XMPXML.sidecarError(
                code: .xmpParseFailed,
                message: "Unable to identify XMP sidecar \(targetPath) for a stable read."
            )
        }
        return FileIdentity(inode: inode, modificationDate: modificationDate, size: size)
    }
}

/// Thrown before any mutation when a plan's recorded scalar state no longer
/// matches the target document. The wrapper type — not the wrapped message —
/// is the contract that lets the pipeline keep the newer on-disk edit instead
/// of restoring a pre-plan backup over it.
struct XMPScalarWritePreconditionFailure: Error, LocalizedError {
    let sidecarError: SidecarError

    init(scalar: XMPManagedScalar) {
        sidecarError = SidecarError(
            code: .validationFailed,
            stage: .write,
            message:
                "Scalar precondition failed for \(scalar.qualifiedPropertyName): the current XMP value "
                + "no longer matches the value recorded in the change plan.",
            recoverable: true
        )
    }

    var errorDescription: String? {
        sidecarError.errorDescription
    }
}

private struct SendableFileManager: @unchecked Sendable {
    var value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}
