# Phase 4 Implementation Plan — CupricAspect GUI MVP

Version: 0.6
Date: 2026-07-07
Requirements basis: `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md` (v0.9)
Visual design basis: `agent_docs/07-cupricaspect-gui-design.md` (v0.1) — read it before building any screen
Audience: junior engineer or Sonnet-level coding agent, one milestone at a time.

**v0.6 changes (requirements v0.9):** milestone **B0 — Beta readiness** inserted before M9 as the next step (packaging, single-source version, first-run guidance, file logging, release evidence, sharp edges); the first beta ships from B0, Wizard-only, with M9–M11 post-beta. FR4-007 amended to single-root import (nested folders via recursive scan) — the M1 "multi-select" wording is superseded.

**v0.5 changes (requirements v0.7):** normalization reality — the Phase 3 engine is fully automatic, so M6 is rewritten as the **Normalization Inspector** (inspection + explanation + session-context input + model-free re-run; FR4-026 amended, FR4-052–055), and the prototypes' keep/merge/rename/drop table is void. **All vocabulary tooling is deferred** (M5 vacated to a stub; FR4-021–025/AC4-005 → Section 12; no milestone may depend on vocabulary editing). New prerequisites: CORE-6 (shared decision explainer) and CLI-1 (`aisidecar explain-session`).

**v0.4 changes (requirements v0.6):** Wizard-first — M1–M8 build only the Wizard shell (Studio toggle disabled, "coming soon"); Studio is now M9, before the experimental database (M10, split into three parts); scale/evidence is M11. New CORE-4 prerequisite (`xmp_export` block in `.ai.json`); M1 gets the corrected file→state derivation table and the lazy-identity policy; M2 gets the FR4-051 Ollama check policy; M4 gets FR4-046a autosave; M5 becomes the vocabulary inspector; M0 code change: single window (FR4-050) and disabled Studio toggle land with M1.

**v0.3 changes:** storage modes (requirements v0.5, FR4-046–048) — sidecar-only is the default; the SQLite working database is an experimental opt-in. Milestones reordered accordingly: the feature flow (import → analyze → review → normalize → export) ships first entirely on files the CLI understands, and the whole database layer (schema, snapshots, external-change detection, retention) is now one late milestone, M9, behind the Settings → Advanced toggle.

**v0.2 changes:** app renamed `CupricAspect` (design decision, requirements v0.4); the GUI target is a SwiftPM executable target in `Package.swift`, not a separate Xcode project (rationale in Section 1); M0 rewritten and completed — it now includes the design-token theme, the aperture component, and the dual-shell skeleton; feature milestones must render with the design system from doc 07.

This plan turns the Phase 4 requirements into ordered milestones. Requirement IDs (FR4-*, NFR4-*, AC4-*) refer to the requirements doc; read the sections cited by each milestone before implementing it. Do not implement ahead of the milestone order.

## 1. Approach Summary

- **App:** `CupricAspect.app`, native SwiftUI, macOS 15 minimum (FR4-001). Two interface shells over one feature state — linear Wizard (default) and nonlinear Studio — per FR4-040/041 and design doc Sections 2, 6, 7.
- **All processing stays in `AISidecarCore`** (FR4-002). The GUI target contains presentation, state orchestration, and user interaction only — the same rule AGENTS.md applies to `AISidecarCLI`.
- **Working state is sidecar-only by default** (FR4-046): durable state lives in `.ai.json` sidecars, XMP sidecars, Phase 3 vocabulary/session files, and `config.json`; queue state is derived by rescanning; in-session review state is memory + session export ("Save session only" / "Apply Prior Session" in the design). The **SQLite database is an experimental opt-in** (FR4-047/048, milestone M9) that adds persisted review state, cross-session external-change detection, and granular resumability — accessed through a thin project-owned data layer (no ORM) when enabled. (M9 reference updated in v0.4: the database milestone is now M10.)
- **Core readiness (verified 2026-07-06):** the library is already embeddable. All pipeline results and callbacks are `Sendable`; there is no `@MainActor` coupling and no direct printing in Core (the `Logger` sink is injectable, default stderr); cancellation exists via `InterruptionMonitor.requestInterruption()` with between-asset checks; pipelines accept absolute paths so the `currentDirectoryPath` fallbacks never fire. Key entry points:
  - `AnalyzePipeline.run(inputPath:configuration:interruptionMonitor:) async throws -> AnalyzeResult`
  - `NormalizePipeline.runSessionOnly/runDryRun/runWritePlan(...) throws -> NormalizePipelineResult`
  - `XMPExportPipeline.runFromJSON/runResolvedInputs(...) throws -> XMPExportPipelineResult` (supports `writesBatchArtifacts: false`)
  - `ApplySessionPipeline.run(...) throws -> ApplySessionPipelineResult`
  - `OllamaVisionRunner.prepare()` for endpoint/model preflight
- **Target structure:** a SwiftPM executable target `CupricAspectApp` (product `CupricAspect`) in the existing `Package.swift`, depending on `AISidecarCore`. One build system for library, CLI, and app: `swift build`/`swift test` cover everything from a clean checkout, and no `.xcodeproj` needs generating or maintaining (xcodegen is not part of the toolchain). During development the app runs via `swift run CupricAspect`; the `.app` bundle (Info.plist, icon, entitlements, hardened runtime) is assembled by the packaging build script — `agent_docs/06-packaging-single-app-plan.md` WI-1 changes from `xcodebuild archive` to a script-assembled bundle around the SwiftPM release binary, which its codesign/notarize steps already accommodate.

## 2. Core Library Prerequisites (do these first, in the SwiftPM package)

Small Core additions the GUI needs. Each follows AGENTS.md rules (reusable behavior in Core, tests with each change).

**CORE-1 — In-process progress callback ✅ (analyze pipeline, completed 2026-07-07).** `AnalyzePipeline.run` takes an optional `progressHandler: (@Sendable (ProgressRecord) -> Void)?`, invoked once per emitted record inside `emit`, alongside — not replacing — the JSONL and logger writes. Default `nil` keeps CLI behavior identical. The equivalent hooks for the normalization/export per-target loops land with the milestones that first consume them (M6/M7).
*Acceptance (met for analyze):* `testProgressHandlerReceivesEveryEmittedRecordAlongsideLogWrites`.

**CORE-2 — Artifact-write opt-out ✅ (analyze pipeline, completed 2026-07-07).** `AnalyzePipeline.run(writesBatchArtifacts: false)` writes `.ai.json` sidecars but no batch progress/summary files, matching `XMPExportPipeline.runResolvedInputs`. Default `true` keeps CLI behavior identical. Audit `NormalizePipeline` when M6 consumes it.
*Acceptance (met for analyze):* `testWritesBatchArtifactsFalseWritesSidecarsButNoReports`.

**CORE-4 — `xmp_export` block in `.ai.json` ✅ (completed 2026-07-07; FR4-049).** `RawSidecarExportStamp` writes the additive block over the generic JSON object (newer-schema fields survive; atomic write); `XMPExportPipeline` stamps every selected contributing sidecar after a per-target write reaches `written`/`created` — so both the Phase 2 export path and Phase 3 `apply-session` stamp, dry runs never do, and a fresh analysis truthfully clears a stale stamp by rewriting the sidecar. Stamping is best-effort by design: it never fails an export whose write and validation already succeeded.
*Acceptance (met):* `testSuccessfulExportStampsContributingRawSidecars` (block contents, dry-run negative, post-stamp typed decode) and the GUI-side `testPlanThenWriteFlipsQueueDerivationToExported` closing the AC4-028 loop.

**CORE-5 — Discovery-only scan ✅ (completed 2026-07-06).** `ImageScanner.inventory(inputPath:recursive:)` returns `ScanInventory` entries (path, relative path, name, extension, size, mtime, detected type) plus the usual recoverable errors, sharing the same visibility/ignore/supported-type rules as `scan` but computing no `SourceIdentity` — the M1 lazy-identity policy needs listing without hashing. `scan` is now built on the same discovery pass, so the two cannot disagree.
*Acceptance (met):* inventory/scan parity, non-recursive exclusion, single-file input, and unsupported-file error tests in `ImageScannerInventoryTests`; full suite unchanged.

**CORE-6 — Normalization decision explainer ✅ (completed 2026-07-07; FR4-055).** `NormalizationDecisionExplainer` in Core: exhaustive enum→sentence mappings (a new case is a compile error until it gets text) for stage/status/kind/skip-reason, `KeywordDecisionSummary` rollup over a session (outcome counts, stages, rules, skip-reason histogram, support, conflicts, per-asset detail, needs-attention), folded keyword lookup, and `renderLines` plain-text rendering. Stage/status/kind gained `CaseIterable` (additive).
*Acceptance (met):* distinctness/exhaustiveness tests + rollup tests against a pipeline-produced session in `NormalizationExplainerTests`.

**CLI-1 — `aisidecar explain-session` ✅ (completed 2026-07-07; AC4-031).** Read-only subcommand: `explain-session <session.json> [--keyword <term>] [--needs-attention] [--verbose]` — presentation over CORE-6 only. Smoke-verified against a real session (session-only normalize over the M2 fixture set).

**CORE-3 — Pause/resume clarification ✅ (verified 2026-07-07, no Core change).** FR4-010 requires pause/resume. `InterruptionMonitor` supports graceful *stop*; "pause" is a GUI-level job-queue concern: run work in bounded slices and simply not schedule the next slice while paused; `--existing skip` semantics make re-runs additive.
*Acceptance (met):* `testTwoSliceRunMatchesSingleFullRun` proves a single-file slice + skip-folder slice produces sidecars identical to one uninterrupted run.

## 3. Milestones

### M0 — App scaffold, design tokens, aperture, shell skeleton ✅ (completed 2026-07-06)

- Add the `CupricAspectApp` executable target (product `CupricAspect`) to `Package.swift`, macOS 15, depending on `AISidecarCore`. No sandbox in MVP development builds (final decision in the packaging plan).
- Implement the design-token theme from design doc Section 3 (`Theme.swift`): light/dark palettes, the three accent palettes with per-theme variants, resolved theme/accent published to the environment; theme (`light`/`dark`/`auto`) and accent persisted via `@AppStorage`; Auto follows the system appearance live.
- Implement `ApertureView` per design doc Section 5 (`TimelineView` + `Canvas`): idle-open, running breathing cycle + spin, static under reduce-motion.
- Root shell switcher per FR4-040/041: `@AppStorage("cupricaspect.nonlinear")` selects Wizard or Studio placeholder shells; both render the 46px title-bar styling, branding, and an About surface showing the app version and Core engine/writer versions (`OwnedXMPSidecarEngine.engineVersion`, `.writerRecipeVersion`).
- Add a `Sources/CupricAspectApp/AGENTS.md` stub pointing agents at this plan, the requirements doc, and design doc 07.
- **Done when:** `swift build --product CupricAspect` and `swift run CupricAspect` work from a clean checkout (window shows branding, theme/accent/shell toggles function); `swift test` still passes for the package.

*Status: implemented — see `Sources/CupricAspectApp/`. Subsequent milestones replace the placeholder shell content with real features, styled per design doc 07.*

Milestones M1–M8 are **sidecar-only** (FR4-046) and **Wizard-only** (FR4-040 MVP scoping): they must not create or read a database, and they build feature views embedded in the Wizard shell only — but always as shell-agnostic `Features/` views, so M9 (Studio) is chrome work, not feature rework. M9 adds the Studio shell. M10 adds the experimental database mode behind the Settings → Advanced toggle, in three parts. M11 closes out scale and release evidence for both modes.

Per-milestone **Not in this milestone** lines are binding scope limits — when tempted to build beyond them, stop.

### M1 — Folder import and asset queue, sidecar-derived ✅ (completed 2026-07-06; FR4-007, FR4-011 in-memory form, FR4-049 read side, FR4-050, AC4-001, AC4-028)

- Folder picker plus drop target per design doc §6 Step 1; security-scoped access if sandboxed later; always pass absolute paths into Core. (v0.9: single root folder by requirement — FR4-007 amended; nested folders via the recursive toggle. The original "multi-select" wording is superseded.)
- Scan via `ImageScanner`; honor same-base-name grouping metadata for later export.
- **Lazy identity policy:** the queue displays on path + size + mtime alone. Full `SourceIdentity` hashing is deferred until a pipeline actually needs it (analyze/export), then computed off the main actor; an optional background backfill may run at utility QoS. Never hash the whole folder just to show the queue.
- In-memory asset queue observable. Between-launch states derive from files only, per this table (FR4-049; do not invent states):

  | On disk | Derived state |
  |---|---|
  | image only | `discovered` |
  | image + `.ai.json` | `analyzed` |
  | image + `.ai.json` with `xmp_export` block + target XMP present | `exported` |
  | image + target XMP present, no `xmp_export` block | `XMP present (external)` |
  | image + `.ai.json` with `xmp_export` block, target XMP missing | `XMP missing (was exported)` |

  (Until CORE-4 lands, no `.ai.json` has the block, so XMP presence always derives `XMP present (external)` — correct by construction.) The remaining FR4-011 states are transient in-run states held in memory while a job runs. Failed states carry `SidecarError` code + message and are filterable by code for the current session.
- Queue list UI: virtualized table with state, filename, error-code filter, embedded in Wizard Step 1.
- Code changes from review decisions land here: single window (FR4-050 — `Window` scene, not `WindowGroup`) and the disabled "coming soon" Studio toggle (FR4-040).
- **Not in this milestone:** no analysis runs, no thumbnails, no `SourceIdentity` eager hashing, no persistence of any kind.
- **Done when:** importing a mixed RAW/JPEG folder shows scan progress and a populated queue; re-import is idempotent; relaunching rebuilds the same queue from disk; a pre-existing XMP renders "XMP present (external)" (AC4-028 read side); no database file exists (AC4-025 groundwork).

*Status: implemented — `Features/Import/` (`AssetQueue.swift` derivation + `FolderImportModel` + `Step1PhotosView`), Wizard step rail/footer in `Shells/WizardShellView.swift`, derivation tests in `Tests/CupricAspectAppTests`. Verified against a fixture folder exercising every derived state, including the AC4-028 external-XMP case. A `CUPRIC_IMPORT_PATH` environment hook auto-imports a folder for dev/UI-test launches.*

### M2 — Analysis job engine ✅ (completed 2026-07-07; FR4-008, FR4-009, FR4-010, FR4-051, AC4-002)

- Preflight: endpoint + model tag selection defaulting to the project default, validated through `OllamaVisionRunner.prepare()`; record model digest (FR4-009). Show actionable guidance when Ollama is unreachable (mirror README troubleshooting).
- Job engine: a single serialized job queue actor that runs pipeline slices in background tasks; start/pause/resume/cancel (FR4-010) via slicing (CORE-3) + `InterruptionMonitor`.
- Wire CORE-1 progress hooks to in-memory queue state and UI updates (the Working screens' progress, current file, rate); keep XMP-parse/hash work off the main actor (FR4-006c, NFR4-003).
- Mode selection: whole image / subject isolated / both (FR4-008).
- Ollama checks per FR4-051: at launch, before each run, and on manual refresh only — no polling loop. Status UI shows the last result and check time.
- Interrupted runs resume naturally on the next run via `--existing skip` semantics over the files already written.
- **Not in this milestone:** no review UI, no XMP anything, no autosave (that's M4's review state).
- **Done when:** the user can run analysis on an imported folder, watch per-asset state advance, cancel mid-batch, relaunch, re-run, and end with the same set of `.ai.json` files a single uninterrupted run produces.

*Status: implemented — `Features/Run/` (`AnalysisRunModel` engine + options, Wizard Steps 2–4 views, Step 5 run summary as the M4 stand-in). Options resolve through `ConfigurationResolver` (CLI-equivalent overrides over config.json). Verified end-to-end against live Ollama: real analyze run over generated JPEGs, per-asset progress advancing the queue, structured error codes surfaced on the summary (`E_MODEL_SCHEMA_VIOLATION` from a schema-violating substitute model), sidecars with full provenance on disk. Cancel returns to Step 3 per design; run failures banner on Step 3 with Ollama guidance (FR4-051).*

### M3 — Thumbnails and previews ✅ (completed 2026-07-07; FR4-013, FR4-014, FR4-039 groundwork)

- Reuse the derivative cache (`DerivativeCache`, `ImageRenderer`) for preview derivatives; keep an in-memory thumbnail index over the shared cache (no DB).
- Grid view virtualization (LazyVGrid or NSCollectionView interop) with lazy full-preview loading.
- Subject-isolated derivative display when available, with instance count and selected-instance indication (FR4-014).
- **Done when:** a 5,000-asset synthetic folder (script fabricates tiny images + `.ai.json` sidecars) scrolls and filters without perceptible stalls (AC4-014 groundwork; final verification in M11).

*Status: implemented — `Features/Preview/` (`ThumbnailStore`: ImageIO embedded-thumbnail decode, byte-capped NSCache, in-flight dedup; `AssetPreviewDetails`: off-main sidecar decode preferring cached pipeline derivatives; `AssetPreviewSheet`: whole image + subject derivative with instance count/selection per FR4-014) and `Features/Import/AssetGridView` (LazyVGrid, async cells, state dots), with a Grid/List toggle in Step 1. `Scripts/generate-synthetic-fixture.swift` fabricates the synthetic folder; verified with 5,000 assets: scan+derive populated the queue in seconds, grid renders lazily, process idle ~110 MB RSS. Interactive scroll-feel check on real RAW libraries remains a manual step (M11). Preview decode covered by tests against an unmodified pipeline-written sidecar fixture.*

### M4 — Candidate review UI and session durability ✅ (completed 2026-07-07; FR4-013–FR4-020, FR4-046a, NFR4-008, AC4-003 partial, AC4-004, AC4-013, AC4-027)

- Review screen: full image + isolated derivative, candidate list showing flat keyword, hierarchical keyword, confidence band, evidence, alternatives, vocabulary match, normalization rule, review requirement, provenance, and producing source (FR4-015/016).
- Approve / reject / edit / defer per candidate; batch approve/reject (FR4-017/018) — all in-memory review state.
- "Save session only" exports the review state in the Phase 3 session-file format (NFR4-008); "Apply Prior Session" / session import resumes it (FR4-012b). `apply-session` parity: a GUI-exported session applies cleanly via `swift run aisidecar apply-session` (AC4-013 cross-check).
- Autosave per FR4-046a: recovery session file in the GUI state directory every 25 decisions or 5 minutes; unclean-exit restore offer on relaunch (AC4-027).
- Scoped batch correction with explicit confirmation, limited to computable scopes only (FR4-019 — no "visually similar").
- `requires_review` vocabulary policy surfaced, not reimplemented (FR4-020). (FR4-020a external-removal rendering is database-mode — arrives in M10b.)
- **Done when:** AC4-004 walkthrough passes on a real analyzed folder, and an export → quit → relaunch → import round trip restores the review exactly.

*Status: implemented. **Architecture:** the durable review form is a Phase 3 session document — `SessionReview` (Core, CORE-7) applies verdicts as decision status + additive `user_review_rejected`/`user_review_deferred` skip reasons and edits as additive `user_edited` candidate kind, so `apply-session` writes exactly the approved set with zero new write paths (AC4-013, proven by `testApplySessionWritesOnlyApprovedKeywords`). The review base session is built model-free via `runSessionOnly` (`fromJSON`, observed-tags + single-image). **GUI:** `Features/Review/` — `ReviewModel` (verdicts, edits, folder-scoped `editEverywhere` for FR4-019's computable scope, FR4-046a autosave: 25 decisions / 5 minutes to a recovery session, launch-time restore offer) and `Step5ReviewView` (thumbnail rows, keyword chips with confidence band + provenance/vocabulary-kind tooltip, approve/reject/defer/edit context menu, per-asset Accept all, batch Approve/Reject all, Save session only / Import session). Verified live against real model output. **Known gaps for later milestones:** the isolated-derivative side-by-side inside review rows (M3's preview sheet has it; wire a click-through in M6/M7 polish — AC4-003 partial), and richer per-candidate detail beyond the tooltip.*

### M5 — (vacated in v0.5) Vocabulary tooling deferred

All vocabulary tooling moved to requirements Section 12 (v0.7): it is not currently an enabled part of the product, and no milestone depends on it. The MVP's only vocabulary touchpoints are the vocabulary-file picker in the normalize options (M6) and read-only display of engine-reported vocabulary facts. The milestone number is kept so cross-references stay stable; there is no M5 work item.

### M6 — Normalization Inspector ✅ (completed 2026-07-07; FR4-026 amended, FR4-027, FR4-027a/b, FR4-052–055, AC4-006, AC4-016, AC4-029, AC4-030; prerequisites CORE-6 ✅, CLI-1 ✅)

- **Session context panel** (FR4-052, AC4-029): Subject/Habitat/Event fields with vocabulary-match feedback, per-field propagation toggles (off by default), unknown-context policy; plus the vocabulary-file picker (bundled starter vocabulary default).
- Run `NormalizePipeline.runSessionOnly`/`runDryRun` over the existing `.ai.json` set (`fromJSON` mode, no model calls); persist the session document as a file.
- **Inspector table** (FR4-026, AC4-030): keyword / support bar (asset count + support units) / outcome chip (accepted · withheld · skipped) / why (stage + governing rule + skip reasons via the CORE-6 explainer); expandable per-asset detail with supporting assets and conflicts (FR4-027); raw vs canonicalized vs propagated vs user-context visually distinct (FR4-027a); hierarchy display only from `canonical_path` (FR4-027b). Filters: outcome, stage, needs-attention. FR3-025 non-supporting/conflicted lists reachable per context value.
- **Re-run loop** (FR4-054): "Re-run normalization" after vocabulary-file or context changes; stale-vocabulary indicator via content-hash mismatch.
- **Export surface** (FR4-053): "Write normalized XMP" (accepted set only, exclusions labeled) and "Save session only"; import an existing session and continue (FR4-012b, AC4-016).
- **Not in this milestone:** no per-keyword decision controls of any kind (the engine has none — FR4-026); no vocabulary editing (point at the file path + re-run loop instead); the XMP write itself reuses M7's export path if M7 lands first, otherwise `runWritePlan` + Phase 2 writer as the engine already wires it.
- **Done when:** AC4-006, AC4-016, AC4-029, and AC4-030 pass against a real analyzed folder, with CLI-1's `explain-session` showing identical facts for a spot-checked keyword (AC4-031).

*Status: implemented — `Features/Normalize/` (`NormalizationModel`: context→config mapping, model-free `fromJSON` run, CORE-6 summaries, outcome/stage/needs-attention filters, SHA-256 stale-vocabulary indicator, save/import, accepted-only write via `ApplySessionPipeline` + `XMPExportPipeline`; `SessionContextPanel` per FR4-052 with per-field propagation gates off by default and the vocabulary-file picker; `NormalizationInspectorView` with support bars, outcome chips, explainer why-lines, expandable per-asset detail with conflicts, and post-run session-context results). Wizard normalize action enabled end-to-end: analyze → normalize → Inspector → write, verified live against real model output (10 keywords, 27 accepted decisions, correct explanations). The normalize write currently writes directly with the Phase 2 backup/validation chain; the M7 dry-run change-plan view will front it.*

### M7 — Export, validation, and compatibility ✅ (completed 2026-07-07; FR4-028–FR4-038b, AC4-007, AC4-008, AC4-010, AC4-011, AC4-017, AC4-018 partial, AC4-019, AC4-028)

- Dry-run first: render the change plan visually before any write (FR4-029); same-base-name groups shown with pair-scope selection (FR4-034, AC4-018).
- Export through `XMPExportPipeline` with the owned engine unchanged (FR4-028); backups, restore-on-validation-failure, and post-write validation surfaced in the export report UI (FR4-035, FR4-035b/c). Export always re-reads and semantically merges against current sidecar content (Phase 2 behavior), so out-of-band edits are honored even without change *detection*; the FR4-048 limitation disclosure appears here.
- CORE-4 lands here at the latest: successful exports write the `xmp_export` block (FR4-049), and the M1 queue derivation starts reporting `exported` / `XMP missing (was exported)` states (AC4-028 full).
- Malformed/unsupported XMP as first-class UI states with `E_XMP_PARSE_FAILED` / `E_XMP_UNSUPPORTED_RDF`, export disabled until resolved or excluded (FR4-035a).
- Lightroom Classic and Capture One compatibility profiles and post-export instructions (FR4-036–FR4-038); compatibility-report view (FR4-038a).
- No external tool invocation anywhere (FR4-028a, AC4-019).
- **Done when:** the listed ACs pass, including a full round trip verified in Lightroom Classic or Capture One (release evidence pattern from `agent_docs/release-evidence/`), plus AC4-025 end-to-end (still no database file).

*Status: implemented — `Features/Export/` (`ExportModel`: every write fronted by a dry-run change plan per FR4-029, then the real write through `ApplySessionPipeline` + `XMPExportPipeline` — the Phase 2 backup/source-hash/validation/restore chain unchanged; `ChangePlanSheet`: per-target adds, same-base-name group + pair-scope badges (AC4-018 display — pair-scope *selection* is fixed at session build, noted), failed targets excluded with error codes per FR4-035a, LR/C1 compatibility notes per FR4-036–038; `ExportReportView`: per-target status/backup/validation/errors, engine identity, report-recorded application instructions per FR4-035b/c and FR4-038a-lite; `Step3ApplyView`: session picker with recorded facts). All four wizard actions now live: analyze / write / normalize / apply, all writes through the one export surface. The Lightroom Classic / Capture One round-trip check remains a manual release-evidence step (Ron: run a write, open in LR/C1, record per `agent_docs/release-evidence/`).*

### M8 — Sidecar-only hardening ✅ (completed 2026-07-07; AC4-025, crash behavior)

- Kill-mid-batch testing: scripted kill/relaunch during analyze and export leaves no ambiguous file state (partial writes are the pipelines' existing temp-file/rename discipline; verify from the GUI paths).
- Relaunch reconstruction review: every screen's state either rebuilds from disk or is explicitly session-scoped and marked as such.
- **Done when:** AC4-025 passes end-to-end repeatedly, including kill/relaunch variants.

*Status: implemented and verified live. **`Scripts/m8-kill-relaunch-check.sh`** (repeatable; needs Ollama) SIGKILLs the app mid-analyze, asserts no atomic-writer temp files and every surviving `.ai.json` parses, relaunches and resumes to the full set via existing-skip, runs the CLI normalize + apply-session follow-through to well-formed XMP, and asserts no database file exists under the state directory (AC4-025). First live run: killed at 1/6 → resumed to 6/6 → 6 valid XMPs → PASS. **Housekeeping:** `StateHousekeeping.pruneArtifacts` removes per-run artifact directories (`review-artifacts`/`normalize-artifacts`/`export-sessions`) older than 7 days at launch — never the recovery file — so the state directory is bounded (tested). **Relaunch reconstruction audit:** queue → rescanned from disk (including `exported` via the CORE-4 stamp); options → re-resolved from the config chain; run progress → transient by design, resumable via skip semantics; review → FR4-046a recovery file + explicit session save/import; Inspector → session files (AC4-016); export plans → ephemeral dry-runs, recomputed; written state → derived from stamps + XMP on disk; appearance/shell → UserDefaults. Nothing depends on process memory alone.*

### M8a — Settings expansion and model picker ✅ (completed 2026-07-07; FR4-056, FR4-057, AC4-032, AC4-033; requirements v0.8)

- **CORE-8:** `OllamaVisionRunner.listInstalledVisionTags(endpoint:)` — the preflight's `/api/tags` + `/api/show` probing exposed standalone (serial per invariant 15); tested via the recorded transport.
- **CORE-9:** `ConfigFileEditor.merge` — read-modify-write over the shared `config.json` preserving unknown keys, atomic, creates file/directory when missing; tested including CLI-resolve parity.
- **GUI:** `Features/Settings/` — `SettingsModel` (resolves through the standard chain, writes through CORE-9, discloses active `AISIDECAR_*` overrides, rejects invalid endpoints without writing) and `SettingsSheet` (vision model picker with refresh + unavailable-model flag, editable endpoint with connectivity badge, render/GPS/existing defaults, config Reveal, derivative-cache Purge with confirmation, appearance, about card). Replaces the M0 About sheet; Studio adopts it in M9.
- Verified live: connected badge and picker against a running Ollama; write-through, unknown-key preservation, env-disclosure, and vision filtering covered by tests.

### B0 — Beta readiness (requirements v0.9; the first beta ships from here, Wizard-only)

The MVP feature flow is complete (M0–M8a). B0 turns it into something that can be handed to a beta tester. Work the items in this order; each is independently committable. M9–M11 are post-beta.

**Progress (2026-07-07): B0-1 (minus Developer ID signing/notarization), B0-2, B0-3, B0-4, and B0-6 are done — see per-item status notes. Outstanding: B0-5 (manual release evidence), the Developer ID signing/notarization/`spctl` pass, and the `v0.1.0-beta.1` tag. Alongside B0, the always-on Phase 2 merge-into-existing-XMP behavior (backup-and-merge default) was verified end-to-end (CLI live round trip preserving foreign keywords, `xmp:Rating`, and a timestamped backup) and is now revealed in the change-plan UI: a standing policy card, per-target merge/new-file badges with preserved-keyword counts from the dry-run preview, and footer totals.**

**B0-1 — Packaging (the blocker).** Execute `agent_docs/06-packaging-single-app-plan.md` WI-2 → WI-1 → WI-4 → WI-6 for the GUI: resource-bundle relocation test first (the plan's own "most likely bug"), then the release build script that assembles `CupricAspect.app` around the SwiftPM release binary (Contents/MacOS, Info.plist per WI-4, embedded CLI per D3 optional for beta — GUI-only bundle is acceptable for B0), `.icns` generated from the design bundle's `cupricaspect_icon-3.svg`, Developer ID signing + notarization + stapling, DMG.
*Done when:* the DMG installs and launches on a Mac that has never had Xcode, `spctl --assess` passes.

*Status (2026-07-07): implemented except Developer ID signing/notarization (deferred by decision until the certificate is in hand — the script ad-hoc signs by default and takes `--sign <identity>` for the WI-1 steps 4–5 when ready; `spctl --assess` therefore still pending). WI-2 found the real relocation bug: SwiftPM's generated `Bundle.module` accessor checks only the main-bundle root and the absolute build-machine path — a relocated executable resolves resources only on the machine that built it, and an app bundle would look in the `.app` root, not `Contents/Resources`. Fixed with `AISidecarResourceBundle` in Core (search order: `Contents/Resources` → executable-adjacent → `../Resources` for the Helpers CLI → `Bundle.module` for dev/test); prompts, schemas, and vocabulary all resolve through it. The SwiftPM resource bundle is flat, so codesign rejects a copy under `Helpers/` — the app carries ONE copy in `Contents/Resources` shared by both executables. `Scripts/wi2-relocation-check.sh` proves both relocated layouts with the build tree hidden plus a negative control. `Scripts/build-release.sh` assembles `dist/CupricAspect.app` (Info.plist from `Scripts/packaging/Info.plist.template`, committed `AppIcon.icns` from `Scripts/generate-app-icon.sh`, embedded CLI by default, version cross-checked against the embedded CLI) and packs the DMG. Verified: assembled app launches, embedded CLI reports the product version.*

**B0-2 — Single-source version (packaging plan D5).** One version constant feeds the app About card, `CFBundleShortVersionString`, and `aisidecar --version` (currently "0.0.0"). Tag the beta `v0.1.0-beta.1`.
*Done when:* all three surfaces show the same non-placeholder version from one source.

*Status (2026-07-07): done — `AISidecarVersion.current` ("0.1.0-beta.1") in Core feeds `aisidecar --version`, the About/Settings cards, and the build script's `CFBundleShortVersionString` injection (cross-checked at assembly). The `v0.1.0-beta.1` tag itself waits for B0-5 evidence.*

**B0-3 — First-run / missing-runtime guidance (FR4-058, AC4-034; packaging plan WI-5).** Launch-time Ollama check with install/start guidance; empty vision-model list explains itself and names a starter model with its `ollama pull` command (do not silently assume the 26B default model exists).
*Done when:* AC4-034 passes on a clean user account without Ollama, and again with Ollama but no vision model.

*Status (2026-07-07): done — `RuntimeGuidanceModel` (one launch-time check + manual re-check, no polling) drives a Wizard banner: unreachable → install/start guidance with a Download Ollama action; reachable-but-no-vision-model → starter suggestion with a copyable `ollama pull <resolved tag>` command. Settings' empty model picker explains itself the same way. Unit-tested via an injected tag lister; unreachable banner verified live against a dead endpoint. The clean-user-account pass remains part of B0-5's manual round.*

**B0-4 — Diagnostic file logging (FR4-059, AC4-035).** Replace the discarded `Logger(sink: { _ in })` with a shared file sink: size-bounded log under the state directory, path shown in Settings → About. Fix the silent `try?` on "Save session only" / session import — errors surface in the UI.
*Done when:* AC4-035 passes; a deliberately failed run's structured errors are readable in the log file.

*Status (2026-07-07): done — `FileLogSink` (5 MB cap, one rotated generation, text format so `errors=E_*` codes stay readable) under `~/Library/Application Support/CupricAspect/logs/`, fed by all four pipeline loggers; path + Reveal in Settings → About. Review and normalization save/import/restore surface failures via `fileError` in the UI and echo them to the log. Sink write/rotation/level tests in `GUILogTests`.*

**B0-5 — Release evidence (manual).** The Lightroom Classic / Capture One round trip per `agent_docs/release-evidence/` (write real XMP from the GUI, import in LR/C1, record results), plus the outstanding Phase 1 M9 calibration evidence or an explicit deferral note (AGENTS release-signoff requirement).
*Done when:* evidence files exist under `agent_docs/release-evidence/` for the current writer recipe.

**B0-6 — Sharp edges.**
- Single-folder import is now the requirement (FR4-007 amended v0.9) — no code change needed; verify the Step 1 copy doesn't promise otherwise.
- Pause story (FR4-010): either a Pause button implemented as cancel-plus-resume (skip semantics already make this safe — CORE-3), or explicit UI copy on Cancel: "progress is kept; Start resumes where you left off."
- Review-screen scale sanity: load the M4 review list from a 1,000–2,000 image synthetic session (`Scripts/generate-synthetic-fixture.swift`) and fix any stalls (the 5,000 target formally lands in M11).
- Reopen-last-folder convenience on launch (remember the last source/output folders in UserDefaults; offer, don't auto-import).
*Done when:* each edge verified with a note here.

*Status (2026-07-07): all four verified.* **Step 1 copy** — already singular ("Drop a folder of photos here"); screenshot-checked, no change. **Pause story** — the copy option: Step 4's Cancel now carries "Progress is kept — analyzed photos stay done. Start again to resume where you left off." **Review scale** — the generator gained `--sidecar-template` (patches a real pipeline sidecar per image, correct per-file identity) so full 1,500-asset sessions can be fabricated; the env-gated `ReviewScaleTests` (`CUPRIC_SCALE_TESTS=1 CUPRIC_SCALE_DIR=…`) measured session build 8.5 s (one-time, behind the building spinner), `assetRows` recompute 40 ms, single-asset verdict update < 100 ms — no stalls to fix; rows render in a `LazyVStack`. **Reopen-last-folder** — `FolderImportModel` remembers source/output in UserDefaults and offers a "Last time: …" row on launch (Reopen/dismiss, never auto-imports); covered by `FolderImportReopenTests`.

**Not in B0:** Studio (M9), the database (M10), vocabulary tooling, embedded-CLI install action (WI-3), Sparkle/auto-update, CI. Beta distribution is a signed DMG handed out directly.

### M9 — Studio shell (FR4-040, FR4-041, AC4-021)

- Build the Studio chrome per design doc §7: 214px sidebar, centered window title, per-view sticky run bars; embed the existing `Features/` views (they were built shell-agnostic in M1–M8 — this milestone is chrome and navigation, not feature work).
- Enable the "Nonlinear UI" toggle (remove "coming soon"); FR4-041 state survival across shell switches; the Studio views map to the same feature state the Wizard steps use.
- **Not in this milestone:** no database anything; no new feature behavior — if a feature view needs changes to embed cleanly, that's a `Features/` refactor ticket, not Studio scope creep.
- **Done when:** AC4-021 passes (switch off→on→off with in-flight state, relaunch restores shell choice), and the M1–M8 golden-path walkthroughs pass identically in Studio.

### M10 — Experimental database mode (FR4-003–FR4-005, FR4-004a–c, FR4-011 persisted, FR4-012a, FR4-020a, FR4-030a–e, NFR4-004, NFR4-007, AC4-009, AC4-012, AC4-015, AC4-020, AC4-023, AC4-024, AC4-026)

Everything database-backed lands here, behind Settings → Advanced → "Working database (experimental)" (FR4-047; design doc Settings spec). Implement as three sequential sub-milestones — each independently landable with `swift test` green:

**M10a — Data layer and schema v1.**
- Thin wrapper over the system SQLite3 C API (no third-party ORM): connection actor, typed statement helpers, migration runner. Database file under `~/Library/Application Support/CupricAspect/` — never in the app bundle.
- Schema v1 tables (from FR4-004): `assets`, `source_identities`, `sidecar_snapshots` (content hash, mtime, parse state, `XMPMetadataSnapshot` blob, `XMPUnmanagedContentFingerprint` blob, engine/recipe versions), `derivatives`, `model_runs`, `tag_candidates`, `tag_reviews`, `vocabulary_entries`, `normalization_sessions`, `export_actions`, `review_actions`, `external_change_events`, `backups`, `validation_results`, `schema_meta`. Core `Codable` documents stored as JSON blobs; index only what the UI filters on.
- Migration policy per NFR4-007; every asset state change one transaction (NFR4-004); the Settings → Advanced toggle with enable/disable flows per FR4-047 and AC4-026, including the keep-or-delete offer. When enabled, the persisted FR4-011 state machine replaces the in-memory derivation.
- **Done when:** AC4-015 and AC4-026 pass; AC4-025 still passes with the toggle off.

**M10b — Sidecar snapshots and external-change detection.**
- Snapshot job (FR4-030a), manual "Refresh Metadata" (FR4-012a, AC4-020), pre-export freshness check (FR4-030b/c), non-resurrection (FR4-030d, FR4-020a) — the M4 review UI gains the externally-removed rendering.
- **Done when:** AC4-009 and AC4-020 pass using a sidecar edited by hand between sessions.

**M10c — Retention.**
- Forget-folder (one transaction, export-or-confirm gate, "Forget folder…" in the queue UI), age-based prune with change-detection exemptions, post-delete `VACUUM` off the main actor; Settings exposes the retention window (default 180 days).
- **Done when:** AC4-023 and AC4-024 pass.

### M11 — Scale, polish, release evidence (FR4-039, AC4-014, remaining NFRs)

- Real 5,000-image session benchmark in **both modes**: scrolling, filtering, selection latency; batched DB writes when enabled; profiling pass with Instruments.
- Retention at scale (database mode): prune + vacuum measured on the 5,000-image session with no main-actor stalls; AC4-024 verified against a session with events aged past the window.
- Provenance completeness audit (NFR4-005); conservative-defaults review (NFR4-006); privacy audit — nothing uploads (NFR4-001/002).
- Record release evidence following the `agent_docs/release-evidence/` pattern.
- **Done when:** every AC4-001…AC4-028 has a recorded pass or an explicit deferral note (database-mode ACs recorded with the toggle on).

## 4. GUI Target Structure

```
Sources/CupricAspectApp/
├── App/                 CupricAspectApp.swift (@main), root shell switcher, DI container
├── DesignSystem/        Theme.swift (tokens, doc 07 §3), ApertureView.swift (§5),
│                        shared styled controls (segmented, chips, cards) as they emerge
├── Shells/
│   ├── Wizard/          step rail, footer nav, the five step screens (doc 07 §6)
│   └── Studio/          sidebar, run bars, the seven views (doc 07 §7)
├── Data/                SQLite wrapper, migrations, repositories (one per table group)
├── Jobs/                Job queue actor, pipeline slicing, InterruptionMonitor wiring, progress bridge
├── Features/            shell-agnostic feature views/state both shells embed
│   ├── Import/          folder picker, scan, queue list
│   ├── Review/          review screen, candidate actions, batch corrections
│   ├── Normalization/   session context panel, inspector, re-run loop
│   │                    (Vocabulary/ returns if Section 12 tooling lands)
│   ├── Export/          change-plan view, export runner, compatibility reports
│   └── Settings/        model/endpoint config, cache locations, appearance, shell toggle
└── Support/             formatting, error-code presentation, preview fixtures
```

Shells are thin: layout, navigation, and chrome only. Feature views and their observable state live in `Features/` and are embedded by both shells (FR4-041 state survival falls out of this). Rules mirror AGENTS.md: anything two features share and any non-presentation logic goes to `AISidecarCore`, not `Support/`.

## 5. Testing Strategy

- Data layer and job engine: XCTest in a `CupricAspectAppTests` SwiftPM test target, offline, deterministic — same bar as `AISidecarCoreTests`; runs under plain `swift test`.
- Pipeline integration: use Core's existing mock runners (`MockVisionModelRunner`, recorded-fixture replay) so GUI tests never need Ollama.
- UI: XCUITest smoke for the M1 import, M4 review, and M7 export golden paths only; don't chase pixel coverage. (XCUITest needs an app bundle — defer wiring it until the packaging script exists; manual golden-path walkthroughs are the interim bar.)
- Every milestone ends with `swift test` green and `swift build --product CupricAspect` succeeding.

## 6. Out of Scope (MVP)

Everything in requirements Section 3 "shall not" and Section 12 (embedding search, OCR passes, DAM profiles, embedded metadata writing, plug-ins). Do not scaffold for these beyond what the requirements' Section 12 groundwork already implies.
