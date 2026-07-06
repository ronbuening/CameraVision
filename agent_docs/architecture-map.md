# Architecture Map

What lives where in `AISidecarCore` and `AISidecarCLI`, and which types are the entry points. Read this before changing code in an unfamiliar module; read the phase requirements docs (see AGENTS.md index) before changing behavior.

## Big Picture

```
images ──► FileScanning ──► Identity ──► Rendering ──► SubjectIsolation ──► ModelRuntime ──► Sidecars (.ai.json)
                                                                                                │
                     Phase 2: Metadata (candidate extraction, owned XMP engine) ◄── raw sidecars┤
                     Phase 3: Normalization (vocabulary, consensus)             ◄───────────────┘
                                                │
                                        Pipeline (orchestration) ──► Reporting (logs/reports/summaries)
```

- **Phase 1** (`analyze`): scan → identity hash → render derivatives → optional subject isolation → Ollama vision model → raw `.ai.json` sidecars. Never writes XMP.
- **Phase 2** (`write-xmp`): read raw sidecars → extract accepted candidates → plan/merge/write `.xmp` sidecars through the project-owned XMP engine, with backups and post-write validation.
- **Phase 3** (`normalize`, `apply-session`): vocabulary canonicalization + batch consensus over candidates → durable session document → normalized XMP writes reusing the Phase 2 export pipeline.

## Module Map (Sources/AISidecarCore)

| Directory | Owns | Key types |
|---|---|---|
| `Configuration/` | Config models, precedence (CLI > env > file > default), invocation validation | `ConfigurationResolver`, `RunConfiguration`/`ResolvedRunConfiguration`, `XMPExportConfiguration`, `NormalizationConfiguration`, `InvocationRules` |
| `FileScanning/` | Folder scan, supported extensions, source records | `ImageScanner`, `SourceImage`, `ScanResult` |
| `Identity/` | Source content identity hashing (fast/sha256 policies) | `SourceIdentity` |
| `Rendering/` | Model-input profiles, render recipes, whole-image rendering, derivative cache | `ImageRenderer`, `DerivativeCache`, `ModelInputProfileRegistry`, `RenderRecipe` |
| `SubjectIsolation/` | Apple Vision foreground masks, instance selection, two-resolution subject crops | `SubjectIsolationService`, `AppleVisionForegroundMaskProvider`, `InstanceSelectionPolicy` |
| `ModelRuntime/` | Ollama HTTP client, prompt/schema registry, schema validation + response repair, mock runners | `OllamaVisionRunner`, `OllamaHTTPTransport`, `VisionModelRunner` (protocol), `PromptRegistry`, `JSONSchemaValidator` |
| `Sidecars/` | Raw `.ai.json` naming, schema records, schema-evolution rewrites, atomic writes | `RawJSONSidecar`, `RawJSONSidecarWriter/Reader`, `RawJSONSidecarInputResolver`, `AtomicFileWriter`, `SidecarNaming` |
| `Metadata/` | Phase 2: candidate extraction, keyword policy, XMP naming/grouping, owned XMP parser/writer engine, backups, merge validation | `CandidateExtractor`, `MetadataWriteEngine` (protocol), `OwnedXMPSidecarEngine`, `XMPDocumentParser/Writer`, `XMPKeywordReader/Merger`, `XMPMetadataSnapshot`, `XMPUnmanagedContentFingerprint`, `XMPBackupManager`, `XMPChangePlan`, `SameBaseNameGroupResolver` |
| `Normalization/` | Phase 3: vocabulary load/index/validate, canonicalization, affinity graph, consensus, session documents | `VocabularyLoader/Index/Validator`, `VocabularyTextFolder`, `CandidateCanonicalizer`, `AssetAffinityGraph`, `BatchConsensusEngine`, `NormalizationSessionDocument`, `NormalizedXMPChangePlanner` |
| `Pipeline/` | Orchestration of everything above + interruption handling | see entry-point table below |
| `Reporting/` | Injectable logger, JSONL progress logs, reports, summaries, schema identifiers | `Logger` (injectable sink), `ProgressLog`, `JSONLWriter`, `BatchSummary`, `XMPExportReport`, `NormalizationReport`, `ArtifactNames` |
| `Cleanup/` | Scoped removal of owned raw sidecars and run artifacts | `ArtifactCleanup` |
| `Benchmarking/` | Milestone 9a benchmark harness | `Milestone9BenchmarkRunner` |
| `Errors/` | Project-wide structured error codes (additive only, stable raw strings) | `SidecarError` |
| `Support/` | Shared JSON encoder/decoder factories, timestamps | `JSONCoding`, `Timestamp` |
| `Resources/` | Bundled prompts, response schemas, JSON schemas, default vocabulary (~5.8 MB), loaded via `Bundle.module` | — |

## Pipeline Entry Points

All results are `Sendable`; no `@MainActor` coupling; Core never prints directly (the `Logger` sink is injectable, default stderr). Cancellation: pass an `InterruptionMonitor` and call `requestInterruption()`; pipelines check it between assets.

| Pipeline | Entry | Async | Purpose |
|---|---|---|---|
| `AnalyzePipeline` | `run(inputPath:configuration:interruptionMonitor:)` | yes | Phase 1 full analyze → `.ai.json` |
| `XMPExportPipeline` | `runFromJSON(...)` / `runResolvedInputs(...)` | no | Phase 2 export; `writesBatchArtifacts: false` suppresses batch artifact files |
| `NormalizePipeline` | `runSessionOnly(...)` / `runDryRun(...)` / `runWritePlan(...)` | no | Phase 3 session, dry-run plan, or write plan |
| `ApplySessionPipeline` | `run(...)` | no | Re-apply a stored session, no model runs |
| `AnalyzeAndXMPPipeline` | `run(...)` | yes | analyze + write-xmp in one command |
| `AnalyzeAndNormalizePipeline` | `run(...)` | yes | analyze + normalize (+ export) in one command |
| `ModelInputExportPipeline` | `run(...)` | yes | Diagnostic only: rendered model inputs + manifest, no sidecars/model calls |
| `AnalyzeShellPipeline` | — | — | Legacy pre-model test seam, test-only call sites; audit before touching (see efficiency plan R4) |

## CLI Layer (Sources/AISidecarCLI)

One file per subcommand (`AnalyzeCommand`, `WriteXMPCommand`, `NormalizeCommand`, `ApplySessionCommand`, `BenchmarkCommand`, `PurgeCommand`, `CleanupCommand`) plus `SharedOptions`. The CLI does argument parsing, invocation-request building, and stdout presentation only — reusable behavior belongs in Core.

## Artifacts and File Locations

| Artifact | Where |
|---|---|
| Raw AI sidecar | `<image>.<ext>.ai.json`, beside the image or mirrored under `--output-dir` |
| XMP sidecar | owned parser/writer output, target naming in `Metadata/XMPNaming.swift` |
| Progress log / report / summary | `*-progress-*.jsonl` / `*-report-*.json` / `*-summary-*.md` (names in `Reporting/ArtifactNames.swift`) |
| Normalization session | `normalization-session-*.json`, reusable by `apply-session` |
| Derivative cache | `~/Library/Caches/aisidecar/derivatives` (configurable), manifest JSON + `aisidecar purge` lifecycle |
| Config file | `~/Library/Application Support/aisidecar/config.json` (configurable) |
