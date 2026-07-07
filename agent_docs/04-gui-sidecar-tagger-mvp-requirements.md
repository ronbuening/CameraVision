# Phase 4 Requirements - GUI Sidecar Tagger MVP

Version: 0.5
Date: 2026-07-06
Supersedes: 0.4
Builds on: Phase 1 Requirements v0.4, Phase 2 Requirements v0.5, Phase 3 Requirements v0.4
App name: `CupricAspect.app` (resolves the former working name `SidecarTagger.app`)
Visual design basis: `agent_docs/07-cupricaspect-gui-design.md`
Core library: `AISidecarCore` (shared with the `aisidecar` CLI by construction, per PW-002)
Minimum deployment target: macOS 15
Default vision model: `gemma4:26b-a4b-it-qat`
Primary output artifact: reviewed XMP sidecar files, with a local working database

This document inherits the Project-Wide Conventions of the Phase 1 requirements and the owned-XMP export/normalization behavior of Phases 2 and 3. They are not restated except where Phase 4 narrows or clarifies their GUI use.

## 0. Changes from v0.4 — storage modes

This revision makes **sidecar-only** the default storage mode and demotes the SQLite working database to an experimental opt-in.

1. FR4-046: by default the GUI keeps all durable state in files the CLI already understands — `.ai.json` raw sidecars, XMP sidecars, Phase 3 vocabulary and normalization-session files, and `config.json`. Review state is in-memory for the session; durability comes from session export/import (NFR4-008, the design's "Save session only" and "Apply Prior Session"). No database file is created or opened.
2. FR4-047: the SQLite working database becomes an experimental option at Settings → Advanced → "Working database (experimental)", stored under `~/Library/Application Support/CupricAspect/` — never inside the app bundle.
3. FR4-048 scopes existing requirements by mode: the database-backed guarantees (persisted queue state, cross-session external-change detection and non-resurrection, provenance-driven reprocessing across sessions, transactional crash resumability, retention policy) apply only when database mode is enabled, and the sidecar-only limitations must be disclosed in the UI where they matter.
4. Rationale: the file-based methodology is the proven, transparent core of the project — every artifact is inspectable and CLI-interoperable, and the GUI defaults to it. The database earns its way in as an enhancement once its value is demonstrated, rather than being a structural prerequisite.

## 0.1 Changes from v0.3 — design adoption (retained)

This revision adopts the CupricAspect visual design (Claude Design handoff bundle at `agent_docs/gui-wrapper-for-cameravision/`, extracted into `agent_docs/07-cupricaspect-gui-design.md`).

1. The application is named **CupricAspect**. Wherever this document or the packaging plan says `SidecarTagger.app`, read `CupricAspect.app`. The GUI-only state directory becomes `~/Library/Application Support/CupricAspect/`. Shared `aisidecar` config and derivative-cache paths are unchanged.
2. New interface-shell and appearance requirements FR4-040 through FR4-045 (Section 13): dual Wizard/Studio shells, theme and accent system, the aperture brand/progress component, and reduce-motion behavior.
3. Where the design prototypes and this document diverge, the resolutions in design doc Section 8.2 are binding — notably the existing-sidecar control is Skip/Overwrite/Fail (Core `ExistingPolicy`) in both shells, and every prototype count, rate, filename, and thumbnail is sample data to be replaced by real pipeline state.
4. The design prototypes cover the primary happy-path surfaces only. All other surfaces required by this document (asset queue and state machine, vocabulary editor, external-change and malformed-XMP states, dry-run change plans, compatibility reports) remain required and shall be built with the same design tokens (design doc Section 8.3).
5. Data-retention requirements FR4-004a–c and AC4-023/024 (added in this revision): per-folder forget, age-based pruning of the append-only history tables with change-detection records exempt, and post-deletion compaction. The working database is intentionally append-heavy — provenance-driven reprocessing (FR4-012) and external-change memory (FR4-020a, FR4-030a–e) require history — so growth is bounded by explicit policy rather than left unbounded.

## 0.2 Changes from v0.2 (retained)

This revision updates Phase 4 for the Phase 2/3 decision to use a project-owned XMP sidecar engine instead of ExifTool.

1. The GUI now uses `MetadataWriteEngine` with the required `OwnedXMPSidecarEngine` implementation. It shall not require, invoke, package, or surface ExifTool as part of runtime export.
2. ExifTool validation is removed from acceptance. Export validation is performed by the owned XMP parser, `XMPMetadataSnapshot`, and `XMPUnmanagedContentFingerprint`, with Lightroom Classic and Capture One smoke checks retained as release evidence.
3. Existing sidecar preservation is semantic, not byte-for-byte. The GUI shall not promise preservation of whitespace, namespace-prefix order, attribute order, or original XML formatting.
4. Sidecar snapshots stored in SQLite now include content hash, mtime, owned-parser metadata snapshot, unmanaged-content fingerprint, managed keyword snapshot, XMP parse state, engine version, and writer recipe version.
5. Out-of-band sidecar edits are re-merged against the current sidecar using the owned parser. If a keyword was removed outside the app after the last export, it shall not be resurrected without explicit user confirmation.
6. Malformed or unsupported existing XMP is a first-class UI state. The GUI must display `E_XMP_PARSE_FAILED` and `E_XMP_UNSUPPORTED_RDF`, prevent ambiguous writes, and leave source images and sidecars unchanged.
7. The former future item "native XMP write engine replacing ExifTool" is removed because the owned XMP engine is now the required foundation.
8. The GUI shall expose owned-XMP diagnostics at a user-appropriate level: validation status, backup/restoration status, external-change status, and safe failure codes, not raw sidecar contents.

For continuity, all substantive v0.2 changes remain active: out-of-band sidecar edit detection, versioned SQLite schema, scoped batch correction, 5,000-image responsiveness target, crash-resumability through transactions and pipeline artifacts, direct surfacing of structured error codes, SwiftUI on macOS 15, and a thin owned SQLite data layer.

## 0.3 Current Dependency Status

Phase 4 is not the next implementation target. The repository is ready through Phase 2 Milestone 10 plus the pre-Phase-3 GPS context milestone; Phase 1 Milestone 9 release evidence or explicit deferral remains before release signoff. Phase 4 work should wait until Phase 3 provides vocabulary files, normalization sessions, normalized export plans, and `normalize` / `apply-session` command behavior in `AISidecarCore`.

## 1. Purpose

Phase 4 shall turn the command-line phases into the original GUI MVP: a local-first macOS application for AI-assisted subject and scene tagging that writes clean XMP sidecars for Lightroom Classic, Capture One, and similar tools.

The GUI shall not replace Lightroom, Capture One, Photo Mechanic, or a DAM. It provides controlled review, correction, normalization, and sidecar export around the analysis pipeline already proven by the CLI phases.

## 2. Builds Upon Phase 3

Phase 4 shall reuse, from `AISidecarCore`:

- the Phase 1 scanner, identity, renderer, subject-isolation chain, model runner, raw JSON schema, error taxonomy, progress logs, batch summaries, and provenance structure;
- the Phase 1 GPS context policy as model-input context only, never as writable GPS metadata;
- the Phase 2 raw-sidecar reader, source verification, candidate extraction, same-base-name group planning, XMP target naming, export reports, and dry-run change plans;
- the Phase 2 `MetadataWriteEngine` protocol and required `OwnedXMPSidecarEngine` implementation;
- the Phase 2 owned XMP modules: `XMPDocumentParser`, `XMPDocumentWriter`, `XMPKeywordReader`, `XMPKeywordMerger`, `XMPMetadataSnapshot`, and `XMPUnmanagedContentFingerprint`;
- the Phase 2 semantic merge, backup, restore, validation, and fail-closed XMP parse behavior;
- the Phase 3 vocabulary format and integrity rules, normalization sessions, synonym canonicalization, propagation rules, conflict detection, and normalized XMP write plans.

The GUI is a user-facing orchestration layer over the same core engine. There is no parallel implementation to drift; PW-002 makes this structural rather than aspirational.

## 3. Scope

The GUI shall support:

- folder import;
- image queue management;
- whole-image and subject-isolated preview display;
- one-pass or two-pass model analysis;
- candidate tag review;
- controlled vocabulary editing;
- batch normalization review;
- source verification and stale-session warnings;
- sidecar snapshot refresh;
- sidecar export through the owned XMP engine;
- semantic export validation;
- compatibility reporting for Lightroom Classic and Capture One.

The GUI shall not perform RAW editing, develop-setting management, cloud upload, face recognition, direct Lightroom catalog manipulation, direct Capture One catalog/session manipulation, embedded metadata writing, or external metadata-tool orchestration in the MVP.

## 4. Architecture Requirements

FR4-001 - The GUI shall be a native macOS application built with SwiftUI, targeting macOS 15. AppKit interop is permitted where SwiftUI is insufficient, but the application architecture is SwiftUI.

FR4-002 - All processing shall be performed by `AISidecarCore`; the GUI target contains presentation, state orchestration, and user interaction only.

FR4-046 - **Sidecar-only mode (default).** By default the GUI shall keep all durable state in the file formats the CLI already reads and writes: `.ai.json` raw sidecars, XMP sidecars, Phase 3 vocabulary files, Phase 3 normalization-session files, and the shared `config.json`. Between-session queue state is derived by rescanning the selected folders and inspecting those files. In-session review state is held in memory and made durable by session export (NFR4-008); an unfinished review is resumed by importing the session file (FR4-012b). In this mode the GUI shall not create, open, or require any database file.

FR4-047 - **Database mode (experimental opt-in).** The SQLite working database shall be offered as an experimental option under Settings → Advanced ("Working database (experimental)"), off by default. Enabling it creates the database under `~/Library/Application Support/CupricAspect/` — never inside the app bundle, which is read-only and code-signed. Disabling it returns the GUI to sidecar-only behavior without loss of any sidecar, session, or vocabulary file, and offers to keep or delete the database file. The toggle's UI copy shall state, in plain language, what the database adds (persisted review state without manual session export, cross-session external-change detection, keyword non-resurrection memory, granular crash resumability) and that the feature is experimental.

FR4-048 - **Mode scoping.** The following apply only in database mode: FR4-003, FR4-004, FR4-004a–c, FR4-005, the persisted form of the FR4-011 state machine, FR4-012 reprocessing across sessions, FR4-020a cross-session non-resurrection, FR4-030a–e external-change detection, NFR4-004 transactional state changes, NFR4-007 migrations, and AC4-009, AC4-012 (cross-session part), AC4-015, AC4-020, AC4-023, AC4-024. In sidecar-only mode the GUI shall disclose the relevant limitation at the point of use (for example, before export: "External edits since your last export are merged, but cannot be flagged — enable the working database for change detection"). Requirements not listed here apply in both modes.

FR4-003 - (Database mode.) The GUI shall use a local SQLite database as working state, accessed through a thin data layer owned by the project. No heavyweight ORM shall be used in the MVP.

FR4-004 - The database shall store assets, source identity hashes, source-resolution state, sidecar target paths, sidecar content hashes, sidecar mtimes, `XMPMetadataSnapshot` records, `XMPUnmanagedContentFingerprint` records, derivative records, model runs, tag candidates, approved tags, rejected tags, deferred tags, vocabulary entries, normalization sessions, export actions, review actions, external-change events, backup paths, validation results, engine versions, and writer recipe versions.

FR4-004a - The user shall be able to "forget" an imported root folder: delete its assets and all dependent rows (snapshots, candidates, reviews, model runs, events, export actions, validation results) in one transaction. Forgetting shall require either a completed session export in the NFR4-008 format or an explicit confirmation that names what is lost — review history and the external-change memory that prevents keyword resurrection (FR4-020a) for that folder. Forgetting shall never modify or delete image files, sidecars, or sidecar backups on disk.

FR4-004b - The append-only history tables (`model_runs`, `review_actions`, `export_actions`, `external_change_events`, `validation_results`) shall be prunable by age with a user-configurable retention window (default 180 days). Pruning shall always retain, per asset and regardless of age: the most recent sidecar snapshot, the most recent export action, and every record still required for external-change detection (FR4-030a–e) and non-resurrection (FR4-020a). Current review decisions, tag candidates for not-yet-exported work, normalization sessions, and vocabulary entries are never auto-pruned.

FR4-004c - After a forget or prune deletes a substantial number of rows, the data layer shall compact the database (SQLite `VACUUM` or incremental auto-vacuum) off the main actor, so on-disk size tracks live data.

FR4-005 - (Database mode.) The GUI shall treat XMP sidecars as export artifacts, not as the only working memory. The database is the working truth between sessions; the current sidecar on disk is the interchange truth; reconciling the two is required before export. (In sidecar-only mode the files on disk are the only truth; export always merges against current sidecar content via the Phase 2 semantic-merge path.)

FR4-006 - The GUI shall import existing Phase 1 `.ai.json`, Phase 2 XMP sidecars, Phase 2 export reports/change plans, Phase 3 vocabulary files, and Phase 3 normalization session files, honoring PW-011/PW-012 schema evolution.

FR4-006a - The GUI shall not require ExifTool or any external metadata command-line tool to import, review, validate, or export sidecar metadata.

FR4-006b - Optional developer diagnostics may compare owned-engine output against external tools outside the shipped app. Such diagnostics are not runtime dependencies and are not user-facing MVP features.

FR4-006c - XMP parse, merge, validation, hashing, and snapshot work shall run off the main actor. The UI shall receive stable state updates, not direct XML objects.

## 5. User Workflow Requirements

FR4-007 - The user shall be able to select one or more folders for scanning.

FR4-008 - The user shall be able to choose analysis mode: whole image, subject isolated, or both.

FR4-009 - The user shall be able to choose or confirm the model tag, defaulting to `gemma4:26b-a4b-it-qat`, with the tag verified against the local runtime and the digest recorded.

FR4-010 - The user shall be able to start, pause, resume, and cancel scan, render, model, normalization, sidecar refresh, and export jobs.

FR4-011 - The application shall show queue state per asset:

```text
discovered
source verified
metadata read
metadata read failed
rendered
analyzed
normalized
awaiting review
approved
externally changed
export planned
exported
failed
```

Failed states shall display the structured error code and message and shall be filterable by code.

FR4-012 - The application shall allow reprocessing by model, prompt version, render recipe, vocabulary version, normalization session, XMP writer recipe version, or source-verification result, using recorded provenance.

FR4-012a - The user shall be able to refresh metadata snapshots without running analysis or export.

FR4-012b - The user shall be able to import an existing Phase 3 normalization session and continue review/export from it.

## 6. Review UI Requirements

FR4-013 - The review screen shall show the full image.

FR4-014 - The review screen shall show the subject-isolated derivative when available, including the recorded instance count and selected-instance indication.

FR4-015 - The review screen shall show which source produced each candidate: whole image, subject isolated, normalized batch context, or user context.

FR4-016 - The review screen shall show flat keyword, hierarchical keyword, confidence band, evidence string, alternatives, vocabulary match, normalization rule, review requirement, and provenance.

FR4-017 - The user shall be able to approve, reject, edit, or defer each candidate tag.

FR4-018 - The user shall be able to approve or reject tags in batches.

FR4-019 - The user shall be able to apply a corrected tag, with explicit confirmation, to a defined computable scope: the current batch, the current normalization session, the current folder, a same-base-name group, or all images currently carrying a specified candidate tag. "Visually similar" is not a computable scope in the MVP, and the UI shall not offer it until embedding search exists.

FR4-020 - Tags whose vocabulary entries set `requires_review` shall require manual review. This is vocabulary policy surfaced in the UI, not a parallel GUI policy.

FR4-020a - When a tag was removed from an XMP sidecar outside the app after a previous export, the GUI shall show it as externally removed. Re-adding it shall require explicit user confirmation rather than automatic resurrection from the database.

## 7. Vocabulary and Normalization UI Requirements

FR4-021 - The GUI shall include a controlled vocabulary editor operating on the Phase 3 JSON format and enforcing Phase 3 integrity rules at edit time, with violations explained inline rather than only at save time.

FR4-022 - The user shall be able to add, edit, delete, import, and export vocabulary entries. Export shall produce a valid Phase 3 vocabulary file with a fresh content hash.

FR4-023 - The user shall be able to define synonyms, with collision detection live in the editor.

FR4-024 - The user shall be able to mark a tag as requiring review.

FR4-025 - The user shall be able to mark a tag as eligible or ineligible for auto-approval.

FR4-026 - The user shall be able to inspect batch normalization decisions before XMP export, including the governing rule for each decision.

FR4-027 - The GUI shall show conflicting model observations and explain why a tag was or was not propagated.

FR4-027a - The GUI shall distinguish raw model candidates, vocabulary-canonicalized candidates, propagated batch tags, and user session context in the visual review model.

FR4-027b - The GUI shall show whether an exported hierarchical keyword comes from a vocabulary `canonical_path`. It shall not display raw model text containing `|` as exportable hierarchy.

## 8. Sidecar Export Requirements

FR4-028 - The GUI shall use the Phase 2/3 `MetadataWriteEngine`, `OwnedXMPSidecarEngine`, backup, restore, semantic merge, and validation behavior unchanged.

FR4-028a - The GUI shall not invoke ExifTool or any other external metadata command-line tool for required export, validation, import, or reporting.

FR4-029 - The GUI shall support dry-run export, rendering the Phase 2/3 change plan visually before any write.

FR4-030 - The GUI shall preserve existing sidecar metadata by default, verified by Phase 2 semantic validation: owned-parser readback, managed-field snapshot comparison, and unmanaged-content fingerprint comparison.

FR4-030a - At snapshot time, the application shall record each sidecar's content hash, mtime, parse status, managed keyword snapshot, unmanaged-content fingerprint, XMP writer recipe version, and owned-engine version in the database.

FR4-030b - Before any export write, the application shall perform a freshness check. If the on-disk sidecar hash differs from the database snapshot, the application shall re-read the current sidecar, rebuild the owned-engine metadata snapshot and unmanaged-content fingerprint, re-merge approved pending tags against current disk content, and mark the asset "changed outside the app" in the UI and export report.

FR4-030c - A merge against a stale snapshot is forbidden. The user may review the external change, refresh the database snapshot, or cancel export for the affected asset.

FR4-030d - If a previously exported app-approved keyword is missing from the current sidecar during freshness check, it shall be treated as an external deletion. It shall not be re-added unless the user explicitly confirms re-export of that keyword.

FR4-030e - The user shall be able to trigger a manual refresh that re-snapshots sidecars and highlights external changes without exporting.

FR4-031 - The GUI shall write approved flat keywords to `XMP-dc:Subject`.

FR4-032 - The GUI shall write approved hierarchical keywords to `XMP-lr:HierarchicalSubject` when enabled.

FR4-032a - Hierarchical keywords written by the GUI shall come from Phase 3 vocabulary `canonical_path` values or other approved Phase 3 normalized write plans, not from unchecked model text.

FR4-033 - The GUI shall never modify source image files, including proprietary RAW, JPEG, TIFF, HEIC, PNG, and DNG files. The MVP is sidecar-only.

FR4-034 - The GUI shall surface same-base-name groups with Phase 2 scope options (`union|raw-only|jpeg-only`) before export.

FR4-035 - The GUI shall validate exported sidecars through the owned parser and semantic snapshot/fingerprint comparison, and shall present failures, restorations, and backups in the export report.

FR4-035a - Malformed existing XMP shall surface as `E_XMP_PARSE_FAILED`. Unsupported but well-formed RDF/XMP shapes shall surface as `E_XMP_UNSUPPORTED_RDF`. The GUI shall not offer a normal export button for affected assets until the user resolves or excludes them.

FR4-035b - On validation failure, the GUI shall show whether a backup was restored, where the backup is located, which validation check failed, and which assets remain unexported.

FR4-035c - The export report shall record the owned XMP engine name/version, XMP writer recipe version, validation results, backup paths, restoration results, external-change decisions, and structured errors.

## 9. Compatibility Requirements

FR4-036 - The GUI shall include a Lightroom Classic compatibility profile that prioritizes XMP sidecar export and Lightroom-style hierarchical keywords.

FR4-037 - The GUI shall include a Capture One compatibility profile that prioritizes flat keywords in `dc:subject` and warns that Lightroom-specific hierarchy may not behave identically.

FR4-038 - Export reports shall give the post-export instructions specified by Phase 2: Lightroom Classic requires the user to select already-imported photos and invoke Metadata > Read Metadata from Files to import outside sidecar changes; Capture One behavior depends on Metadata preferences, especially Auto Sync Sidecar XMP / Load / Full Sync.

FR4-038a - The GUI shall provide a compatibility-report view summarizing which XMP fields were written, which fields were intentionally not written, whether the owned parser validated the sidecar, and whether Lightroom Classic/Capture One smoke-check evidence is available for the current writer recipe version.

FR4-038b - Compatibility smoke checks are release evidence, not required runtime behavior. The shipped GUI shall not shell out to external validators to claim success.

FR4-039 - The application shall remain responsive — scrolling, filtering, and selection without perceptible stalls — with a working session of 5,000 images. This number is a design input: it implies precomputed thumbnails persisted via the derivative cache/database, virtualized grid views, lazy full-preview loading, asynchronous sidecar parsing, and batched database writes.

## 10. Non-Functional Requirements

NFR4-001 - The application shall process images locally by default.

NFR4-002 - The application shall not upload source images, derivatives, metadata, sidecars, vocabulary files, normalization sessions, or model output to a cloud service in the MVP.

NFR4-003 - Long-running operations shall run in background queues while the UI remains responsive, using the PW-015 pipeline for image/model work and separate bounded queues for XMP parsing, hashing, and validation.

NFR4-003a - Responsiveness is measured against the FR4-039 scale target.

NFR4-004 - The application shall be crash-resumable. Every asset state change shall be a database transaction. In-flight pipeline work follows the Phase 1 contract: atomic artifact writes and progress logs. On relaunch, state is reconstructed from the database and durable artifacts; no asset can be in an ambiguous state.

NFR4-005 - The application shall record model, prompt, render, vocabulary, normalization, source-verification, XMP writer, backup, validation, and export provenance.

NFR4-006 - The application shall prefer conservative metadata over aggressive but unreliable automation.

NFR4-007 - The database schema shall carry a version. The application shall apply forward migrations automatically, shall refuse to open a database from a newer schema with a clear message, and shall never destructively migrate without a completed backup of the database file.

NFR4-008 - The application shall provide an export of approved-tag state in the Phase 3 session-file format, so the working database is never the only copy of accumulated review work.

NFR4-009 - The application shall not have a required runtime dependency on ExifTool, Adobe XMP Toolkit, Exiv2, ImageMagick, or any other external metadata tool. Libraries that are part of the macOS system stack and Swift package dependencies already approved by the project are permitted.

NFR4-010 - XMP formatting changes made by the owned writer shall be documented as semantic preservation, not byte-for-byte preservation. The UI and reports shall not imply otherwise.

## 11. Acceptance Criteria

AC4-001 - The user can import a folder of mixed RAW and JPEG files.

AC4-002 - The GUI can run whole-image analysis, subject-isolated analysis, or both.

AC4-003 - The GUI shows both whole-image and subject-isolated model outputs where available, with instance information for multi-subject frames.

AC4-004 - The user can approve, reject, edit, or defer proposed tags, with confidence bands, evidence, vocabulary match, and provenance visible.

AC4-005 - The user can manage a controlled vocabulary and synonyms, with integrity violations caught at edit time.

AC4-006 - The GUI can apply Phase 3 batch normalization and show the governing rule and provenance for each result.

AC4-007 - The GUI writes approved tags to XMP sidecars without modifying source image files.

AC4-008 - Existing XMP metadata is semantically preserved, verified by owned-parser readback, metadata snapshot comparison, and unmanaged-content fingerprint comparison.

AC4-009 - A sidecar edited in Lightroom Classic or Capture One between GUI sessions is detected before export, re-merged against current content, and flagged in the UI and report. An externally added keyword survives. An externally deleted keyword is not resurrected without explicit user confirmation.

AC4-010 - Exported sidecars validate through the owned XMP parser, and release smoke checks confirm Lightroom Classic and Capture One can import the written keywords.

AC4-011 - The user can generate a compatibility/export report including post-export instructions.

AC4-012 - The app can resume after being closed mid-batch with no asset in an ambiguous state.

AC4-013 - The core engine remains callable by the `aisidecar` CLI, demonstrated by running a CLI batch against the same `AISidecarCore` build.

AC4-014 - A 5,000-image session scrolls, filters, and changes selection without perceptible stalls on the target hardware.

AC4-015 - Opening a database from an older schema migrates it forward after backing it up; opening one from a newer schema is refused with a clear message.

AC4-016 - The GUI can import a Phase 3 normalization session, continue review, and export through the owned XMP engine without model runs.

AC4-017 - A malformed existing XMP sidecar surfaces `E_XMP_PARSE_FAILED`; an unsupported RDF/XMP shape surfaces `E_XMP_UNSUPPORTED_RDF`; neither condition modifies the sidecar or source image.

AC4-018 - Exporting a same-base-name RAW+JPEG group produces exactly one sidecar write plan and shows the selected `pair-scope` before export.

AC4-019 - The shipped GUI can export sidecars without ExifTool installed.

AC4-020 - Manual metadata refresh detects changed, added, deleted, malformed, and missing sidecars without running image analysis.

AC4-023 - Forgetting a folder removes its rows in one transaction, leaves every other folder's state and all on-disk image/sidecar files untouched, shrinks the database file after compaction, and a subsequent re-import of that folder behaves as a first import. The forget action is blocked until a session export completes or the user explicitly confirms the described loss. (AC4-021/022 are in Section 13.)

AC4-024 - After pruning history older than the retention window, AC4-009 external-change detection and keyword non-resurrection still pass for an asset whose relevant events predate the window.

AC4-025 - On a fresh install with defaults, a complete analyze → review → export → relaunch → re-review cycle succeeds with no database file created anywhere on disk; after relaunch the queue is rebuilt from the folder's files, and an exported session file restores the in-progress review via import.

AC4-026 - Enabling the experimental working database creates it under `~/Library/Application Support/CupricAspect/`; disabling it returns to sidecar-only behavior with all sidecar, session, and vocabulary files intact, and the user is offered the choice to keep or delete the database file. The app bundle's contents are unchanged by either action.

## 12. Future Groundwork Beyond the GUI MVP

The GUI phase should leave room for:

- visual embedding search, which would unlock a real "visually similar" scope for FR4-019;
- stronger species-specific assist models;
- OCR-specific passes using Apple Vision text recognition or a dedicated text model path;
- map/GPS filtering without AI-inferred GPS writes;
- Photo Mechanic or DAM profile exports;
- model comparison runs over recorded provenance;
- user correction learning;
- embedded JPEG/TIFF/DNG metadata writing only after the sidecar-only engine has proven safe;
- broader XMP namespace editing only when each namespace and field is explicitly scoped;
- optional external-tool comparison as developer diagnostics, not as shipped runtime behavior;
- direct plug-in integrations, if later justified.

## 13. Interface Shell and Appearance Requirements (v0.4)

These requirements bind the GUI to the CupricAspect design. Exact tokens, layouts, and per-screen specs live in `agent_docs/07-cupricaspect-gui-design.md`; this section states only the testable behavior.

FR4-040 - The application shall provide two interface shells over the same feature state: a linear **Wizard** (five steps: Photos, What to do, Options, Working, Review) and a nonlinear **Studio** (sidebar navigation: Analyze, Normalize, Write XMP, Apply Prior Session, Settings). Wizard is the first-launch default.

FR4-041 - The shell choice shall be a Settings toggle ("Nonlinear UI"), persisted across launches (`UserDefaults` key `cupricaspect.nonlinear`). Switching shells shall not discard in-flight state: selected folders, chosen action, options, and unexported results survive the switch.

FR4-042 - The application shall support Light, Dark, and Auto themes and three accent palettes (copper — default, amber/"Brass", patina), persisted across launches. Auto shall follow the macOS system appearance and update live when it changes.

FR4-043 - The animated aperture component (design doc Section 5) is the brand mark and the working indicator: idle-open when no job runs; breathing/spinning while a job runs. When the system reduce-motion setting is on, it shall render statically and entrance/progress animations shall be disabled.

FR4-044 - Option controls shall map one-to-one onto existing Core enums (`AnalysisMode`, `ExistingPolicy`, `GPSContextMode`, `XMPPairScope`, `stage_concurrency`); the GUI shall not invent option values that Core does not accept. The existing-sidecar control offers Skip / Overwrite / Fail in both shells.

FR4-045 - Every count, rate, filename, thumbnail, and progress figure shown in the shells shall come from real pipeline, database, or filesystem state; prototype sample data shall not ship.

AC4-021 - Switching Nonlinear UI off→on→off with a folder selected and un-exported review results present loses no state, and the chosen shell is restored after relaunch.

AC4-022 - With macOS reduce-motion enabled, the working screen shows a static aperture and a non-animated progress fill while a batch runs to completion successfully.

## Reference Basis

This document incorporates the Reference Basis of Phase 1 v0.4, Phase 2 v0.5, and Phase 3 v0.4. Items load-bearing for this phase specifically:

- Adobe XMP specifications: https://developer.adobe.com/xmp/docs/xmp-specifications/
- W3C RDF/XML syntax and RDF container vocabulary: https://www.w3.org/TR/rdf-syntax-grammar/
- Apple Foundation XML document processing: https://developer.apple.com/documentation/foundation/xmldocument
- IPTC Photo Metadata Standard 2025.1, Keywords implemented as `dc:subject`: https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata
- Adobe Lightroom Classic XMP sidecar behavior and metadata actions: https://helpx.adobe.com/lightroom-classic/help/create-xmp-acr-files.html and https://helpx.adobe.com/lightroom-classic/help/advanced-metadata-actions.html
- Capture One XMP sidecar behavior and Auto Sync Sidecar XMP settings: https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files
