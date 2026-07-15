import Foundation

/// Component-level affinity facts persisted without raw sensitive metadata.
public struct AssetAffinityComponentScoreRecord: Codable, Sendable, Equatable {
    public var timeScore: Double?
    public var gpsScore: Double?
    public var filenameScore: Double?
    public var fileListAdjacencyScore: Double?
    public var gearScore: Double
    public var primaryAvailableWeight: Double
    public var primaryEvidenceCount: Int
    public var basisSignals: [String]
    public var gearOnly: Bool

    enum CodingKeys: String, CodingKey {
        case timeScore = "time_score"
        case gpsScore = "gps_score"
        case filenameScore = "filename_score"
        case fileListAdjacencyScore = "file_list_adjacency_score"
        case gearScore = "gear_score"
        case primaryAvailableWeight = "primary_available_weight"
        case primaryEvidenceCount = "primary_evidence_count"
        case basisSignals = "basis_signals"
        case gearOnly = "gear_only"
    }

    public init(
        timeScore: Double? = nil,
        gpsScore: Double? = nil,
        filenameScore: Double? = nil,
        fileListAdjacencyScore: Double? = nil,
        gearScore: Double,
        primaryAvailableWeight: Double,
        primaryEvidenceCount: Int,
        basisSignals: [String],
        gearOnly: Bool
    ) {
        self.timeScore = timeScore
        self.gpsScore = gpsScore
        self.filenameScore = filenameScore
        self.fileListAdjacencyScore = fileListAdjacencyScore
        self.gearScore = gearScore
        self.primaryAvailableWeight = primaryAvailableWeight
        self.primaryEvidenceCount = primaryEvidenceCount
        self.basisSignals = basisSignals
        self.gearOnly = gearOnly
    }
}

/// Stored edge between two normalization nodes.
public struct AssetAffinityEdgeRecord: Codable, Sendable, Equatable, Hashable {
    public var fromNodeID: String
    public var toNodeID: String
    public var affinity: Double
    public var scoreBand: String
    public var components: AssetAffinityComponentScoreRecord

    enum CodingKeys: String, CodingKey {
        case fromNodeID = "from_node_id"
        case toNodeID = "to_node_id"
        case affinity
        case scoreBand = "score_band"
        case components
    }

    public init(
        fromNodeID: String,
        toNodeID: String,
        affinity: Double,
        scoreBand: String,
        components: AssetAffinityComponentScoreRecord
    ) {
        self.fromNodeID = fromNodeID
        self.toNodeID = toNodeID
        self.affinity = affinity
        self.scoreBand = scoreBand
        self.components = components
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fromNodeID)
        hasher.combine(toNodeID)
    }

    public static func == (lhs: AssetAffinityEdgeRecord, rhs: AssetAffinityEdgeRecord) -> Bool {
        lhs.fromNodeID == rhs.fromNodeID
            && lhs.toNodeID == rhs.toNodeID
            && lhs.affinity == rhs.affinity
            && lhs.scoreBand == rhs.scoreBand
            && lhs.components == rhs.components
    }
}

/// Explanatory local cluster record for session/report audit.
public struct NormalizationClusterRecord: Codable, Sendable, Equatable {
    public var clusterID: String
    public var memberNodeIDs: [String]
    public var basis: String

    enum CodingKeys: String, CodingKey {
        case clusterID = "cluster_id"
        case memberNodeIDs = "member_node_ids"
        case basis
    }

    public init(clusterID: String, memberNodeIDs: [String], basis: String) {
        self.clusterID = clusterID
        self.memberNodeIDs = memberNodeIDs
        self.basis = basis
    }
}

/// Complete graph result used by consensus code and persisted sessions.
public struct AssetAffinityGraph: Sendable, Equatable {
    public var nodes: [NormalizationAffinityNodeRecord]
    public var edges: [AssetAffinityEdgeRecord]
    public var clusters: [NormalizationClusterRecord]
    public var nodeIDByAssetID: [String: String]

    public init(
        nodes: [NormalizationAffinityNodeRecord],
        edges: [AssetAffinityEdgeRecord],
        clusters: [NormalizationClusterRecord],
        nodeIDByAssetID: [String: String]
    ) {
        self.nodes = nodes
        self.edges = edges
        self.clusters = clusters
        self.nodeIDByAssetID = nodeIDByAssetID
    }

    public func neighbors(of nodeID: String, minimumAffinity: Double) -> [(nodeID: String, affinity: Double)] {
        edges.compactMap { edge in
            guard edge.affinity >= minimumAffinity else {
                return nil
            }
            if edge.fromNodeID == nodeID {
                return (edge.toNodeID, edge.affinity)
            }
            if edge.toNodeID == nodeID {
                return (edge.fromNodeID, edge.affinity)
            }
            return nil
        }
    }
}

/// Deterministic graph builder for Phase 3 metadata affinity.
public struct AssetAffinityGraphBuilder {
    public init() {}

    public func build(
        input: NormalizationResolvedInputBatch,
        profile: AssetAffinityProfile,
        mode: NormalizationAffinityMode
    ) -> AssetAffinityGraph {
        let nodes = input.sameBaseNameGroups.map {
            NormalizationAffinityNodeRecord(
                nodeID: $0.groupID,
                groupID: $0.groupID,
                memberAssetIDs: $0.memberAssetIDs.sorted()
            )
        }.sorted { $0.nodeID < $1.nodeID }
        let nodeIDByAssetID = Dictionary(
            uniqueKeysWithValues: nodes.flatMap { node in
                node.memberAssetIDs.map { ($0, node.nodeID) }
            }
        )
        guard mode == .metadataWeighted else {
            return AssetAffinityGraph(nodes: nodes, edges: [], clusters: [], nodeIDByAssetID: nodeIDByAssetID)
        }

        let assetByID = Dictionary(uniqueKeysWithValues: input.sourceAssets.map { ($0.assetID, $0) })
        let scoringNodes = nodes.compactMap { node -> ScoringNode? in
            guard let representativeID = node.memberAssetIDs.min(),
                let asset = assetByID[representativeID]
            else {
                return nil
            }
            return ScoringNode(node: node, inputs: asset.affinityInputs)
        }
        let pairs = CandidateNeighborGenerator().candidatePairs(nodes: scoringNodes, profile: profile)
        var scoredEdges = pairs.compactMap { pair -> AssetAffinityEdgeRecord? in
            let edge = score(lhs: pair.0, rhs: pair.1, profile: profile)
            guard edge.affinity >= profile.minAffinityToStoreEdge else {
                return nil
            }
            return edge
        }

        scoredEdges = prune(edges: scoredEdges, maxNeighborsPerNode: profile.maxNeighborsPerAsset)
        scoredEdges.sort(by: compareEdges)
        return AssetAffinityGraph(
            nodes: nodes,
            edges: scoredEdges,
            clusters: clusters(from: scoredEdges),
            nodeIDByAssetID: nodeIDByAssetID
        )
    }

    private func score(
        lhs: ScoringNode,
        rhs: ScoringNode,
        profile: AssetAffinityProfile
    ) -> AssetAffinityEdgeRecord {
        let filename = FilenameSequenceAffinityScorer.score(lhs: lhs.inputs, rhs: rhs.inputs, profile: profile)
        let filenameScore = filename.basis == "filename_sequence" ? filename.score : nil
        let listScore = filename.basis == "explicit_file_list_adjacency" ? filename.score : nil
        let gearScore = CameraLensAffinityScorer.score(lhs: lhs.inputs, rhs: rhs.inputs)

        var weighted = 0.0
        var availableWeight = 0.0
        var primaryEvidenceCount = 0
        var basisSignals: [String] = []
        if let filenameScore = filename.score {
            weighted += profile.filenameWeight * filenameScore
            availableWeight += profile.filenameWeight
            primaryEvidenceCount += 1
            if let basis = filename.basis {
                basisSignals.append(basis)
            }
        }

        var primaryScore = availableWeight == 0 ? 0 : weighted / availableWeight
        if primaryEvidenceCount == 1, filename.score != nil {
            primaryScore = min(primaryScore, 0.70)
        }
        let gearOnly = primaryEvidenceCount == 0 && gearScore > 0
        let affinity = gearOnly ? 0 : min(1.0, primaryScore * (1.0 + profile.gearBoostMax * gearScore))
        let roundedAffinity = AffinityScoreFormatter.rounded(affinity)
        let components = AssetAffinityComponentScoreRecord(
            filenameScore: filenameScore.map(AffinityScoreFormatter.rounded),
            fileListAdjacencyScore: listScore.map(AffinityScoreFormatter.rounded),
            gearScore: AffinityScoreFormatter.rounded(gearScore),
            primaryAvailableWeight: AffinityScoreFormatter.rounded(availableWeight),
            primaryEvidenceCount: primaryEvidenceCount,
            basisSignals: basisSignals.sorted(),
            gearOnly: gearOnly
        )

        let ordered = [lhs.node.nodeID, rhs.node.nodeID].sorted()
        return AssetAffinityEdgeRecord(
            fromNodeID: ordered[0],
            toNodeID: ordered[1],
            affinity: roundedAffinity,
            scoreBand: AffinityScoreFormatter.band(for: roundedAffinity),
            components: components
        )
    }

    private func prune(
        edges: [AssetAffinityEdgeRecord],
        maxNeighborsPerNode: Int
    ) -> [AssetAffinityEdgeRecord] {
        // Index edges by each incident node once (O(edges)) instead of re-filtering the whole edge
        // list per node (O(nodes x edges)). The retained set is identical; the caller re-sorts the
        // pruned edges, so the unordered return order is unchanged in effect.
        var incidentEdges: [String: [AssetAffinityEdgeRecord]] = [:]
        for edge in edges {
            incidentEdges[edge.fromNodeID, default: []].append(edge)
            incidentEdges[edge.toNodeID, default: []].append(edge)
        }
        var keep = Set<AssetAffinityEdgeRecord>()
        for (nodeID, incident) in incidentEdges {
            let retained =
                incident
                .sorted { lhs, rhs in
                    if lhs.affinity == rhs.affinity {
                        return otherNodeID(lhs, nodeID: nodeID) < otherNodeID(rhs, nodeID: nodeID)
                    }
                    return lhs.affinity > rhs.affinity
                }
                .prefix(maxNeighborsPerNode)
            keep.formUnion(retained)
        }
        return Array(keep)
    }

    private func clusters(from edges: [AssetAffinityEdgeRecord]) -> [NormalizationClusterRecord] {
        let strongEdges = edges.filter { $0.affinity >= 0.55 }
        guard !strongEdges.isEmpty else {
            return []
        }
        let nodeIDs = Set(strongEdges.flatMap { [$0.fromNodeID, $0.toNodeID] }).sorted()
        return [
            NormalizationClusterRecord(
                clusterID: "cluster-000001",
                memberNodeIDs: nodeIDs,
                basis: "strong_or_better_affinity_edges"
            )
        ]
    }
}

/// Candidate pair generation before scoring, bounded for large batches.
public struct CandidateNeighborGenerator {
    public static let allPairsThreshold = 500

    public init() {}

    public func candidatePairs(
        nodes: [ScoringNode],
        profile: AssetAffinityProfile
    ) -> [(ScoringNode, ScoringNode)] {
        let sorted = nodes.sorted { $0.node.nodeID < $1.node.nodeID }
        if sorted.count <= Self.allPairsThreshold {
            return allPairs(sorted)
        }

        var pairs = Set<ScoringPair>()
        for (index, lhs) in sorted.enumerated() {
            for rhs in sorted.dropFirst(index + 1) {
                if shouldConsider(lhs: lhs, rhs: rhs, profile: profile) {
                    pairs.insert(ScoringPair(lhs: lhs, rhs: rhs))
                }
            }
        }
        // Index nodes by ID so pair reconstruction is O(1) per pair instead of a linear scan of
        // `sorted`. The emitted order is unchanged: pairs are still returned in `ScoringPair` sort
        // order.
        let nodesByID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.node.nodeID, $0) })
        return pairs.sorted().compactMap { pair in
            guard let lhs = nodesByID[pair.lhsNodeID],
                let rhs = nodesByID[pair.rhsNodeID]
            else {
                return nil
            }
            return (lhs, rhs)
        }
    }

    private func allPairs(_ nodes: [ScoringNode]) -> [(ScoringNode, ScoringNode)] {
        var pairs: [(ScoringNode, ScoringNode)] = []
        for (index, lhs) in nodes.enumerated() {
            for rhs in nodes.dropFirst(index + 1) {
                pairs.append((lhs, rhs))
            }
        }
        return pairs
    }

    private func shouldConsider(
        lhs: ScoringNode,
        rhs: ScoringNode,
        profile: AssetAffinityProfile
    ) -> Bool {
        if let lhsSequence = lhs.inputs.parsedSequenceNumber,
            let rhsSequence = rhs.inputs.parsedSequenceNumber,
            lhs.inputs.relativeDirectory == rhs.inputs.relativeDirectory,
            abs(lhsSequence - rhsSequence) <= Int(profile.filenameCutoff)
        {
            return true
        }
        if let lhsIndex = lhs.inputs.fileListIndex,
            let rhsIndex = rhs.inputs.fileListIndex,
            abs(lhsIndex - rhsIndex) <= Int(profile.filenameCutoff)
        {
            return true
        }
        return false
    }
}

public struct ScoringNode: Sendable, Equatable {
    public var node: NormalizationAffinityNodeRecord
    public var inputs: AssetAffinityInputs

    public init(node: NormalizationAffinityNodeRecord, inputs: AssetAffinityInputs) {
        self.node = node
        self.inputs = inputs
    }
}

private struct ScoringPair: Hashable, Comparable {
    var lhsNodeID: String
    var rhsNodeID: String

    init(lhs: ScoringNode, rhs: ScoringNode) {
        let ordered = [lhs.node.nodeID, rhs.node.nodeID].sorted()
        self.lhsNodeID = ordered[0]
        self.rhsNodeID = ordered[1]
    }

    static func < (lhs: ScoringPair, rhs: ScoringPair) -> Bool {
        if lhs.lhsNodeID == rhs.lhsNodeID {
            return lhs.rhsNodeID < rhs.rhsNodeID
        }
        return lhs.lhsNodeID < rhs.lhsNodeID
    }
}

private func compareEdges(_ lhs: AssetAffinityEdgeRecord, _ rhs: AssetAffinityEdgeRecord) -> Bool {
    if lhs.fromNodeID == rhs.fromNodeID {
        if lhs.affinity == rhs.affinity {
            return lhs.toNodeID < rhs.toNodeID
        }
        return lhs.affinity > rhs.affinity
    }
    return lhs.fromNodeID < rhs.fromNodeID
}

private func otherNodeID(_ edge: AssetAffinityEdgeRecord, nodeID: String) -> String {
    edge.fromNodeID == nodeID ? edge.toNodeID : edge.fromNodeID
}
