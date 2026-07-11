import Foundation

/// Canonical filename prefixes for run artifacts.
///
/// The pipelines that create progress logs, reports, summaries, and sessions and the `cleanup`
/// pass that recognizes owned artifacts both reference these constants, so the write side and the
/// recognize side cannot drift out of sync and leave orphaned files behind.
public enum ArtifactNames {
    public static let batchProgressPrefix = "batch-progress-"
    public static let batchSummaryPrefix = "batch-summary-"
    public static let modelInputExportManifestPrefix = "model-input-export-"
    public static let xmpExportProgressPrefix = "xmp-export-progress-"
    public static let xmpExportReportPrefix = "xmp-export-report-"
    public static let xmpExportSummaryPrefix = "xmp-export-summary-"
    public static let normalizationProgressPrefix = "normalization-progress-"
    public static let normalizationReportPrefix = "normalization-report-"
    public static let normalizationSummaryPrefix = "normalization-summary-"
    public static let normalizationSessionPrefix = "normalization-session-"
    public static let normalizationApplyProgressPrefix = "normalization-apply-progress-"
    public static let normalizationApplyReportPrefix = "normalization-apply-report-"
    public static let normalizationApplySummaryPrefix = "normalization-apply-summary-"
    /// Infix of backup-and-merge XMP backups (`<name>.xmp.bak-<token>`, written by
    /// `XMPBackupManager`). Scans ignore them; cleanup never deletes them.
    public static let xmpBackupInfix = ".xmp.bak-"
}
