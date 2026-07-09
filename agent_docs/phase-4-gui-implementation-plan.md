# Phase 4 Implementation Plan — CupricAspect GUI MVP

Version: 0.7
Date: 2026-07-08
Requirements basis: `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md` (v0.10)
Visual design basis: `agent_docs/07-cupricaspect-gui-design.md` (v0.3) — read it before building any screen
Audience: junior engineer or Sonnet-level coding agent, one milestone at a time.

Execution order across all remaining work is owned by `agent_docs/08-post-review-hardening-plan.md` §1.1. Completed-milestone history: see the ledger below and git log.

**v0.7:** compressed completed milestones to a ledger; rescued as-built architecture notes; recorded pre-M9/M10 design decisions needed.

This plan turns the Phase 4 requirements into ordered milestones. Requirement IDs (FR4-*, NFR4-*, AC4-*) refer to the requirements doc; read the sections cited by each milestone before implementing it. Do not implement ahead of the milestone order.

## 1. Approach Summary

- **App:** `CupricAspect.app`, native SwiftUI, macOS 15 minimum (FR4-001). Two interface shells over one feature state — linear Wizard (default) and nonlinear Studio — per FR4-040/041 and design doc Sections 2, 6, 7.
- **All processing stays in `AISidecarCore`** (FR4-002). The GUI target contains presentation, state orchestration, and user interaction only — the same rule AGENTS.md applies to `AISidecarCLI`.
- **Working state is sidecar-only by default** (FR4-046): durable state lives in `.ai.json` sidecars, XMP sidecars, Phase 3 vocabulary/session files, and `config.json`; queue state is derived by rescanning; in-session review state is memory + session export ("Save session only" / "Apply Prior Session" in the design). The **SQLite database is an experimental opt-in** (FR4-047/048, milestone M10) that adds persisted review state, cross-session external-change detection, and granular resumability — accessed through a thin project-owned data layer (no ORM) when enabled.
- **Core readiness (verified 2026-07-06):** the library is already embeddable. All pipeline results and callbacks are `Sendable`; there is no `@MainActor` coupling and no direct printing in Core (the `Logger` sink is injectable, default stderr); cancellation exists via `InterruptionMonitor.requestInterruption()` with between-asset checks; pipelines accept absolute paths so the `currentDirectoryPath` fallbacks never fire. Key entry points:
  - `AnalyzePipeline.run(inputPath:configuration:interruptionMonitor:) async throws -> AnalyzeResult`
  - `NormalizePipeline.runSessionOnly/runDryRun/runWritePlan(...) throws -> NormalizePipelineResult`
  - `XMPExportPipeline.runFromJSON/runResolvedInputs(...) throws -> XMPExportPipelineResult` (supports `writesBatchArtifacts: false`)
  - `ApplySessionPipeline.run(...) throws -> ApplySessionPipelineResult`
  - `OllamaVisionRunner.prepare()` for endpoint/model preflight
- **Target structure:** a SwiftPM executable target `CupricAspectApp` (product `CupricAspect`) in the existing `Package.swift`, depending on `AISidecarCore`. One build system for library, CLI, and app: `swift build`/`swift test` cover everything from a clean checkout, and no `.xcodeproj` needs generating or maintaining (xcodegen is not part of the toolchain). During development the app runs via `swift run CupricAspect`; the `.app` bundle (Info.plist, icon, entitlements, hardened runtime) is assembled by the packaging build script — `agent_docs/06-packaging-single-app-plan.md` WI-1 changes from `xcodebuild archive` to a script-assembled bundle around the SwiftPM release binary, which its codesign/notarize steps already accommodate.

## 2. Core Library Prerequisites — ledger (all complete)

Each landed with tests per AGENTS.md rules (reusable behavior in Core). One line each: ID, what it is, where it lives.

- **CORE-1 ✅** In-process progress callback — `AnalyzePipeline.run(progressHandler:)`, invoked once per emitted record alongside the JSONL and logger writes.
- **CORE-2 ✅** Artifact-write opt-out — `AnalyzePipeline.run(writesBatchArtifacts: false)` writes sidecars but no batch progress/summary files.
- **CORE-3 ✅** Pause/resume clarification (FR4-010) — no Core change: "pause" is GUI job slicing over `InterruptionMonitor` + `--existing skip` re-run semantics.
- **CORE-4 ✅** `xmp_export` block in `.ai.json` (FR4-049) — `RawSidecarExportStamp`, stamped by `XMPExportPipeline` after successful per-target writes; never on dry runs; best-effort by design.
- **CORE-5 ✅** Discovery-only scan — `ImageScanner.inventory(inputPath:recursive:)`: listing without `SourceIdentity` hashing (the M1 lazy-identity policy); `scan` shares the same discovery pass.
- **CORE-6 ✅** Normalization decision explainer (FR4-055) — `NormalizationDecisionExplainer` + `KeywordDecisionSummary` in Core; exhaustive enum→sentence mappings.
- **CORE-7 ✅** `SessionReview` (Core, landed with M4) — applies review verdicts/edits onto a Phase 3 session document so `apply-session` writes exactly the approved set; see the as-built notes below.
- **CORE-8 ✅** `OllamaVisionRunner.listInstalledVisionTags(endpoint:)` (landed with M8a) — installed vision-model discovery, serial per invariant 15.
- **CORE-9 ✅** `ConfigFileEditor.merge` (landed with M8a) — atomic read-modify-write over the shared `config.json`, preserving unknown keys, creating file/directory when missing.
- **CLI-1 ✅** `aisidecar explain-session` (AC4-031) — read-only presentation over CORE-6: `explain-session <session.json> [--keyword] [--needs-attention] [--verbose]`.

## 3. Milestones

### Completed milestones — ledger (M0–M8a)

M1–M8 were built **sidecar-only** (FR4-046) and **Wizard-only** (FR4-040 MVP scoping), always as shell-agnostic `Features/` views so M9 (Studio) is chrome work, not feature rework. Details and per-milestone acceptance: git log.

- **M0 — Scaffold, design tokens, aperture, shell skeleton** (FR4-040/041, FR4-050) ✅ done. SwiftPM target `CupricAspectApp`; theme/aperture per doc 07 §3/§5; root shell switcher; see `Sources/CupricAspectApp/` (`DesignSystem/Theme.swift`, `DesignSystem/ApertureView.swift`, `App/`).
- **M1 — Folder import and sidecar-derived asset queue** (FR4-007, FR4-011 in-memory form, FR4-049 read side, FR4-050, AC4-001, AC4-028) ✅ done. Final behavior: **single root folder** (FR4-007 as amended v0.9), nested folders via the recursive toggle; lazy identity — the queue displays on path + size + mtime, `SourceIdentity` hashing deferred to pipelines. See `Features/Import/` (`AssetQueue.swift`, `FolderImportModel`, `Step1PhotosView`); the file→state derivation table is in the as-built notes below.
- **M2 — Analysis job engine** (FR4-008/009/010, FR4-051, AC4-002) ✅ done. Serialized job-queue actor with slice-based pause/cancel (CORE-3), CORE-1 progress wiring, FR4-051 Ollama check policy (launch / pre-run / manual only); XMP-parse/hash work kept off the main actor (FR4-006c, NFR4-003). See `Features/Run/` (`AnalysisRunModel`, Wizard Steps 2–4 views).
- **M3 — Thumbnails and previews** (FR4-013/014, FR4-039 groundwork) ✅ done. See `Features/Preview/` (`ThumbnailStore`, `AssetPreviewDetails`, `AssetPreviewSheet`) and `Features/Import/AssetGridView`; verified at 5,000 synthetic assets (`Scripts/generate-synthetic-fixture.swift`).
- **M4 — Candidate review UI and session durability** (FR4-013–FR4-020, FR4-046a, NFR4-008, AC4-003 partial, AC4-004, AC4-013, AC4-027) ✅ done. See `Features/Review/` (`ReviewModel`, `Step5ReviewView`); the review-as-session architecture (CORE-7) is in the as-built notes below. Known gap: isolated-derivative side-by-side inside review rows (AC4-003 partial; wire in M9-era polish).
- **M5 — (vacated in v0.5)** Vocabulary tooling deferred to requirements Section 12 (FR4-021–025, AC4-005); the number is kept so cross-references stay stable; there is no M5 work item.
- **M6 — Normalization Inspector** (FR4-026 amended, FR4-027/027a/b, FR4-052–055, AC4-006, AC4-016, AC4-029–031) ✅ done. Session context panel, model-free `fromJSON` runs, CORE-6 explainer table, re-run loop with stale-vocabulary hash indicator, session save/import. See `Features/Normalize/` (`NormalizationModel`, `SessionContextPanel`, `NormalizationInspectorView`).
- **M7 — Export, validation, and compatibility** (FR4-028–FR4-038b, AC4-007/008/010/011/017, AC4-018 partial, AC4-019, AC4-028) ✅ done. Every write fronted by a dry-run change plan; the Phase 2 backup/source-hash/validation/restore chain unchanged; CORE-4 stamping closes the AC4-028 loop; no external tool invocation anywhere (FR4-028a); LR/C1 compatibility notes in the plan sheet. See `Features/Export/` (`ExportModel`, `ChangePlanSheet`, `ExportReportView`, `Step3ApplyView`).
- **M8 — Sidecar-only hardening** (AC4-025) ✅ done. Kill/relaunch verified via `Scripts/m8-kill-relaunch-check.sh`; `StateHousekeeping.pruneArtifacts` bounds the state directory; relaunch-reconstruction audit passed — nothing depends on process memory alone.
- **M8a — Settings expansion and model picker** (FR4-056/057, AC4-032/033; requirements v0.8) ✅ done. See `Features/Settings/` (`SettingsModel`, `SettingsSheet`), built on CORE-8/9; replaces the M0 About sheet; Studio adopts it in M9.

### As-built architecture notes (rescued reference)

**Queue-state derivation from disk (M1; FR4-011, FR4-049).** Between-launch states derive from files only — do not invent states:

| On disk | Derived state |
|---|---|
| image only | `discovered` |
| image + `.ai.json` | `analyzed` |
| image + `.ai.json` with `xmp_export` block + target XMP present | `exported` |
| image + target XMP present, no `xmp_export` block | `XMP present (external)` |
| image + `.ai.json` with `xmp_export` block, target XMP missing | `XMP missing (was exported)` |

The remaining FR4-011 states are transient in-run states held in memory while a job runs; failed states carry `SidecarError` code + message and are filterable by code for the current session. A fresh analysis rewrites the sidecar and thereby truthfully clears a stale export stamp.

**Review-as-session (M4; CORE-7).** The durable review form is a Phase 3 session document — `SessionReview` (Core) applies verdicts as decision status + additive `user_review_rejected`/`user_review_deferred` skip reasons, and edits as additive `user_edited` candidate kind, so `apply-session` writes exactly the approved set with zero new write paths (AC4-013, proven by `testApplySessionWritesOnlyApprovedKeywords`). The review base session is built model-free via `runSessionOnly` (`fromJSON`, observed-tags + single-image). Durability: FR4-046a autosave (recovery session every 25 decisions or 5 minutes to the GUI state directory, unclean-exit restore offer on relaunch — AC4-027) plus explicit "Save session only" / session import resume (FR4-012b); a GUI-exported session applies cleanly via `swift run aisidecar apply-session` (AC4-013 cross-check).

### B0 — Beta readiness (requirements v0.9; the first beta ships from here, Wizard-only)

Status: B0-1 (minus Developer ID signing/notarization), B0-2, B0-3, B0-4, and B0-6 are done. Outstanding: B0-5 release evidence, the Developer ID signing/notarization/`spctl` pass, and the `v0.1.0-beta.1` tag — sequenced by 08 §1.1. Alongside B0, the always-on Phase 2 merge-into-existing-XMP behavior (backup-and-merge default) was verified end-to-end (CLI live round trip preserving foreign keywords, `xmp:Rating`, and a timestamped backup) and is revealed in the change-plan UI: a standing policy card, per-target merge/new-file badges with preserved-keyword counts from the dry-run preview, and footer totals.

- **B0-1 — Packaging** ✅ done except Developer ID signing/notarization (deferred until the certificate is in hand; `Scripts/build-release.sh` ad-hoc signs by default and takes `--sign <identity>` for the WI-1 steps 4–5 when ready — `spctl --assess` therefore still pending). Key fix: `AISidecarResourceBundle` in Core resolves SwiftPM's resource-relocation bug (search order `Contents/Resources` → executable-adjacent → `../Resources` → `Bundle.module`); the app carries one shared resource copy in `Contents/Resources`; proven by `Scripts/wi2-relocation-check.sh`. `Scripts/build-release.sh` assembles `dist/CupricAspect.app` (Info.plist template, committed `AppIcon.icns`, embedded CLI, version cross-check) and packs the DMG.
- **B0-2 — Single-source version** (packaging plan D5) ✅ done — `AISidecarVersion.current` ("0.1.0-beta.1") in Core feeds `aisidecar --version`, the About/Settings cards, and the build script's `CFBundleShortVersionString` injection (cross-checked at assembly). Tag timing: per 08 §1.1.
- **B0-3 — First-run / missing-runtime guidance** (FR4-058, AC4-034) ✅ done — `RuntimeGuidanceModel` (one launch-time check + manual re-check, no polling) drives the Wizard banner (unreachable → install/start guidance; no vision model → starter suggestion with copyable `ollama pull` command) and the Settings empty-picker guidance. The clean-user-account pass folds into B0-5's manual round.
- **B0-4 — Diagnostic file logging** (FR4-059, AC4-035) ✅ done — `FileLogSink` (5 MB cap, one rotated generation, `errors=E_*` readable) under `~/Library/Application Support/CupricAspect/logs/`, fed by all four pipeline loggers; path + Reveal in Settings → About; the silent `try?` on session save/import now surfaces errors in the UI and the log.

**B0-5 — Release evidence (manual, outstanding).** The Lightroom Classic / Capture One round trip per `agent_docs/release-evidence/` (write real XMP from the GUI, import in LR/C1, record results), plus the outstanding Phase 1 M9 calibration evidence or an explicit deferral note (AGENTS release-signoff requirement).
*Done when:* evidence files exist under `agent_docs/release-evidence/` for the current writer recipe.

- **B0-6 — Sharp edges** ✅ all four verified: Step 1 copy already singular ("Drop a folder of photos here"); Cancel carries resume copy ("Progress is kept… Start again to resume"); review scale measured at 1,500 synthetic assets (session build 8.5 s one-time, verdict update < 100 ms, no stalls — env-gated `ReviewScaleTests`, generator `--sidecar-template` flag); reopen-last-folder offer via UserDefaults (Reopen/dismiss, never auto-imports).

**Not in B0:** Studio (M9), the database (M10), vocabulary tooling, embedded-CLI install action (WI-3), Sparkle/auto-update, CI. Beta distribution is a signed DMG handed out directly.

The remaining pre-tag and post-beta sequence (R1 blockers → B0-5 + signing + tag → R2–R4 → M9) is owned by `agent_docs/08-post-review-hardening-plan.md` §1.1.

### M9 — Studio shell (FR4-040, FR4-041, AC4-021)

- Build the Studio chrome per design doc §7: 214px sidebar, centered window title, per-view sticky run bars; embed the existing `Features/` views (they were built shell-agnostic in M1–M8 — this milestone is chrome and navigation, not feature work).
- Enable the "Nonlinear UI" toggle (remove "coming soon"); FR4-041 state survival across shell switches; the Studio views map to the same feature state the Wizard steps use.
- **Not in this milestone:** no database anything; no new feature behavior — if a feature view needs changes to embed cleanly, that's a `Features/` refactor ticket, not Studio scope creep.
- **Done when:** AC4-021 passes (switch off→on→off with in-flight state, relaunch restores shell choice), and the M1–M8 golden-path walkthroughs pass identically in Studio.

**Decisions required before M9** (resolve and record in this doc or 07 before starting):

1. **Studio "Write XMP" view scope.** Design doc 07 §7 specifies an export-from-existing-sidecars flow with its own folder pickers (FROM RAW SIDECARS + SOURCE ROOT) that has no Wizard equivalent. Decide whether it maps onto `ExportModel`/`Step3ApplyView` or is descoped from M9's chrome-only scope. R2-6 resolved the related write-path risk by deleting `NormalizationModel.writeNormalizedXMP`; any Studio Write XMP view must compose `ExportModel` and keep every write behind its dry-run change-plan gate.
2. **Studio view→model mapping table.** Author a table mapping each Studio view (`analyze`, `normalize`, `write`, `apply`, `settings`, `processing`, `results`) to the `Features/` model/view it embeds, before any chrome is built.
3. **Stage log well.** The mapping from `ProgressRecord` (CORE-1) to the Studio processing view's stage-log-well lines (scan/render/model/writing, per 07 §7 and resolution 8) is unspecified — define it.
4. **"Apply Prior Session" stats copy.** Design doc 07 (line ~245) shows "{N} images · {K} keyword decisions · {m} merges · {d} drops" — merge/drop decisions do not exist in the engine (07 resolution 10), so {m}/{d} cannot be populated. Replacement copy needed.

### M10 — Experimental database mode (FR4-003–FR4-005, FR4-004a–c, FR4-011 persisted, FR4-012a, FR4-020a, FR4-030a–e, NFR4-004, NFR4-007, AC4-009, AC4-012, AC4-015, AC4-020, AC4-023, AC4-024, AC4-026)

Everything database-backed lands here, behind Settings → Advanced → "Working database (experimental)" (FR4-047; design doc Settings spec). Implement as three sequential sub-milestones — each independently landable with `swift test` green:

**Decisions required before M10a** (design notes to write first): the column-level schema (the table list below names tables, not columns) and a repository API sketch; and — critically — the enable-time transition: seeding the persisted FR4-011 state machine from the file-derived states, the DB↔disk reconciliation procedure (FR4-005 requires reconciliation before export, but no procedure exists anywhere), and disable/re-enable semantics beyond AC4-026's keep-or-delete offer.

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

- Real 5,000-image session benchmark in **both modes**: scrolling, filtering, selection latency; batched DB writes when enabled; profiling pass with Instruments. Define the target hardware for these numbers before measuring.
- Retention at scale (database mode): prune + vacuum measured on the 5,000-image session with no main-actor stalls; AC4-024 verified against a session with events aged past the window.
- Provenance completeness audit (NFR4-005); conservative-defaults review (NFR4-006); privacy audit — nothing uploads (NFR4-001/002).
- Absorb doc 08's parked M11-scope items (see 08 §6 and R2-5): the two-instance file-coordination decision (single-instance lock vs. beyond the R2-7 known-issues note), the `AssetQueue.hasXMPExportBlock` partial-decode measurement at 5,000 assets, and the benchmark-harness nits (median bias, missing `failed_sidecar_count`, child-exit-code flagging).
- Wire XCUITest smoke for the M1 import / M4 review / M7 export golden paths — the app-bundle prerequisite it was deferred on now exists (B0-1 packaging script).
- Record release evidence following the `agent_docs/release-evidence/` pattern.
- **Done when:** every AC4-001…AC4-028 has a recorded pass or an explicit deferral note (database-mode ACs recorded with the toggle on).

## 4. GUI Target Structure

As built (M0–M8a); `Data/` and `Jobs/` do not exist yet:

```
Sources/CupricAspectApp/
├── App/                 CupricAspectApp.swift (@main), root shell switcher, DI container
├── DesignSystem/        Theme.swift (tokens, doc 07 §3), ApertureView.swift (§5),
│                        shared styled controls (segmented, chips, cards)
├── Shells/              flat: WizardShellView.swift (step rail, footer nav, doc 07 §6),
│                        StudioShellView.swift (M9 fills in the sidebar + views, doc 07 §7)
├── Features/            shell-agnostic feature views/state both shells embed
│   ├── Import/          folder picker, scan, queue derivation, list/grid
│   ├── Run/             analysis job engine, options, working/summary views
│   ├── Preview/         thumbnail store, preview sheet
│   ├── Review/          review screen, candidate actions, autosave/recovery
│   ├── Normalize/       session context panel, inspector, re-run loop
│   ├── Export/          change-plan sheet, export runner, report, apply-session
│   └── Settings/        model/endpoint config, defaults, appearance, about
├── Data/                (future, M10) SQLite wrapper, migrations, repositories
├── Jobs/                (future, M9/M10 refactor if warranted) — the job-queue actor
│                        currently lives in Features/Run/AnalysisRunModel
└── Support/             formatting, error-code presentation, preview fixtures
```

Shells are thin: layout, navigation, and chrome only. Feature views and their observable state live in `Features/` and are embedded by both shells (FR4-041 state survival falls out of this). Rules mirror AGENTS.md: anything two features share and any non-presentation logic goes to `AISidecarCore`, not `Support/`. (`Vocabulary/` returns under `Features/` only if requirements Section 12 tooling lands.)

## 5. Testing Strategy

- Data layer and job engine: XCTest in a `CupricAspectAppTests` SwiftPM test target, offline, deterministic — same bar as `AISidecarCoreTests`; runs under plain `swift test`.
- Pipeline integration: use Core's existing mock runners (`MockVisionModelRunner`, recorded-fixture replay) so GUI tests never need Ollama.
- UI: XCUITest smoke for the M1 import, M4 review, and M7 export golden paths only; don't chase pixel coverage. The app-bundle prerequisite it was deferred on is now met (B0-1's `Scripts/build-release.sh`); wiring is scheduled in M11 — manual golden-path walkthroughs remain the interim bar.
- Every milestone ends with `swift test` green and `swift build --product CupricAspect` succeeding.

## 6. Out of Scope (MVP)

Everything in requirements Section 3 "shall not" and Section 12 (embedding search, OCR passes, DAM profiles, embedded metadata writing, plug-ins). Do not scaffold for these beyond what the requirements' Section 12 groundwork already implies.
