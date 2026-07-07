# Phase 4 Implementation Plan — CupricAspect GUI MVP

Version: 0.3
Date: 2026-07-06
Requirements basis: `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md` (v0.5)
Visual design basis: `agent_docs/07-cupricaspect-gui-design.md` (v0.1) — read it before building any screen
Audience: junior engineer or Sonnet-level coding agent, one milestone at a time.

**v0.3 changes:** storage modes (requirements v0.5, FR4-046–048) — sidecar-only is the default; the SQLite working database is an experimental opt-in. Milestones reordered accordingly: the feature flow (import → analyze → review → normalize → export) ships first entirely on files the CLI understands, and the whole database layer (schema, snapshots, external-change detection, retention) is now one late milestone, M9, behind the Settings → Advanced toggle.

**v0.2 changes:** app renamed `CupricAspect` (design decision, requirements v0.4); the GUI target is a SwiftPM executable target in `Package.swift`, not a separate Xcode project (rationale in Section 1); M0 rewritten and completed — it now includes the design-token theme, the aperture component, and the dual-shell skeleton; feature milestones must render with the design system from doc 07.

This plan turns the Phase 4 requirements into ordered milestones. Requirement IDs (FR4-*, NFR4-*, AC4-*) refer to the requirements doc; read the sections cited by each milestone before implementing it. Do not implement ahead of the milestone order.

## 1. Approach Summary

- **App:** `CupricAspect.app`, native SwiftUI, macOS 15 minimum (FR4-001). Two interface shells over one feature state — linear Wizard (default) and nonlinear Studio — per FR4-040/041 and design doc Sections 2, 6, 7.
- **All processing stays in `AISidecarCore`** (FR4-002). The GUI target contains presentation, state orchestration, and user interaction only — the same rule AGENTS.md applies to `AISidecarCLI`.
- **Working state is sidecar-only by default** (FR4-046): durable state lives in `.ai.json` sidecars, XMP sidecars, Phase 3 vocabulary/session files, and `config.json`; queue state is derived by rescanning; in-session review state is memory + session export ("Save session only" / "Apply Prior Session" in the design). The **SQLite database is an experimental opt-in** (FR4-047/048, milestone M9) that adds persisted review state, cross-session external-change detection, and granular resumability — accessed through a thin project-owned data layer (no ORM) when enabled.
- **Core readiness (verified 2026-07-06):** the library is already embeddable. All pipeline results and callbacks are `Sendable`; there is no `@MainActor` coupling and no direct printing in Core (the `Logger` sink is injectable, default stderr); cancellation exists via `InterruptionMonitor.requestInterruption()` with between-asset checks; pipelines accept absolute paths so the `currentDirectoryPath` fallbacks never fire. Key entry points:
  - `AnalyzePipeline.run(inputPath:configuration:interruptionMonitor:) async throws -> AnalyzeResult`
  - `NormalizePipeline.runSessionOnly/runDryRun/runWritePlan(...) throws -> NormalizePipelineResult`
  - `XMPExportPipeline.runFromJSON/runResolvedInputs(...) throws -> XMPExportPipelineResult` (supports `writesBatchArtifacts: false`)
  - `ApplySessionPipeline.run(...) throws -> ApplySessionPipelineResult`
  - `OllamaVisionRunner.prepare()` for endpoint/model preflight
- **Target structure:** a SwiftPM executable target `CupricAspectApp` (product `CupricAspect`) in the existing `Package.swift`, depending on `AISidecarCore`. One build system for library, CLI, and app: `swift build`/`swift test` cover everything from a clean checkout, and no `.xcodeproj` needs generating or maintaining (xcodegen is not part of the toolchain). During development the app runs via `swift run CupricAspect`; the `.app` bundle (Info.plist, icon, entitlements, hardened runtime) is assembled by the packaging build script — `agent_docs/06-packaging-single-app-plan.md` WI-1 changes from `xcodebuild archive` to a script-assembled bundle around the SwiftPM release binary, which its codesign/notarize steps already accommodate.

## 2. Core Library Prerequisites (do these first, in the SwiftPM package)

Small Core additions the GUI needs. Each follows AGENTS.md rules (reusable behavior in Core, tests with each change).

**CORE-1 — In-process progress callback.** Pipelines currently report per-asset progress only via the JSONL log file and logger records. Tailing a file from the GUI is fragile. Add an optional `@Sendable (ProgressRecord) -> Void` progress hook to `AnalyzePipeline` (and the normalization/export pipelines' per-target loops), invoked after each asset completes, alongside — not replacing — the existing log writes. Default `nil` keeps CLI behavior identical.
*Acceptance:* new unit test proves the hook fires once per asset with the same record appended to the log; `swift test` passes; CLI output unchanged.

**CORE-2 — Artifact-write audit for GUI mode.** `XMPExportPipeline.runResolvedInputs` already accepts `writesBatchArtifacts: Bool`. Audit `AnalyzePipeline` and `NormalizePipeline` for an equivalent switch so the GUI can keep progress/report state in its database without scattering `*-progress-*.jsonl` files into user folders. If missing, add the same opt-out, defaulting to current behavior.
*Acceptance:* GUI-mode run writes `.ai.json` sidecars but no batch artifacts; CLI defaults unchanged; regression tests for both settings.

**CORE-3 — Pause/resume clarification (no Core change expected).** FR4-010 requires pause/resume. `InterruptionMonitor` supports graceful *stop*; "pause" is a GUI-level job-queue concern: run work in bounded slices (e.g., N assets per pipeline invocation) and simply not schedule the next slice while paused. Verify slicing works: an `AnalyzePipeline.run` over an explicit file list of N assets must be resumable by calling again with the remaining list (`--existing skip` semantics already support this). Document the pattern in the GUI job engine.
*Acceptance:* a written design note in the GUI target plus an integration test running two slices back-to-back with identical results to one full run.

## 3. Milestones

### M0 — App scaffold, design tokens, aperture, shell skeleton ✅ (completed 2026-07-06)

- Add the `CupricAspectApp` executable target (product `CupricAspect`) to `Package.swift`, macOS 15, depending on `AISidecarCore`. No sandbox in MVP development builds (final decision in the packaging plan).
- Implement the design-token theme from design doc Section 3 (`Theme.swift`): light/dark palettes, the three accent palettes with per-theme variants, resolved theme/accent published to the environment; theme (`light`/`dark`/`auto`) and accent persisted via `@AppStorage`; Auto follows the system appearance live.
- Implement `ApertureView` per design doc Section 5 (`TimelineView` + `Canvas`): idle-open, running breathing cycle + spin, static under reduce-motion.
- Root shell switcher per FR4-040/041: `@AppStorage("cupricaspect.nonlinear")` selects Wizard or Studio placeholder shells; both render the 46px title-bar styling, branding, and an About surface showing the app version and Core engine/writer versions (`OwnedXMPSidecarEngine.engineVersion`, `.writerRecipeVersion`).
- Add a `Sources/CupricAspectApp/AGENTS.md` stub pointing agents at this plan, the requirements doc, and design doc 07.
- **Done when:** `swift build --product CupricAspect` and `swift run CupricAspect` work from a clean checkout (window shows branding, theme/accent/shell toggles function); `swift test` still passes for the package.

*Status: implemented — see `Sources/CupricAspectApp/`. Subsequent milestones replace the placeholder shell content with real features, styled per design doc 07.*

Milestones M1–M8 are **sidecar-only** (FR4-046): they must not create or read a database. M9 adds the experimental database mode behind the Settings → Advanced toggle. M10 closes out scale and release evidence for both modes.

### M1 — Folder import and asset queue, sidecar-derived (FR4-007, FR4-011 in-memory form, AC4-001)

- Folder picker (multi-select), security-scoped access if sandboxed later; always pass absolute paths into Core.
- Scan via `ImageScanner`, compute `SourceIdentity` off the main actor, honor same-base-name grouping metadata for later export.
- In-memory asset queue observable. Between-launch states are derived from files on disk: `discovered` (image present), `analyzed` (`.ai.json` present), `exported` (target `.xmp` present); the remaining FR4-011 states are transient in-run states held in memory while a job runs. Failed states carry `SidecarError` code + message and are filterable by code for the current session.
- Queue list UI: virtualized table with state, filename, error-code filter.
- **Done when:** importing a mixed RAW/JPEG folder shows scan progress and a populated queue; re-import is idempotent; relaunching rebuilds the same queue from disk; no database file exists (AC4-025 groundwork).

### M2 — Analysis job engine (FR4-008, FR4-009, FR4-010, AC4-002)

- Preflight: endpoint + model tag selection defaulting to the project default, validated through `OllamaVisionRunner.prepare()`; record model digest (FR4-009). Show actionable guidance when Ollama is unreachable (mirror README troubleshooting).
- Job engine: a single serialized job queue actor that runs pipeline slices in background tasks; start/pause/resume/cancel (FR4-010) via slicing (CORE-3) + `InterruptionMonitor`.
- Wire CORE-1 progress hooks to in-memory queue state and UI updates (the Working screens' progress, current file, rate); keep XMP-parse/hash work off the main actor (FR4-006c, NFR4-003).
- Mode selection: whole image / subject isolated / both (FR4-008).
- Interrupted runs resume naturally on the next run via `--existing skip` semantics over the files already written.
- **Done when:** the user can run analysis on an imported folder, watch per-asset state advance, cancel mid-batch, relaunch, re-run, and end with the same set of `.ai.json` files a single uninterrupted run produces.

### M3 — Thumbnails and previews (FR4-013, FR4-014, FR4-039 groundwork)

- Reuse the derivative cache (`DerivativeCache`, `ImageRenderer`) for preview derivatives; keep an in-memory thumbnail index over the shared cache (no DB).
- Grid view virtualization (LazyVGrid or NSCollectionView interop) with lazy full-preview loading.
- Subject-isolated derivative display when available, with instance count and selected-instance indication (FR4-014).
- **Done when:** a 5,000-asset synthetic folder (script fabricates tiny images + `.ai.json` sidecars) scrolls and filters without perceptible stalls (AC4-014 groundwork; final verification in M10).

### M4 — Candidate review UI and session durability (FR4-013–FR4-020, NFR4-008, AC4-003, AC4-004)

- Review screen: full image + isolated derivative, candidate list showing flat keyword, hierarchical keyword, confidence band, evidence, alternatives, vocabulary match, normalization rule, review requirement, provenance, and producing source (FR4-015/016).
- Approve / reject / edit / defer per candidate; batch approve/reject (FR4-017/018) — all in-memory review state.
- "Save session only" exports the review state in the Phase 3 session-file format (NFR4-008); "Apply Prior Session" / session import resumes it (FR4-012b). `apply-session` parity: a GUI-exported session applies cleanly via `swift run aisidecar apply-session` (AC4-013 cross-check).
- Scoped batch correction with explicit confirmation, limited to computable scopes only (FR4-019 — no "visually similar").
- `requires_review` vocabulary policy surfaced, not reimplemented (FR4-020). (FR4-020a external-removal rendering is database-mode — arrives in M9.)
- **Done when:** AC4-004 walkthrough passes on a real analyzed folder, and an export → quit → relaunch → import round trip restores the review exactly.

### M5 — Vocabulary editor (FR4-021–FR4-025, AC4-005)

- Editor over the Phase 3 vocabulary JSON format using Core's `VocabularyLoader`/`VocabularyValidator`; integrity violations shown inline at edit time, not only on save (FR4-021).
- Add/edit/delete/import/export; export writes a valid Phase 3 vocabulary file with fresh content hash (FR4-022). Synonym collision detection live (FR4-023). `requires_review` and auto-approval eligibility toggles (FR4-024/025).
- **Done when:** AC4-005 passes, including a deliberately invalid edit being caught inline.

### M6 — Normalization review (FR4-026, FR4-027, FR4-027a/b, AC4-006, AC4-016)

- Run `NormalizePipeline.runSessionOnly`/`runDryRun` against reviewed candidates; persist the session document as a file; render per-decision governing rule and provenance (FR4-026).
- Conflict view: conflicting observations and why a tag did or didn't propagate (FR4-027); visually distinguish raw vs canonicalized vs propagated vs user-context tags (FR4-027a); hierarchical display only from `canonical_path` (FR4-027b).
- Import an existing normalization session file and continue review (FR4-012b, AC4-016).
- **Done when:** AC4-006 and AC4-016 pass.

### M7 — Export, validation, and compatibility (FR4-028–FR4-038b, AC4-007, AC4-008, AC4-010, AC4-011, AC4-017, AC4-018, AC4-019)

- Dry-run first: render the change plan visually before any write (FR4-029); same-base-name groups shown with pair-scope selection (FR4-034, AC4-018).
- Export through `XMPExportPipeline` with the owned engine unchanged (FR4-028); backups, restore-on-validation-failure, and post-write validation surfaced in the export report UI (FR4-035, FR4-035b/c). Export always re-reads and semantically merges against current sidecar content (Phase 2 behavior), so out-of-band edits are honored even without change *detection*; the FR4-048 limitation disclosure appears here.
- Malformed/unsupported XMP as first-class UI states with `E_XMP_PARSE_FAILED` / `E_XMP_UNSUPPORTED_RDF`, export disabled until resolved or excluded (FR4-035a).
- Lightroom Classic and Capture One compatibility profiles and post-export instructions (FR4-036–FR4-038); compatibility-report view (FR4-038a).
- No external tool invocation anywhere (FR4-028a, AC4-019).
- **Done when:** the listed ACs pass, including a full round trip verified in Lightroom Classic or Capture One (release evidence pattern from `agent_docs/release-evidence/`), plus AC4-025 end-to-end (still no database file).

### M8 — Sidecar-only hardening (AC4-025, crash behavior)

- Kill-mid-batch testing: scripted kill/relaunch during analyze and export leaves no ambiguous file state (partial writes are the pipelines' existing temp-file/rename discipline; verify from the GUI paths).
- Relaunch reconstruction review: every screen's state either rebuilds from disk or is explicitly session-scoped and marked as such.
- **Done when:** AC4-025 passes end-to-end repeatedly, including kill/relaunch variants.

### M9 — Experimental database mode (FR4-003–FR4-005, FR4-004a–c, FR4-011 persisted, FR4-012, FR4-012a, FR4-020a, FR4-030a–e, NFR4-004, NFR4-007, AC4-009, AC4-012, AC4-015, AC4-020, AC4-023, AC4-024, AC4-026)

Everything database-backed lands here, behind Settings → Advanced → "Working database (experimental)" (FR4-047; design doc Settings spec):

- Thin wrapper over the system SQLite3 C API (no third-party ORM): connection actor, typed statement helpers, migration runner. Database file under `~/Library/Application Support/CupricAspect/` — never in the app bundle.
- Schema v1 tables (from FR4-004): `assets`, `source_identities`, `sidecar_snapshots` (content hash, mtime, parse state, `XMPMetadataSnapshot` blob, `XMPUnmanagedContentFingerprint` blob, engine/recipe versions), `derivatives`, `model_runs`, `tag_candidates`, `tag_reviews`, `vocabulary_entries`, `normalization_sessions`, `export_actions`, `review_actions`, `external_change_events`, `backups`, `validation_results`, `schema_meta`. Core `Codable` documents stored as JSON blobs; index only what the UI filters on.
- Migration policy per NFR4-007; every asset state change one transaction (NFR4-004); persisted FR4-011 state machine replaces the in-memory derivation when enabled.
- Sidecar snapshots + external-change detection (FR4-030a–e): snapshot job, manual "Refresh Metadata" (FR4-012a, AC4-020), pre-export freshness check, non-resurrection (FR4-020a) — the M4 review UI gains the externally-removed rendering.
- Retention (FR4-004a–c): forget-folder (one transaction, export-or-confirm gate, "Forget folder…" in the queue UI), age-based prune with change-detection exemptions, post-delete `VACUUM` off the main actor; Settings exposes the retention window (default 180 days).
- Enable/disable flows per FR4-047 and AC4-026, including the keep-or-delete offer on disable.
- **Done when:** the listed ACs pass with the toggle on, AC4-025 still passes with it off, and switching modes never touches sidecar/session/vocabulary files.

### M10 — Scale, polish, release evidence (FR4-039, AC4-014, remaining NFRs)

- Real 5,000-image session benchmark in **both modes**: scrolling, filtering, selection latency; batched DB writes when enabled; profiling pass with Instruments.
- Retention at scale (database mode): prune + vacuum measured on the 5,000-image session with no main-actor stalls; AC4-024 verified against a session with events aged past the window.
- Provenance completeness audit (NFR4-005); conservative-defaults review (NFR4-006); privacy audit — nothing uploads (NFR4-001/002).
- Record release evidence following the `agent_docs/release-evidence/` pattern.
- **Done when:** every AC4-001…AC4-026 has a recorded pass or an explicit deferral note (database-mode ACs recorded with the toggle on).

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
│   ├── Vocabulary/      editor, validation surface
│   ├── Normalization/   session run + decision inspection
│   ├── Export/          change-plan view, export runner, compatibility reports
│   └── Settings/        model/endpoint config, cache locations, appearance, shell toggle
└── Support/             formatting, error-code presentation, preview fixtures
```

Shells are thin: layout, navigation, and chrome only. Feature views and their observable state live in `Features/` and are embedded by both shells (FR4-041 state survival falls out of this). Rules mirror AGENTS.md: anything two features share and any non-presentation logic goes to `AISidecarCore`, not `Support/`.

## 5. Testing Strategy

- Data layer and job engine: XCTest in a `CupricAspectAppTests` SwiftPM test target, offline, deterministic — same bar as `AISidecarCoreTests`; runs under plain `swift test`.
- Pipeline integration: use Core's existing mock runners (`MockVisionModelRunner`, recorded-fixture replay) so GUI tests never need Ollama.
- UI: XCUITest smoke for the M2/M5/M9 golden paths only; don't chase pixel coverage. (XCUITest needs an app bundle — defer wiring it until the packaging script exists; manual golden-path walkthroughs are the interim bar.)
- Every milestone ends with `swift test` green and `swift build --product CupricAspect` succeeding.

## 6. Out of Scope (MVP)

Everything in requirements Section 3 "shall not" and Section 12 (embedding search, OCR passes, DAM profiles, embedded metadata writing, plug-ins). Do not scaffold for these beyond what the requirements' Section 12 groundwork already implies.
