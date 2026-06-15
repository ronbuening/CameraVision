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
        return XMPMetadataSnapshot.make(targetPath: targetPath, exists: true, parsed: parsed)
    }

    public func preview(_ request: XMPWriteRequest) throws -> XMPWritePreview {
        try validateExecutablePlan(request.plan)
        let snapshot = try readSnapshot(at: request.plan.targetXMPPath)
        let outcome = XMPKeywordMerger().preview(plan: request.plan, snapshot: snapshot)
        return XMPWritePreview(
            targetXMPPath: request.plan.targetXMPPath,
            wouldCreate: !snapshot.exists,
            existingFlatKeywords: snapshot.flatKeywords,
            existingHierarchicalKeywords: snapshot.hierarchicalKeywords,
            resultingFlatKeywords: outcome.resultingFlatKeywords,
            resultingHierarchicalKeywords: outcome.resultingHierarchicalKeywords,
            flatKeywordsToAdd: outcome.addedFlatKeywords,
            hierarchicalKeywordsToAdd: outcome.addedHierarchicalKeywords,
            warnings: request.plan.sourceVerificationWarnings + request.plan.groupWarnings
        )
    }

    public func apply(_ request: XMPWriteRequest) throws -> XMPWriteResult {
        try validateExecutablePlan(request.plan)
        let targetURL = URL(fileURLWithPath: request.plan.targetXMPPath).standardizedFileURL
        let targetPath = targetURL.path
        let existed = fileManagerBox.value.fileExists(atPath: targetPath)
        let preSnapshot = try readSnapshot(at: targetPath)

        let parsed = try parsedDocumentForWrite(
            targetPath: targetPath,
            existed: existed,
            includeHierarchicalBag: !request.plan.hierarchicalKeywordsToAdd.isEmpty
        )
        let outcome = try XMPKeywordMerger().merge(plan: request.plan, into: parsed)
        let shouldWrite = !existed || !outcome.addedFlatKeywords.isEmpty || !outcome.addedHierarchicalKeywords.isEmpty

        guard shouldWrite else {
            return XMPWriteResult(
                targetXMPPath: targetPath,
                created: false,
                modified: false,
                preWriteSnapshot: preSnapshot,
                postWriteSnapshot: preSnapshot,
                addedFlatKeywords: [],
                addedHierarchicalKeywords: [],
                warnings: request.plan.sourceVerificationWarnings + request.plan.groupWarnings
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
            warnings: request.plan.sourceVerificationWarnings + request.plan.groupWarnings
        )
    }

    public func validateReadable(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        let targetPath = URL(fileURLWithPath: targetXMPPath).standardizedFileURL.path
        let parsed = try XMPDocumentParser(fileManager: fileManagerBox.value).parseFile(at: targetPath)
        return XMPMetadataSnapshot.make(targetPath: targetPath, exists: true, parsed: parsed)
    }

    public func shutdown() throws {}

    private func parsedDocumentForWrite(
        targetPath: String,
        existed: Bool,
        includeHierarchicalBag: Bool
    ) throws -> XMPParsedDocument {
        if existed {
            return try XMPDocumentParser(fileManager: fileManagerBox.value).parseFile(at: targetPath)
        }
        return XMPDocumentWriter().makeNewDocument(
            targetPath: targetPath,
            includeHierarchicalBag: includeHierarchicalBag
        )
    }

    private func validateExecutablePlan(_ plan: XMPChangePlan) throws {
        guard plan.status == .planned, plan.failures.isEmpty else {
            throw plan.failures.first ?? SidecarError(
                code: .validationFailed,
                stage: .write,
                message: "Cannot execute failed XMP change plan for \(plan.targetXMPPath).",
                recoverable: true
            )
        }
    }
}

private struct SendableFileManager: @unchecked Sendable {
    var value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}
