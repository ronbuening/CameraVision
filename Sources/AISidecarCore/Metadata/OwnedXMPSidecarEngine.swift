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

    public init(fileManager: FileManager = .default) {
        self.fileManagerBox = SendableFileManager(fileManager)
    }

    public func prepare(configuration _: ResolvedXMPExportConfiguration) throws -> MetadataWriteEngineContext {
        MetadataWriteEngineContext(
            engineName: Self.engineName,
            engineVersion: Self.engineVersion,
            writerRecipeVersion: Self.writerRecipeVersion
        )
    }

    public func readSnapshot(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        let targetPath = URL(fileURLWithPath: targetXMPPath).standardizedFileURL.path
        guard fileManagerBox.value.fileExists(atPath: targetPath) else {
            return .empty(targetPath: targetPath, exists: false)
        }
        let parsed = try XMPDocumentParser(fileManager: fileManagerBox.value).parseFile(at: targetPath)
        return try XMPMetadataSnapshot.make(targetPath: targetPath, exists: true, parsed: parsed)
    }

    public func preview(_ request: XMPWriteRequest) throws -> XMPWritePreview {
        try validateExecutablePlan(request.plan)
        let snapshot = try readSnapshot(at: request.plan.targetXMPPath)
        try validateScalarPreconditions(in: request, against: snapshot)
        let parsed = try parsedDocumentForWrite(
            targetPath: request.plan.targetXMPPath,
            existed: snapshot.exists,
            includeHierarchicalBag: !request.plan.hierarchicalKeywordsToAdd.isEmpty,
            sourceFileNames: request.plan.sourceMembers.map(\.sourceFileName)
        )
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
            resultingUrgency: resultingSnapshot.urgency
        )
    }

    public func apply(_ request: XMPWriteRequest) throws -> XMPWriteResult {
        try validateExecutablePlan(request.plan)
        let targetURL = URL(fileURLWithPath: request.plan.targetXMPPath).standardizedFileURL
        let targetPath = targetURL.path
        let existed = fileManagerBox.value.fileExists(atPath: targetPath)
        let preSnapshot = try readSnapshot(at: targetPath)
        try validateScalarPreconditions(in: request, against: preSnapshot)

        let parsed = try parsedDocumentForWrite(
            targetPath: targetPath,
            existed: existed,
            includeHierarchicalBag: !request.plan.hierarchicalKeywordsToAdd.isEmpty,
            sourceFileNames: request.plan.sourceMembers.map(\.sourceFileName)
        )
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
                resultingUrgency: preSnapshot.urgency
            )
        }

        let data = try XMPDocumentWriter().data(for: parsed)
        try AtomicFileWriter.writeFile(to: targetURL, fileManager: fileManagerBox.value) { temporaryURL in
            try data.write(to: temporaryURL)
            // FR2-026: validate the sibling temp sidecar before atomic replacement.
            _ = try validateReadable(at: temporaryURL.path)
        }

        let postSnapshot = try readSnapshot(at: targetPath)
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
            resultingUrgency: postSnapshot.urgency
        )
    }

    public func validateReadable(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        let targetPath = URL(fileURLWithPath: targetXMPPath).standardizedFileURL.path
        let parsed = try XMPDocumentParser(fileManager: fileManagerBox.value).parseFile(at: targetPath)
        return try XMPMetadataSnapshot.make(targetPath: targetPath, exists: true, parsed: parsed)
    }

    public func shutdown() throws {}

    private func parsedDocumentForWrite(
        targetPath: String,
        existed: Bool,
        includeHierarchicalBag: Bool,
        sourceFileNames: [String]
    ) throws -> XMPParsedDocument {
        if existed {
            return try XMPDocumentParser(fileManager: fileManagerBox.value).parseFile(
                at: targetPath,
                sourceFileNames: sourceFileNames
            )
        }
        return XMPDocumentWriter().makeNewDocument(
            targetPath: targetPath,
            includeHierarchicalBag: includeHierarchicalBag
        )
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
        return resultingSnapshot
    }

    private func validateScalarPreconditions(
        in request: XMPWriteRequest,
        against snapshot: XMPMetadataSnapshot
    ) throws {
        try validateScalarPrecondition(request.ratingWrite, for: .rating, currentValue: snapshot.rating)
        try validateScalarPrecondition(request.labelWrite, for: .label, currentValue: snapshot.label)
        try validateScalarPrecondition(request.urgencyWrite, for: .urgency, currentValue: snapshot.urgency)
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
