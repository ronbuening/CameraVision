# Phase 4 Implementation Plan — GUI Sidecar Tagger MVP

Version: 0.1
Date: 2026-07-06
Requirements basis: `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md` (v0.3)
Audience: junior engineer or Sonnet-level coding agent, one milestone at a time.

This plan turns the Phase 4 requirements into ordered milestones. Requirement IDs (FR4-*, NFR4-*, AC4-*) refer to the requirements doc; read the sections cited by each milestone before implementing it. Do not implement ahead of the milestone order.

## 1. Approach Summary

- **App:** `SidecarTagger.app`, native SwiftUI, macOS 15 minimum (FR4-001). Working name kept until release naming is decided.
- **All processing stays in `AISidecarCore`** (FR4-002). The GUI target contains presentation, state orchestration, and user interaction only — the same rule AGENTS.md applies to `AISidecarCLI`.
- **Working state lives in SQLite** (FR4-003/004), accessed through a thin project-owned data layer (no ORM). XMP sidecars are export artifacts; the database is working truth; reconcile before export (FR4-005).
- **Core readiness (verified 2026-07-06):** the library is already embeddable. All pipeline results and callbacks are `Sendable`; there is no `@MainActor` coupling and no direct printing in Core (the `Logger` sink is injectable, default stderr); cancellation exists via `InterruptionMonitor.requestInterruption()` with between-asset checks; pipelines accept absolute paths so the `currentDirectoryPath` fallbacks never fire. Key entry points:
  - `AnalyzePipeline.run(inputPath:configuration:interruptionMonitor:) async throws -> AnalyzeResult`
  - `NormalizePipeline.runSessionOnly/runDryRun/runWritePlan(...) throws -> NormalizePipelineResult`
  - `XMPExportPipeline.runFromJSON/runResolvedInputs(...) throws -> XMPExportPipelineResult` (supports `writesBatchArtifacts: false`)
  - `ApplySessionPipeline.run(...) throws -> ApplySessionPipelineResult`
  - `OllamaVisionRunner.prepare()` for endpoint/model preflight
- **Target structure:** a new Xcode app project `SidecarTagger/` at the repo root that depends on the existing local SwiftPM package for `AISidecarCore`. `Package.swift` remains the source of truth for the library and CLI; the Xcode project owns only the app target, assets, and entitlements. (Packaging, signing, and distribution are covered by `agent_docs/06-packaging-single-app-plan.md`.)

## 2. Core Library Prerequisites (do these first, in the SwiftPM package)

Small Core additions the GUI needs. Each follows AGENTS.md rules (reusable behavior in Core, tests with each change).

**CORE-1 — In-process progress callback.** Pipelines currently report per-asset progress only via the JSONL log file and logger records. Tailing a file from the GUI is fragile. Add an optional `@Sendable (ProgressRecord) -> Void` progress hook to `AnalyzePipeline` (and the normalization/export pipelines' per-target loops), invoked after each asset completes, alongside — not replacing — the existing log writes. Default `nil` keeps CLI behavior identical.
*Acceptance:* new unit test proves the hook fires once per asset with the same record appended to the log; `swift test` passes; CLI output unchanged.

**CORE-2 — Artifact-write audit for GUI mode.** `XMPExportPipeline.runResolvedInputs` already accepts `writesBatchArtifacts: Bool`. Audit `AnalyzePipeline` and `NormalizePipeline` for an equivalent switch so the GUI can keep progress/report state in its database without scattering `*-progress-*.jsonl` files into user folders. If missing, add the same opt-out, defaulting to current behavior.
*Acceptance:* GUI-mode run writes `.ai.json` sidecars but no batch artifacts; CLI defaults unchanged; regression tests for both settings.

**CORE-3 — Pause/resume clarification (no Core change expected).** FR4-010 requires pause/resume. `InterruptionMonitor` supports graceful *stop*; "pause" is a GUI-level job-queue concern: run work in bounded slices (e.g., N assets per pipeline invocation) and simply not schedule the next slice while paused. Verify slicing works: an `AnalyzePipeline.run` over an explicit file list of N assets must be resumable by calling again with the remaining list (`--existing skip` semantics already support this). Document the pattern in the GUI job engine.
*Acceptance:* a written design note in the GUI target plus an integration test running two slices back-to-back with identical results to one full run.

## 3. Milestones

### M0 — App scaffold and decision records

- Create the Xcode project with the SwiftUI app target (macOS 15), local package dependency on `AISidecarCore`, and hardened-runtime build settings. No sandbox in the MVP development builds (final decision in the packaging plan).
- App launches to an empty main window with an About box showing the app version and the `AISidecarCore` engine/writer versions (pull from the same constants the CLI uses).
- Add a `SidecarTagger/AGENTS.md` stub pointing agents at this plan and the requirements doc.
- **Done when:** app builds and runs from a clean checkout with `xcodebuild -scheme SidecarTagger build`; `swift test` still passes for the package.

### M1 — SQLite data layer and schema v1 (FR4-003, FR4-004, NFR4-004, NFR4-007)

- Thin wrapper over the system SQLite3 C API (no third-party ORM): connection actor, typed statement helpers, migration runner.
- Schema v1 tables (from FR4-004): `assets`, `source_identities`, `sidecar_snapshots` (content hash, mtime, parse state, `XMPMetadataSnapshot` blob, `XMPUnmanagedContentFingerprint` blob, engine/recipe versions — Section 0 item 4), `derivatives`, `model_runs`, `tag_candidates`, `tag_reviews` (approved/rejected/deferred), `vocabulary_entries`, `normalization_sessions`, `export_actions`, `review_actions`, `external_change_events`, `backups`, `validation_results`, and `schema_meta` (version).
- Store Core's `Codable` documents as JSON blobs in the columns above rather than exploding every field into columns; index only what the UI filters on (asset path, state, error code, session id).
- Migration policy per NFR4-007: forward migrations automatic, newer-schema refusal with clear message, destructive migration only after a completed file-level backup of the DB.
- Every asset state change is one transaction (NFR4-004).
- **Done when:** unit tests cover round-tripping each stored Core type, migration forward from an empty v0 file, and newer-version refusal (AC4-015).

### M2 — Folder import and asset queue (FR4-007, FR4-011, AC4-001)

- Folder picker (multi-select), security-scoped access if sandboxed later; always pass absolute paths into Core.
- Scan via `ImageScanner`, create asset rows, compute `SourceIdentity` off the main actor, honor same-base-name grouping metadata for later export.
- Implement the FR4-011 state machine exactly (the 13 listed states) as a DB-backed enum; failed states carry `SidecarError` code + message and are filterable by code.
- Queue list UI: virtualized table with state, filename, error-code filter.
- **Done when:** importing a mixed RAW/JPEG folder produces asset rows in `discovered` → `source verified` states with progress shown, and re-import is idempotent.

### M3 — Thumbnails and previews (FR4-013, FR4-014, FR4-039 groundwork)

- Reuse the derivative cache (`DerivativeCache`, `ImageRenderer`) for preview derivatives; persist thumbnail references in the DB.
- Grid view virtualization (LazyVGrid or NSCollectionView interop) with lazy full-preview loading.
- Subject-isolated derivative display when available, with instance count and selected-instance indication (FR4-014).
- **Done when:** a 5,000-asset synthetic session (script to fabricate DB rows + tiny thumbnails) scrolls and filters without perceptible stalls (AC4-014 groundwork; final verification in M11).

### M4 — Analysis job engine (FR4-008, FR4-009, FR4-010, AC4-002)

- Preflight screen: endpoint + model tag selection defaulting to the project default, validated through `OllamaVisionRunner.prepare()`; record model digest (FR4-009). Show actionable guidance when Ollama is unreachable (mirror README troubleshooting).
- Job engine: a single serialized job queue actor that runs pipeline slices in background tasks; start/pause/resume/cancel (FR4-010) via slicing (CORE-3) + `InterruptionMonitor`.
- Wire CORE-1 progress hooks to DB state transitions and UI updates; keep XMP-parse/hash work off the main actor (FR4-006c, NFR4-003).
- Mode selection: whole image / subject isolated / both (FR4-008).
- **Done when:** the user can run analysis on an imported folder, watch per-asset state advance, cancel mid-batch, relaunch the app, and see consistent state (AC4-012 groundwork).

### M5 — Candidate review UI (FR4-013–FR4-020a, AC4-003, AC4-004)

- Review screen: full image + isolated derivative, candidate list showing flat keyword, hierarchical keyword, confidence band, evidence, alternatives, vocabulary match, normalization rule, review requirement, provenance, and producing source (FR4-015/016).
- Approve / reject / edit / defer per candidate; batch approve/reject (FR4-017/018); all writes as DB transactions.
- Scoped batch correction with explicit confirmation, limited to computable scopes only (FR4-019 — no "visually similar").
- `requires_review` vocabulary policy surfaced, not reimplemented (FR4-020).
- Externally-removed keywords render as such and need explicit confirmation to re-add (FR4-020a; detection arrives in M8 — model the state now).
- **Done when:** AC4-004 walkthrough passes on a real analyzed folder.

### M6 — Vocabulary editor (FR4-021–FR4-025, AC4-005)

- Editor over the Phase 3 vocabulary JSON format using Core's `VocabularyLoader`/`VocabularyValidator`; integrity violations shown inline at edit time, not only on save (FR4-021).
- Add/edit/delete/import/export; export writes a valid Phase 3 vocabulary file with fresh content hash (FR4-022). Synonym collision detection live (FR4-023). `requires_review` and auto-approval eligibility toggles (FR4-024/025).
- **Done when:** AC4-005 passes, including a deliberately invalid edit being caught inline.

### M7 — Normalization review (FR4-026, FR4-027, FR4-027a/b, AC4-006, AC4-016)

- Run `NormalizePipeline.runSessionOnly`/`runDryRun` against reviewed candidates; persist the session document; render per-decision governing rule and provenance (FR4-026).
- Conflict view: conflicting observations and why a tag did or didn't propagate (FR4-027); visually distinguish raw vs canonicalized vs propagated vs user-context tags (FR4-027a); hierarchical display only from `canonical_path` (FR4-027b).
- Import an existing normalization session file and continue review (FR4-012b, AC4-016).
- **Done when:** AC4-006 and AC4-016 pass.

### M8 — Sidecar snapshots and external-change detection (FR4-012a, FR4-030a–e, AC4-009, AC4-020)

- Snapshot job: for each asset's target sidecar, record content hash, mtime, parse status, managed keyword snapshot, unmanaged fingerprint, writer recipe + engine versions into `sidecar_snapshots` (FR4-030a).
- Manual "Refresh Metadata" action re-snapshots without analysis or export and highlights changed/added/deleted/malformed/missing sidecars (FR4-012a, FR4-030e, AC4-020).
- Freshness check before export: hash mismatch → re-read, rebuild snapshot/fingerprint, re-merge, mark "changed outside the app" (FR4-030b); merging against a stale snapshot is impossible by construction (FR4-030c); external deletions are never resurrected silently (FR4-030d).
- Malformed/unsupported XMP as first-class UI states with `E_XMP_PARSE_FAILED` / `E_XMP_UNSUPPORTED_RDF`, export disabled until resolved or excluded (FR4-035a).
- **Done when:** AC4-009 and AC4-020 pass using a sidecar edited by hand between sessions.

### M9 — Export, validation, and compatibility (FR4-028–FR4-038b, AC4-007, AC4-008, AC4-010, AC4-011, AC4-017, AC4-018, AC4-019)

- Dry-run first: render the change plan visually before any write (FR4-029); same-base-name groups shown with pair-scope selection (FR4-034, AC4-018).
- Export through `XMPExportPipeline` with the owned engine unchanged (FR4-028); backups, restore-on-validation-failure, and post-write validation surfaced in the export report UI (FR4-035, FR4-035b/c).
- Lightroom Classic and Capture One compatibility profiles and post-export instructions (FR4-036–FR4-038); compatibility-report view (FR4-038a).
- No external tool invocation anywhere (FR4-028a, AC4-019).
- **Done when:** the listed ACs pass, including a full round trip verified in Lightroom Classic or Capture One (release evidence pattern from `agent_docs/release-evidence/`).

### M10 — Crash resumability and session export (NFR4-004, NFR4-008, AC4-012)

- Relaunch reconstruction from DB + durable artifacts; kill-mid-batch test leaves no ambiguous asset (AC4-012).
- Export approved-tag state in the Phase 3 session-file format so the DB is never the only copy (NFR4-008).
- `apply-session` parity: an exported session must be applicable by the CLI against the same folder (AC4-013 cross-check).
- **Done when:** scripted kill/relaunch test passes repeatedly, and a GUI-exported session applies cleanly via `swift run aisidecar apply-session`.

### M11 — Scale, polish, release evidence (FR4-039, AC4-014, remaining NFRs)

- Real 5,000-image session benchmark: scrolling, filtering, selection latency; batched DB writes; profiling pass with Instruments.
- Provenance completeness audit (NFR4-005); conservative-defaults review (NFR4-006); privacy audit — nothing uploads (NFR4-001/002).
- Record release evidence following the `agent_docs/release-evidence/` pattern.
- **Done when:** every AC4-001…AC4-020 has a recorded pass or an explicit deferral note.

## 4. Suggested GUI Target Structure

```
SidecarTagger/
├── App/                 SidecarTaggerApp.swift, AppDelegate glue, DI container
├── Data/                SQLite wrapper, migrations, repositories (one per table group)
├── Jobs/                Job queue actor, pipeline slicing, InterruptionMonitor wiring, progress bridge
├── Features/
│   ├── Import/          folder picker, scan, queue list
│   ├── Review/          review screen, candidate actions, batch corrections
│   ├── Vocabulary/      editor, validation surface
│   ├── Normalization/   session run + decision inspection
│   ├── Export/          change-plan view, export runner, compatibility reports
│   └── Settings/        model/endpoint config, cache locations
└── Support/             formatting, error-code presentation, preview fixtures
```

Rules mirror AGENTS.md: anything two features share and any non-presentation logic goes to `AISidecarCore`, not `Support/`.

## 5. Testing Strategy

- Data layer and job engine: XCTest in the app target, offline, deterministic — same bar as `AISidecarCoreTests`.
- Pipeline integration: use Core's existing mock runners (`MockVisionModelRunner`, recorded-fixture replay) so GUI tests never need Ollama.
- UI: XCUITest smoke for the M2/M5/M9 golden paths only; don't chase pixel coverage.
- Every milestone ends with `swift test` (package) + app test plan green.

## 6. Out of Scope (MVP)

Everything in requirements Section 3 "shall not" and Section 12 (embedding search, OCR passes, DAM profiles, embedded metadata writing, plug-ins). Do not scaffold for these beyond what the requirements' Section 12 groundwork already implies.
