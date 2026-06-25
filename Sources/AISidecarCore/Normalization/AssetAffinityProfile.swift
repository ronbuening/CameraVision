import Foundation

/// Resolved metadata-affinity thresholds and decay parameters for a named profile.
public struct AssetAffinityProfile: Sendable, Equatable {
    public var name: NormalizationAffinityProfile
    public var timeWeight: Double
    public var gpsWeight: Double
    public var filenameWeight: Double
    public var timeHalfLifeSeconds: Double
    public var timeCutoffSeconds: Double
    public var gpsHalfDistanceMeters: Double
    public var gpsCutoffMeters: Double
    public var filenameHalfGap: Double
    public var filenameCutoff: Double
    public var gearBoostMax: Double
    public var minAffinityForConsensus: Double
    public var minAffinityToStoreEdge: Double
    public var maxNeighborsPerAsset: Int
    public var globalConsensusThreshold: Double
    public var globalMinEligibleAssets: Int
    public var globalMinSupportingAssets: Int

    public static func resolved(
        name: NormalizationAffinityProfile,
        minAffinityForConsensus override: Double?
    ) -> AssetAffinityProfile {
        var profile: AssetAffinityProfile
        switch name {
        case .conservative:
            profile = AssetAffinityProfile(
                name: name,
                timeWeight: 0.45,
                gpsWeight: 0.35,
                filenameWeight: 0.20,
                timeHalfLifeSeconds: 120,
                timeCutoffSeconds: 1_800,
                gpsHalfDistanceMeters: 25,
                gpsCutoffMeters: 250,
                filenameHalfGap: 5,
                filenameCutoff: 30,
                gearBoostMax: 0.20,
                minAffinityForConsensus: 0.35,
                minAffinityToStoreEdge: 0.15,
                maxNeighborsPerAsset: 30,
                globalConsensusThreshold: 0.80,
                globalMinEligibleAssets: 5,
                globalMinSupportingAssets: 3
            )
        case .balanced:
            profile = AssetAffinityProfile(
                name: name,
                timeWeight: 0.45,
                gpsWeight: 0.35,
                filenameWeight: 0.20,
                timeHalfLifeSeconds: 300,
                timeCutoffSeconds: 7_200,
                gpsHalfDistanceMeters: 75,
                gpsCutoffMeters: 1_000,
                filenameHalfGap: 10,
                filenameCutoff: 100,
                gearBoostMax: 0.30,
                minAffinityForConsensus: 0.25,
                minAffinityToStoreEdge: 0.10,
                maxNeighborsPerAsset: 50,
                globalConsensusThreshold: 0.75,
                globalMinEligibleAssets: 4,
                globalMinSupportingAssets: 3
            )
        case .aggressive:
            profile = AssetAffinityProfile(
                name: name,
                timeWeight: 0.45,
                gpsWeight: 0.35,
                filenameWeight: 0.20,
                timeHalfLifeSeconds: 900,
                timeCutoffSeconds: 21_600,
                gpsHalfDistanceMeters: 200,
                gpsCutoffMeters: 3_000,
                filenameHalfGap: 25,
                filenameCutoff: 250,
                gearBoostMax: 0.40,
                minAffinityForConsensus: 0.15,
                minAffinityToStoreEdge: 0.05,
                maxNeighborsPerAsset: 100,
                globalConsensusThreshold: 0.70,
                globalMinEligibleAssets: 3,
                globalMinSupportingAssets: 2
            )
        }

        if let override {
            profile.minAffinityForConsensus = override
            profile.minAffinityToStoreEdge = min(profile.minAffinityToStoreEdge, override)
        }
        return profile
    }
}

/// Shared deterministic decay function for affinity components.
public enum AffinityDecay {
    public static func score(value: Double?, halfLife: Double, cutoff: Double) -> Double? {
        guard let value else {
            return nil
        }
        guard value <= cutoff else {
            return 0
        }
        return pow(0.5, value / halfLife)
    }
}
