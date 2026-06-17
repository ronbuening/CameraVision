import Foundation
@testable import AISidecarCore

func phase3LoadedVocabulary(entries: [VocabularyEntry]? = nil) throws -> LoadedVocabulary {
    try VocabularyLoader.load(
        data: vocabularyData(entries: entries ?? phase3VocabularyEntries()),
        sourcePath: "memory://phase3-m10-vocabulary.json"
    )
}

func phase3VocabularyEntries() -> [VocabularyEntry] {
    [
        VocabularyEntry(
            canonicalPath: "Subject",
            flatKeyword: "Subject",
            namespace: .subject,
            parentPath: nil,
            synonyms: [],
            requiresReview: false,
            autoApplyAllowed: false,
            directApplyPolicy: .withhold,
            propagationScope: PropagationScope.none,
            specificity: .broad
        ),
        VocabularyEntry(
            canonicalPath: "Subject|Wildlife",
            flatKeyword: "Wildlife",
            namespace: .subject,
            parentPath: "Subject",
            synonyms: ["wild animal"],
            requiresReview: false,
            autoApplyAllowed: true,
            directApplyPolicy: .allow,
            mutuallyExclusiveGroup: "subject-kind",
            propagationScope: .local,
            specificity: .broad
        ),
        VocabularyEntry(
            canonicalPath: "Subject|Wildlife|Birds",
            flatKeyword: "Birds",
            namespace: .subject,
            parentPath: "Subject|Wildlife",
            synonyms: ["bird", "avian"],
            requiresReview: false,
            autoApplyAllowed: true,
            directApplyPolicy: .allow,
            propagationScope: .local,
            specificity: .broad
        ),
        VocabularyEntry(
            canonicalPath: "Subject|Wildlife|Birds|Herons and Egrets",
            flatKeyword: "Herons and Egrets",
            namespace: .subject,
            parentPath: "Subject|Wildlife|Birds",
            synonyms: ["egret"],
            requiresReview: false,
            autoApplyAllowed: true,
            directApplyPolicy: .allow,
            propagationScope: .local,
            specificity: .mid
        ),
        VocabularyEntry(
            canonicalPath: "Subject|Mammals",
            flatKeyword: "Mammals",
            namespace: .subject,
            parentPath: "Subject",
            synonyms: ["mammal"],
            requiresReview: false,
            autoApplyAllowed: true,
            directApplyPolicy: .allow,
            mutuallyExclusiveGroup: "subject-kind",
            propagationScope: .local,
            specificity: .broad
        ),
        VocabularyEntry(
            canonicalPath: "Subject|Review",
            flatKeyword: "Review",
            namespace: .subject,
            parentPath: "Subject",
            synonyms: ["rare subject"],
            requiresReview: true,
            autoApplyAllowed: false,
            directApplyPolicy: .withhold,
            propagationScope: .local,
            specificity: .broad
        ),
        VocabularyEntry(
            canonicalPath: "Habitat",
            flatKeyword: "Habitat",
            namespace: .habitat,
            parentPath: nil,
            requiresReview: false,
            autoApplyAllowed: false,
            directApplyPolicy: .withhold,
            propagationScope: PropagationScope.none,
            specificity: .broad
        ),
        VocabularyEntry(
            canonicalPath: "Habitat|Wetland",
            flatKeyword: "Wetland",
            namespace: .habitat,
            parentPath: "Habitat",
            synonyms: ["wetland"],
            requiresReview: false,
            autoApplyAllowed: true,
            directApplyPolicy: .allow,
            propagationScope: .local,
            specificity: .mid
        ),
        VocabularyEntry(
            canonicalPath: "Scene",
            flatKeyword: "Scene",
            namespace: .scene,
            parentPath: nil,
            requiresReview: false,
            autoApplyAllowed: false,
            directApplyPolicy: .withhold,
            propagationScope: PropagationScope.none,
            specificity: .broad
        ),
        VocabularyEntry(
            canonicalPath: "Scene|Outdoor",
            flatKeyword: "Outdoor",
            namespace: .scene,
            parentPath: "Scene",
            synonyms: ["outdoors"],
            requiresReview: false,
            autoApplyAllowed: true,
            directApplyPolicy: .allow,
            propagationScope: .global,
            specificity: .broad
        ),
        VocabularyEntry(
            canonicalPath: "Behavior",
            flatKeyword: "Behavior",
            namespace: .behavior,
            parentPath: nil,
            requiresReview: false,
            autoApplyAllowed: false,
            directApplyPolicy: .withhold,
            propagationScope: PropagationScope.none,
            specificity: .broad
        ),
        VocabularyEntry(
            canonicalPath: "Behavior|Flying",
            flatKeyword: "Flying",
            namespace: .behavior,
            parentPath: "Behavior",
            synonyms: ["flight"],
            requiresReview: false,
            autoApplyAllowed: true,
            directApplyPolicy: .allow,
            propagationScope: .local,
            specificity: .mid
        ),
        VocabularyEntry(
            canonicalPath: "Event",
            flatKeyword: "Event",
            namespace: .event,
            parentPath: nil,
            requiresReview: false,
            autoApplyAllowed: false,
            directApplyPolicy: .withhold,
            propagationScope: PropagationScope.none,
            specificity: .broad
        ),
        VocabularyEntry(
            canonicalPath: "Event|Migration",
            flatKeyword: "Migration",
            namespace: .event,
            parentPath: "Event",
            synonyms: ["migration"],
            requiresReview: true,
            autoApplyAllowed: false,
            directApplyPolicy: .userOnly,
            propagationScope: PropagationScope.none,
            specificity: .mid
        )
    ]
}

func phase3Configuration(
    normalizationMode: NormalizationMode = .batchConservative,
    affinityMode: NormalizationAffinityMode = .metadataWeighted
) -> ResolvedNormalizationConfiguration {
    var configuration = ResolvedNormalizationConfiguration.builtInDefaults
    configuration.vocabularyMode = .controlledVocabulary
    configuration.normalizationMode = normalizationMode
    configuration.affinityMode = affinityMode
    configuration.writeFlatKeywords = true
    configuration.writeHierarchicalKeywords = true
    return configuration
}

func phase3InputBatch(_ relativePaths: [String]) -> NormalizationResolvedInputBatch {
    phase3InputBatch(assets: relativePaths.enumerated().map { index, relativePath in
        phase3Asset(index: index + 1, relativePath: relativePath)
    })
}

func phase3InputBatch(
    assets: [NormalizationSourceAsset],
    groups suppliedGroups: [NormalizationSourceGroup]? = nil,
    workflow: NormalizationInputWorkflow = .fileList,
    inputBasePath: String = "/photos"
) -> NormalizationResolvedInputBatch {
    let groups = suppliedGroups ?? assets.enumerated().map { index, asset in
        phase3Group(index: index + 1, assets: [asset])
    }
    return NormalizationResolvedInputBatch(
        workflow: workflow,
        inputPath: "/photos/images.txt",
        inputBasePath: inputBasePath,
        scanRoot: inputBasePath,
        sourceAssets: assets,
        sourceAISidecars: assets.map {
            NormalizationSourceAISidecarRecord(
                sidecarPath: "/sidecars/\($0.sourceRelativePath).ai.json",
                relativePath: "\($0.sourceRelativePath).ai.json",
                sourceAssetID: $0.assetID,
                schemaVersion: "ai-sidecar-json/1.4",
                sourceIdentityStatus: $0.sourceIdentityStatus ?? .matched,
                warnings: []
            )
        },
        sameBaseNameGroups: groups,
        warnings: [],
        failures: []
    )
}

func phase3Asset(
    index: Int,
    relativePath: String,
    fileListIndex: Int? = nil,
    camera: String? = nil,
    lens: String? = nil,
    sameBaseNameGroupID: String? = nil
) -> NormalizationSourceAsset {
    let assetID = String(format: "asset-%06d", index)
    let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
    let fileExtension = URL(fileURLWithPath: fileName).pathExtension
    let source = SourceImage(
        path: "/photos/\(relativePath)",
        relativePath: relativePath,
        fileName: fileName,
        fileExtension: fileExtension,
        fileSize: 1,
        modifiedAt: Date(timeIntervalSince1970: 1_800_010_000 + Double(index)),
        detectedType: SupportedImageType(fileExtension: fileExtension) ?? .jpg,
        identity: SourceIdentity(
            policy: .sha256,
            sha256: AssetAffinityInputBuilder.stableSessionHash(assetID)
        )
    )
    var affinityInputs = AssetAffinityInputBuilder.make(
        assetID: assetID,
        source: source,
        fileListIndex: fileListIndex
    )
    affinityInputs.sameBaseNameGroupID = sameBaseNameGroupID ?? String(format: "group-%06d", index)
    affinityInputs.cameraIdentityClass = camera
    affinityInputs.lensIdentityClass = lens
    return NormalizationSourceAsset(
        assetID: assetID,
        sourcePath: source.path,
        sourceRelativePath: source.relativePath,
        fileName: source.fileName,
        sourceType: source.detectedType,
        sourceIdentity: source.identity,
        sourceSidecarPath: "/sidecars/\(relativePath).ai.json",
        sourceSidecarRelativePath: "\(relativePath).ai.json",
        sourceIdentityStatus: .matched,
        fileListIndex: fileListIndex,
        affinityInputs: affinityInputs
    )
}

func phase3Group(index: Int, assets: [NormalizationSourceAsset]) -> NormalizationSourceGroup {
    let representative = assets[0]
    let directory = representative.affinityInputs.relativeDirectory
    let basename = representative.affinityInputs.filenameStem
    return NormalizationSourceGroup(
        groupID: String(format: "group-%06d", index),
        groupDirectory: directory,
        groupBasename: basename,
        targetRelativePath: directory.isEmpty ? "\(basename).xmp" : "\(directory)/\(basename).xmp",
        memberAssetIDs: assets.map(\.assetID).sorted(),
        selectedAssetIDs: assets.map(\.assetID).sorted(),
        skippedAssetIDs: []
    )
}

func phase3DirectDecision(
    assetID: String,
    canonicalPath: String,
    flatKeyword: String? = nil,
    hierarchicalKeyword: String? = nil,
    stage: NormalizationDecisionStage = .directModelObservation,
    groupID: String? = nil,
    decisionID: String = "",
    observation: CandidateObservation? = nil
) -> PerAssetNormalizationDecision {
    let flat = flatKeyword ?? canonicalPath.split(separator: "|").last.map(String.init)
    return PerAssetNormalizationDecision(
        decisionID: decisionID,
        assetID: assetID,
        groupID: groupID,
        stage: stage,
        status: .accepted,
        candidateKind: .canonicalVocabulary,
        canonicalPath: canonicalPath,
        flatKeyword: flat,
        hierarchicalKeyword: hierarchicalKeyword ?? canonicalPath,
        namespace: .subject,
        directApplyPolicy: .allow,
        requiresReview: false,
        exportFlatKeyword: flat != nil,
        exportHierarchicalKeyword: true,
        supportUnits: 1,
        supportingAssetIDs: [assetID],
        governingRule: stage.rawValue,
        observationCount: observation == nil ? 0 : 1,
        observations: observation.map { [$0] } ?? []
    )
}

func phase3Canonicalization(
    sessionContext: [NormalizationSessionContextRecord] = [],
    decisions: [PerAssetNormalizationDecision]
) -> CandidateCanonicalizationResult {
    CandidateCanonicalizationResult(
        sessionContext: sessionContext,
        observations: decisions.flatMap(\.observations),
        skips: [],
        batchCandidates: [],
        perAssetDecisions: decisions
    )
}

func phase3SessionContext(
    _ type: NormalizationSessionContextType,
    text: String,
    canonicalPath: String,
    propagationAllowed: Bool
) -> NormalizationSessionContextRecord {
    NormalizationSessionContextRecord(
        contextType: type,
        originalText: text,
        foldedText: VocabularyTextFolder.fold(text),
        matchedCanonicalPath: canonicalPath,
        unknownPolicyResult: "matched",
        directApplyPolicy: .allow,
        propagationAllowed: propagationAllowed,
        exportResult: propagationAllowed ? "pending" : "propagation_not_allowed"
    )
}

func phase3Observation(
    id: String,
    assetID: String,
    term: String,
    sourceField: CandidateSourceField = .mainSubjects,
    role: ModelInputRole = .wholeImage
) -> CandidateObservation {
    CandidateObservation(
        observationID: id,
        assetID: assetID,
        groupID: nil,
        term: term,
        normalizedTerm: term,
        foldedTerm: VocabularyTextFolder.fold(term),
        confidence: .high,
        evidence: "fixture evidence",
        provenance: CandidateProvenance(
            sourceField: sourceField,
            inputRole: role,
            sourceSidecar: "/sidecars/\(assetID).ai.json",
            sourceImage: "/photos/\(assetID).JPG",
            modelRunIndex: 0
        )
    )
}
