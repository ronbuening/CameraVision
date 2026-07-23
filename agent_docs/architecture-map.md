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

- **Phase 1** (`analyze`, `assess-quality`): scan → identity hash → render derivatives → optional subject isolation → one factory-selected local vision backend → raw `.ai.json` or `.quality.ai.json` sidecars. Ollama is the current usable backend; the compiled-in Apple FoundationModels descriptor remains unavailable until a public vision-capable API exists. `analyze --assess-quality` selects the combined v1.6.0 contract; `assess-quality` selects the standalone quality-only v1.0.0 contract. With `--quality-scan-mode sequential`, an assess-quality analyze instead runs two passes — the plain v1.5.0 tagging contract, then the quality-only v1.0.0 contract — producing a paired `.ai.json`/`.quality.ai.json` set whose tagging bytes match a no-assessment run (invariant 22). All shapes record `task_profile`, and none write XMP.
- **Phase 2** (`write-xmp`): read raw sidecars → extract accepted candidates → plan/merge/write `.xmp` sidecars through the project-owned XMP engine, with backups and post-write validation. Opt-in quality grading (for example, `--quality-grading`) also derives deterministic grades and plans managed rating, label, urgency, and quality-keyword writes through that same engine path.
- **Phase 3** (`normalize`, `apply-session`): vocabulary canonicalization + batch consensus over tagging candidates → durable session document → normalized XMP writes reusing the Phase 2 export pipeline. Positional normalize scans hash source identities through the bounded async scanner; an absent normalization `stage_concurrency` uses the hardware default only at execution time and remains absent from the session. Analyze-mode `normalize --assess-quality` can create the combined assessment in the same run; opt-in `--quality-grading` delegates to the shared Phase 2 grading applier after normalized keywords are final, and apply-session re-grades from current sidecars/XMP rather than a stored preview.

## Module Map (Sources/AISidecarCore)

| Directory | Owns | Key types |
|---|---|---|
| `Configuration/` | Config models, precedence (CLI > env > file > default), invocation validation, config-file editing; normalization `stage_concurrency` is optional/default-elided and shares the analyze config/env keys | `ConfigurationResolver`, `AppConfig`, `ConfigFileEditor`, `RunConfiguration`/`ResolvedRunConfiguration`, `XMPExportConfiguration`, `NormalizationConfiguration`, `InvocationRules` |
| `FileScanning/` | Folder scan, supported extensions, source records, structured directory-read failures, bounded async source-identity hashing, no-hash inventory scan | `ImageScanner` (`scan(...stageConcurrency:)`; `inventory(inputPath:recursive:)` → `ScanInventory`, CORE-5), `ScanInventoryEntry`, `SourceImage`, `ScanResult` |
| `Identity/` | Source content identity hashing (fast/sha256 policies) | `SourceIdentity` |
| `Rendering/` | Model-input profiles, render recipes, whole-image rendering, cross-process derivative-cache transactions and active-artifact leases | `ImageRenderer`, `DerivativeCache`, `ModelInputProfileRegistry`, `RenderRecipe` |
| `SubjectIsolation/` | Apple Vision foreground masks, instance selection, two-resolution subject crops | `SubjectIsolationService`, `AppleVisionForegroundMaskProvider`, `InstanceSelectionPolicy` |
| `ModelRuntime/` | Backend-neutral runner protocol; deterministic descriptor registry and once-per-run factory selection; backend guidance/model discovery/tuning capabilities; Ollama HTTP runtime; dark, compile-gated Apple FoundationModels adapter; task-aware prompt/schema validation and response repair; mock runners | `VisionModelRunner`, `VisionBackendDescriptor`, `VisionBackendRegistry`, `VisionModelRunnerFactory`, `OllamaBackendDescriptor`/`OllamaVisionRunner`, `AppleFoundationModelsDescriptor`, `ModelTaskProfile`, `PromptRegistry`, `JSONSchemaValidator` |
| `Sidecars/` | Raw `.ai.json`/`.quality.ai.json` naming, schema records, schema-evolution rewrites, atomic writes, export stamps, no-hash queue-state derivation, preview-sidecar interpretation | `RawJSONSidecar`, `RawJSONSidecarWriter/Reader`, `RawJSONSidecarInputResolver`, `AtomicFileWriter`, `SidecarNaming`, `RawSidecarExportStamp` (CORE-4 `xmp_export` block), `QueueStateDeriver`/`QueueDerivedState`, `AssetPreviewLoader`/`AssetPreviewPresentation` |
| `Metadata/` | Phase 2: candidate and quality-assessment extraction, deterministic quality grading shared with normalized planning, read-only review-quality contributor resolution/presentation, shared coordinate/GPS keyword safety, XMP naming/grouping, owned XMP parser/writer engine for managed keyword bags and scalars, backups, merge validation | `CandidateExtractor`, `QualityAssessmentExtractor`, `ReviewQualityLoader`, `ReviewAssetQualityPresentation`, `ReviewQualityLoadResult`, `QualityGradingPolicy`, `QualityTierDeriver`, `QualityGradingPlanApplier`, `KeywordSafetyPolicy`, `MetadataWriteEngine` (protocol), `OwnedXMPSidecarEngine`, `XMPDocumentParser/Writer`, `XMPKeywordReader/Merger`, `XMPScalarReader/Merger`, `XMPManagedScalar`, `XMPMetadataSnapshot`, `XMPUnmanagedContentFingerprint`, `XMPBackupManager`, `XMPChangePlan`, `PlannedScalarWrite`, `SameBaseNameGroupResolver` |
| `Normalization/` | Phase 3: async folder/from-json/file-list input resolution, vocabulary load/index/validate, canonicalization, affinity graph, consensus over tagging candidates, verbatim post-normalization quality-keyword integration, session documents, decision explainer, GUI review application | `NormalizationInputResolver`, `VocabularyLoader/Index/Validator`, `VocabularyTextFolder`, `CandidateCanonicalizer`, `AssetAffinityGraph`, `BatchConsensusEngine`, `NormalizationSessionDocument`, `NormalizedXMPChangePlanner`, `NormalizationDecisionExplainer` (CORE-6), `SessionReview` (CORE-7) |
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
| `AnalyzePipeline` | `run(inputPath:configuration:interruptionMonitor:writesBatchArtifacts:progressHandler:)` | yes | Phase 1 full analyze → `.ai.json`; resolves one task profile for prompt/schema provenance; per-asset `ProgressRecord` callback (CORE-1/2). Standalone callers do not retain decoded written documents. For `taggingWithQuality` + `qualityScanMode == .sequential` it internally orchestrates two passes (tagging, then quality-only), emitting one record per pass per asset, keeping cache clear-on-start before pass 1 / clear-after-success after pass 2, and skipping pass 2 on interruption |
| `QualityAssessPipeline` | `run(inputPath:configuration:interruptionMonitor:progressHandler:)` | yes | Quality-only adapter over `AnalyzePipeline` → `.quality.ai.json`; forces the standalone contract and suppresses GPS/model-input context |
| `XMPExportPipeline` | `runFromJSON(...)` / `runResolvedInputs(...)` | no | Phase 2 export; `writesBatchArtifacts: false` suppresses batch artifact files |
| `NormalizePipeline` | `runSessionOnly(...)` / `runDryRun(...)` / `runWritePlan(...)` | yes | Phase 3 session, dry-run plan, or write plan; mode-based input resolution is async, while `runResolvedInputs(...)` remains synchronous for in-process adapters; when grading is enabled, applies the shared grader after keyword normalization (session-only omits unresolved scalar rows) |
| `NormalizeAndWritePipeline` | `run(...)` | yes | Async normalize → shared export composition, carrying the resolved grading block unchanged |
| `ApplySessionPipeline` | `run(...)` | no | Re-apply stored keyword decisions, no model runs; opt-in grading re-resolves current assessment contributors and current XMP |
| `AnalyzeAndXMPPipeline` | `run(...)` | yes | analyze + write-xmp in one command; opts into the written-document handoff, consumes it without rereading fresh sidecars, then drops the result map before export |
| `AnalyzeAndNormalizePipeline` | `run(...)` | yes | analyze + normalize (+ export) in one command; carries the selected tagging/combined task profile and grading configuration, consumes the opt-in written-document handoff, and drops the result map before normalization |
| `ModelInputExportPipeline` | `run(...)` | yes | Diagnostic only: rendered model inputs + manifest, no sidecars/model calls |

## CLI Layer (Sources/AISidecarCLI)

One file per subcommand (`AnalyzeCommand`, `AssessQualityCommand`, `WriteXMPCommand`, `NormalizeCommand`, `ApplySessionCommand`, `ExplainSessionCommand`, `BenchmarkCommand`, `PurgeCommand`, `CleanupCommand`) plus `SharedOptions` and the shared `QualityGradingOptions`. Analysis-capable shapes accept `--model-backend ollama|apple|auto` (config `model_backend`, env `AISIDECAR_MODEL_BACKEND`): pinned backends fail closed when unavailable, while `auto` resolves one backend for the whole run in registry order (Apple, then Ollama). The default is Ollama; `benchmark` currently rejects non-Ollama selections. `--assess-quality` is available on `analyze`, the analyze-and-write shape of `write-xmp`, and analyze-mode `normalize`; it selects `tagging_with_quality`. The same three commands accept `--quality-scan-mode combined|sequential` (config `quality_scan_mode`, env `AISIDECAR_QUALITY_SCAN_MODE`) to choose the single-call or two-pass shape when assessment is on. `assess-quality` selects `quality_only` and writes `.quality.ai.json`. Normalize resolves `stage_concurrency` as CLI > `AISIDECAR_STAGE_CONCURRENCY` > shared config key > nil; the explicit flag remains invalid with `--from-json`. The identical default-off grading group is composed into `write-xmp`, `normalize`, and `apply-session`; it adds deterministic quality keywords and managed-scalar rows through the shared planner logic. The CLI does argument parsing, invocation-request building, and stdout presentation only — reusable behavior belongs in Core.

## GUI Layer (Sources/CupricAspectApp)

Presentation and state orchestration only (invariant 13); all processing stays in Core. The app has its own `AGENTS.md` in that directory.

| Directory | Owns | Key types |
|---|---|---|
| `App/` | `@main` entry, root shell switcher, root-stable workflow observation | `CupricAspectApp`, `RootShellView` |
| `DesignSystem/` | Design tokens (doc 07 §3), aperture component (§5), shared flow layout and compact quality badges | `Theme`, `ApertureView`, `FlowLayout`, `QualityBadge` |
| `Shells/` | Wizard and Studio presentation chrome; both receive the same root-owned workflow state | `WizardShellView`, `StudioShellView`, `WizardNavigation` |
| `Features/Flow/` | Shell-independent ownership of feature models, wizard state, phase routing, and run/export intents | `WizardFlowModel` |
| `Features/ModelDiscovery/` | Shared backend-and-endpoint-aware discovery of installed vision-capable model choices, including per-backend result isolation, automatic-result reuse, manual refresh, and stale-request suppression | `VisionTagsModel` |
| `Features/Import/` | Folder import, presentation of Core-derived on-disk queue state, grid/list | `FolderImportModel`, `AssetRecord`/`AssetQueueState`, `AssetGridView`, `Step1PhotosView`, `QueueStateDeriver` (Core input) |
| `Features/Run/` | Analysis job engine and backend factory preflight; run-scoped options (including assessment/grading); descriptor-driven model choices, tuning controls, availability identity, and runtime guidance; composable run-option cards and run views | `AnalysisRunModel`, `AnalysisOptions`, `Step2ActionView`, `Step3OptionsView`, `RunModelPickerCard`, `AdvancedOptionsCard`, `QualityGradingOptionsCard`, `RuntimeGuidanceModel` |
| `Features/Preview/` | Thumbnail/ImageIO decoding and presentation of Core-loaded preview facts and derivative paths | `ThumbnailStore`, `RowThumbnail`, `AssetPreviewDetails`, `AssetPreviewSheet`, `AssetPreviewLoader` (Core input) |
| `Features/Review/` | Candidate review, verdicts/edits, autosave/recovery, presentation of Core-loaded read-only quality rows | `ReviewModel`, `Step5ReviewView`, `ReviewQualityPanel`, `ReviewQualityLoader` (Core input) |
| `Features/Normalize/` | Normalization Inspector, session context panel | `NormalizationModel`, `NormalizationInspectorView`, `SessionContextPanel` |
| `Features/Export/` | Change-plan-fronted writes, apply-only grading controls, scalar plan/result presentation | `ExportModel`, `ChangePlanSheet`, `ExportReportView`, `Step3ApplyView` |
| `Features/Settings/` | Settings sheet sections, shared config.json write-through, descriptor-backed backend/availability picker, backend-scoped model picker, quality channel/confidence defaults | `SettingsModel`, `SettingsSheet`, `SettingsControls` |
| `Support/` | File logging (5 MB cap + rotation), state-dir housekeeping, hidden `CUPRIC_*` feature-flag gates | `FileLogSink` (`GUILog.swift`), `StateHousekeeping`, `FeatureFlags` |

GUI model tests live in `Tests/CupricAspectAppTests` (offline, deterministic — same rules as Core tests).

## Artifacts and File Locations

| Artifact | Where |
|---|---|
| Raw AI sidecar | Tagging/combined: `<image>.<ext>.ai.json`; quality-only: `<image>.<ext>.quality.ai.json`; beside the image or mirrored under `--output-dir`; `run_configuration.task_profile` records the model contract, `run_configuration.quality_scan_mode` is recorded only when `sequential` (invariant 22), and `run_configuration.model_backend` is recorded only for a non-default backend and always names the concrete backend the factory resolved (a requested `auto` is stamped to what actually ran, so `"auto"` never appears). Each model run carries backend-native runtime/model/digest provenance. After a successful export (including an unchanged target), the pipeline attempts to update contributing tagging and quality siblings with an additive `xmp_export` stamp containing any actual tool-owned scalar values and the quality tier when graded; stamp failures are warnings after the validated XMP result. |
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
