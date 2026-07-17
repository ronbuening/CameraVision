# Architecture Map

What lives where in `AISidecarCore`, `AISidecarCLI`, and `CupricAspectApp`, and which types are the entry points. Read this before changing code in an unfamiliar module; read the phase requirements docs (see AGENTS.md index) before changing behavior.

## Big Picture

```
images ──► FileScanning ──► Identity ──► Rendering ──► SubjectIsolation ──► ModelRuntime ──► Sidecars (.ai.json)
                                                                                                │
                     Phase 2: Metadata (candidate extraction, owned XMP engine) ◄── raw sidecars┤
                     Phase 3: Normalization (vocabulary, consensus)             ◄───────────────┘
                                                │
                                        Pipeline (orchestration) ──► Reporting (logs/reports/summaries)
```

- **Phase 1** (`analyze`, `assess-quality`): scan → identity hash → render derivatives → optional subject isolation → Ollama vision model → raw `.ai.json` or `.quality.ai.json` sidecars. `analyze --assess-quality` selects the combined v1.6.0 contract; `assess-quality` selects the standalone quality-only v1.0.0 contract. Both record `task_profile`, and neither writes XMP.
- **Phase 2** (`write-xmp`): read raw sidecars → extract accepted candidates → plan/merge/write `.xmp` sidecars through the project-owned XMP engine, with backups and post-write validation. Opt-in quality grading (for example, `--quality-grading`) also derives deterministic grades and plans managed rating, label, urgency, and quality-keyword writes through that same engine path.
- **Phase 3** (`normalize`, `apply-session`): vocabulary canonicalization + batch consensus over candidates → durable session document → normalized XMP writes reusing the Phase 2 export pipeline.

## Module Map (Sources/AISidecarCore)

| Directory | Owns | Key types |
|---|---|---|
| `Configuration/` | Config models, precedence (CLI > env > file > default), invocation validation, config-file editing | `ConfigurationResolver`, `AppConfig`, `ConfigFileEditor`, `RunConfiguration`/`ResolvedRunConfiguration`, `XMPExportConfiguration`, `NormalizationConfiguration`, `InvocationRules` |
| `FileScanning/` | Folder scan, supported extensions, source records, structured directory-read failures, no-hash inventory scan | `ImageScanner` (+ `inventory(inputPath:recursive:)` → `ScanInventory`, CORE-5), `SourceImage`, `ScanResult` |
| `Identity/` | Source content identity hashing (fast/sha256 policies) | `SourceIdentity` |
| `Rendering/` | Model-input profiles, render recipes, whole-image rendering, cross-process derivative-cache transactions and active-artifact leases | `ImageRenderer`, `DerivativeCache`, `ModelInputProfileRegistry`, `RenderRecipe` |
| `SubjectIsolation/` | Apple Vision foreground masks, instance selection, two-resolution subject crops | `SubjectIsolationService`, `AppleVisionForegroundMaskProvider`, `InstanceSelectionPolicy` |
| `ModelRuntime/` | Ollama HTTP client, task-aware prompt/schema registry, schema validation + response repair, mock runners | `OllamaVisionRunner`, `OllamaHTTPTransport`, `VisionModelRunner` (protocol), `ModelTaskProfile`, `PromptRegistry`, `JSONSchemaValidator` |
| `Sidecars/` | Raw `.ai.json`/`.quality.ai.json` naming, schema records, schema-evolution rewrites, atomic writes, export stamps | `RawJSONSidecar`, `RawJSONSidecarWriter/Reader`, `RawJSONSidecarInputResolver`, `AtomicFileWriter`, `SidecarNaming`, `RawSidecarExportStamp` (CORE-4 `xmp_export` block) |
| `Metadata/` | Phase 2: candidate and quality-assessment extraction, deterministic quality grading, shared coordinate/GPS keyword safety, XMP naming/grouping, owned XMP parser/writer engine for managed keyword bags and scalars, backups, merge validation | `CandidateExtractor`, `QualityAssessmentExtractor`, `QualityGradingPolicy`, `QualityTierDeriver`, `KeywordSafetyPolicy`, `MetadataWriteEngine` (protocol), `OwnedXMPSidecarEngine`, `XMPDocumentParser/Writer`, `XMPKeywordReader/Merger`, `XMPScalarReader/Merger`, `XMPManagedScalar`, `XMPMetadataSnapshot`, `XMPUnmanagedContentFingerprint`, `XMPBackupManager`, `XMPChangePlan`, `PlannedScalarWrite`, `SameBaseNameGroupResolver` |
| `Normalization/` | Phase 3: vocabulary load/index/validate, canonicalization, affinity graph, consensus, session documents, decision explainer, GUI review application | `VocabularyLoader/Index/Validator`, `VocabularyTextFolder`, `CandidateCanonicalizer`, `AssetAffinityGraph`, `BatchConsensusEngine`, `NormalizationSessionDocument`, `NormalizedXMPChangePlanner`, `NormalizationDecisionExplainer` (CORE-6), `SessionReview` (CORE-7) |
| `Pipeline/` | Orchestration of everything above + interruption handling | see entry-point table below |
| `Reporting/` | Injectable logger, JSONL progress logs, reports, summaries, schema identifiers, shared owned-artifact prefixes | `Logger` (injectable sink), `ProgressLog`, `JSONLWriter`, `BatchSummary`, `XMPExportReport`, `NormalizationReport`, `ArtifactNames` |
| `Cleanup/` | Scoped removal of owned raw sidecars and run artifacts | `ArtifactCleanup` |
| `Benchmarking/` | Milestone 9a benchmark harness | `Milestone9BenchmarkRunner` |
| `Errors/` | Project-wide structured error codes (additive only, stable raw strings) | `SidecarError` |
| `Support/` | Shared JSON encoder/decoder factories and unknown-field merge, cross-process file locking, timestamps, relocation-safe resource locator, product version | `JSONCoding`, `JSONDocumentMerge`, `FileLock`, `Timestamp`, `AISidecarResourceBundle`, `AISidecarVersion` |
| `Resources/` | Bundled prompts, response schemas, JSON schemas, default vocabulary (~5.8 MB) | loaded via `AISidecarResourceBundle.current` (search order: app `Contents/Resources` → executable-adjacent → `../Resources` → `Bundle.module`; invariant 18) |

## Pipeline Entry Points

All results are `Sendable`; no `@MainActor` coupling; Core never prints directly (the `Logger` sink is injectable, default stderr). Cancellation: pass an `InterruptionMonitor` and call `requestInterruption()`; pipelines check it between assets, while `AnalyzePipeline` also checks between model roles/retries and cancels its in-flight model request. Parent-task cancellation follows the same fail-closed path: the transport passes cancellation through, the model run records `E_INTERRUPTED`, and no failure sidecar is written.

| Pipeline | Entry | Async | Purpose |
|---|---|---|---|
| `AnalyzePipeline` | `run(inputPath:configuration:interruptionMonitor:writesBatchArtifacts:progressHandler:)` | yes | Phase 1 full analyze → `.ai.json`; resolves one task profile for prompt/schema provenance; per-asset `ProgressRecord` callback (CORE-1/2) |
| `QualityAssessPipeline` | `run(inputPath:configuration:interruptionMonitor:progressHandler:)` | yes | Quality-only adapter over `AnalyzePipeline` → `.quality.ai.json`; forces the standalone contract and suppresses GPS/model-input context |
| `XMPExportPipeline` | `runFromJSON(...)` / `runResolvedInputs(...)` | no | Phase 2 export; `writesBatchArtifacts: false` suppresses batch artifact files |
| `NormalizePipeline` | `runSessionOnly(...)` / `runDryRun(...)` / `runWritePlan(...)` | no | Phase 3 session, dry-run plan, or write plan |
| `NormalizeAndWritePipeline` | `run(...)` | no | Normalize → export composition |
| `ApplySessionPipeline` | `run(...)` | no | Re-apply a stored session, no model runs |
| `AnalyzeAndXMPPipeline` | `run(...)` | yes | analyze + write-xmp in one command |
| `AnalyzeAndNormalizePipeline` | `run(...)` | yes | analyze + normalize (+ export) in one command |
| `ModelInputExportPipeline` | `run(...)` | yes | Diagnostic only: rendered model inputs + manifest, no sidecars/model calls |
| `AnalyzeShellPipeline` | — | — | Legacy pre-model test seam, test-only call sites; audit before touching (see efficiency plan R4) |

## CLI Layer (Sources/AISidecarCLI)

One file per subcommand (`AnalyzeCommand`, `AssessQualityCommand`, `WriteXMPCommand`, `NormalizeCommand`, `ApplySessionCommand`, `ExplainSessionCommand`, `BenchmarkCommand`, `PurgeCommand`, `CleanupCommand`) plus `SharedOptions`. `--assess-quality` is available on `analyze` and the analyze-and-write shape of `write-xmp`; it selects `tagging_with_quality`. `assess-quality` selects `quality_only` and writes `.quality.ai.json`. `write-xmp --quality-grading` is the separate, default-off export switch that grades stored assessments and adds managed-scalar rows to the existing XMP plan/write path. The CLI does argument parsing, invocation-request building, and stdout presentation only — reusable behavior belongs in Core.

## GUI Layer (Sources/CupricAspectApp)

Presentation and state orchestration only (invariant 13); all processing stays in Core. The app has its own `AGENTS.md` in that directory.

| Directory | Owns | Key types |
|---|---|---|
| `App/` | `@main` entry, root shell switcher | `CupricAspectApp`, `RootShellView` |
| `DesignSystem/` | Design tokens (doc 07 §3), aperture component (§5) | `Theme`, `ApertureView` |
| `Shells/` | Wizard chrome (step rail, footer nav); Studio chrome is M9 | `WizardShellView`, `StudioShellView` |
| `Features/Import/` | Folder import, sidecar-derived asset queue, grid/list | `FolderImportModel`, `AssetQueue`, `AssetGridView`, `Step1PhotosView` |
| `Features/Run/` | Analysis job engine, options, run views, runtime guidance | `AnalysisRunModel`, `RuntimeGuidanceModel`, `WizardAction`, Steps 2–5 views |
| `Features/Preview/` | Thumbnails, asset preview with subject derivative | `ThumbnailStore`, `AssetPreviewDetails`, `AssetPreviewSheet` |
| `Features/Review/` | Candidate review, verdicts/edits, autosave/recovery | `ReviewModel`, `Step5ReviewView` |
| `Features/Normalize/` | Normalization Inspector, session context panel | `NormalizationModel`, `NormalizationInspectorView`, `SessionContextPanel` |
| `Features/Export/` | Change-plan-fronted writes, export reports | `ExportModel`, `ChangePlanSheet`, `Step3ApplyView` |
| `Features/Settings/` | Settings sheet, config.json write-through, model picker | `SettingsModel`, `SettingsSheet` |
| `Support/` | File logging (5 MB cap + rotation), state-dir housekeeping, hidden `CUPRIC_*` feature-flag gates | `FileLogSink` (`GUILog.swift`), `StateHousekeeping`, `FeatureFlags` |

GUI model tests live in `Tests/CupricAspectAppTests` (offline, deterministic — same rules as Core tests).

## Artifacts and File Locations

| Artifact | Where |
|---|---|
| Raw AI sidecar | Tagging/combined: `<image>.<ext>.ai.json`; quality-only: `<image>.<ext>.quality.ai.json`; beside the image or mirrored under `--output-dir`; `run_configuration.task_profile` records the model contract. After a successful export (including an unchanged target), the pipeline attempts to update contributing tagging and quality siblings with an additive `xmp_export` stamp containing any actual tool-owned scalar values and the quality tier when graded; stamp failures are warnings after the validated XMP result. |
| XMP sidecar | Owned parser/writer output, target naming in `Metadata/XMPNaming.swift`; managed fields are the `dc:subject` and `lr:hierarchicalSubject` bags plus opt-in `xmp:Rating`, `xmp:Label`, label-coupled `photoshop:Urgency`, and the coupled Lightroom `xmpDM:pick`/`xmpDM:good` flag-pair scalars. |
| XMP dry-run plan / export report | `ai-sidecar-xmp-change-plan/1.2` / `ai-sidecar-xmp-export/1.2`; scalar plan rows, derived tier, and quality explanation are additive and appear only when grading is enabled. |
| Progress log / report / summary | `*-progress-*.jsonl` / `*-report-*.json` / `*-summary-*.md` (names in `Reporting/ArtifactNames.swift`) |
| Normalization session | `normalization-session-*.json`, reusable by `apply-session` |
| Model-input export manifest | `model-input-export-*.json`, protected diagnostic manifest |
| Derivative cache | `~/Library/Caches/aisidecar/derivatives` (configurable), write-through manifest JSON + persistent flock file + leased artifact inodes; `aisidecar purge` skips active leases |
| Config file | `~/Library/Application Support/aisidecar/config.json` (configurable; the GUI Settings sheet writes through to the same file via `ConfigFileEditor`) |
| GUI state | `~/Library/Application Support/CupricAspect/` — recovery session, per-run artifact dirs (pruned after 7 days by `StateHousekeeping`), `logs/` diagnostic log |
| Packaged app | `dist/CupricAspect.app` from `Scripts/build-release.sh` — GUI at `Contents/MacOS`, CLI at `Contents/Helpers/aisidecar`, ONE shared resource bundle in `Contents/Resources` |

Derivative-cache ownership is shared by the CLI and GUI. Expensive encode/hash work is staged outside the manifest flock; final rename, manifest mutation, LRU accounting, and purge decisions use the persistent cache lock. `cachedRecord`/`store` return leased artifacts, and every pipeline that consumes them must release each record plus run a final `releaseRetained()` teardown so the configured byte cap can be restored.
