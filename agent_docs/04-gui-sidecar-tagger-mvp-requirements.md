# Phase 4 Requirements - GUI Sidecar Tagger MVP

Version: 0.10
Date: 2026-07-08
Supersedes: 0.9
Builds on: Phase 1 Requirements v0.4, Phase 2 Requirements v0.5, Phase 3 Requirements v0.4
App name: `CupricAspect.app` (resolves the former working name `SidecarTagger.app`)
Visual design basis: `agent_docs/07-cupricaspect-gui-design.md`
Core library: `AISidecarCore` (shared with the `aisidecar` CLI by construction, per PW-002)
Minimum deployment target: macOS 15
Default vision model: `gemma4:26b-a4b-it-qat`
Primary output artifact: reviewed XMP sidecar files, with a local working database

This document inherits the Project-Wide Conventions of the Phase 1 requirements and the owned-XMP export/normalization behavior of Phases 2 and 3. They are not restated except where Phase 4 narrows or clarifies their GUI use.

## 0. Version History

Each row summarizes what that document version changed relative to the one before it. Requirement text in Sections 1–13 carries its own inline `(Amended vX)` / `(Deferred in vX)` markers where the change matters; this table is the only revision narrative.

| Version | What changed |
|---------|--------------|
| v0.2 | Substantive baseline, all still active: out-of-band sidecar edit detection, versioned SQLite schema, scoped batch correction, 5,000-image responsiveness target, crash resumability through transactions and pipeline artifacts, direct surfacing of structured error codes, SwiftUI on macOS 15, thin owned SQLite data layer. |
| v0.3 | Owned XMP engine replaces ExifTool: `MetadataWriteEngine` + required `OwnedXMPSidecarEngine`; no ExifTool at runtime or in acceptance (Lightroom Classic / Capture One smoke checks retained as release evidence); preservation is semantic, not byte-for-byte; out-of-band sidecar edits re-merged via the owned parser with no keyword resurrection without explicit confirmation; malformed/unsupported XMP (`E_XMP_PARSE_FAILED`, `E_XMP_UNSUPPORTED_RDF`) becomes a first-class fail-closed UI state; owned-XMP diagnostics surfaced at a user-appropriate level. |
| v0.4 | CupricAspect design adopted (`agent_docs/07-cupricaspect-gui-design.md`): app renamed from `SidecarTagger.app` to `CupricAspect.app`, GUI state directory `~/Library/Application Support/CupricAspect/`; interface-shell and appearance requirements FR4-040–045 added (Section 13); design doc §8.2 resolutions binding and all prototype counts/rates/filenames are sample data; data-retention requirements FR4-004a–c and AC4-023/024 added. |
| v0.5 | Storage modes: sidecar-only becomes the default — all durable state in files the CLI already understands, with durability via session export/import (FR4-046); the SQLite working database demoted to an experimental opt-in (FR4-047) with database-only guarantees scoped by mode and sidecar-only limitations disclosed at point of use (FR4-048). |
| v0.6 | MVP scoping from the 2026-07-06 design review: Wizard-first MVP with Studio in a later milestone (FR4-040); review autosave (FR4-046a, AC4-027); `xmp_export` block written into `.ai.json` so export status is derivable from files alone (FR4-049, CORE-4); reprocessing narrowed to `skip`/`overwrite` re-runs (FR4-012); vocabulary editor descoped to a read/toggle inspector (itself deferred entirely in v0.7); single window (FR4-050); no-polling Ollama status policy (FR4-051). |
| v0.7 | Normalization reality: normalization review is inspection + explanation, never per-keyword editing — the normalize screen becomes the read-only **Normalization Inspector** plus session context panel and model-free re-run loop (FR4-026/027 amended, FR4-052–055); **all vocabulary tooling deferred to Section 12, including the inspector promised in v0.6** (FR4-021–025, AC4-005 removed from the MVP; the GUI only selects a vocabulary file and displays engine-reported facts); `aisidecar explain-session` added, sharing one Core explainer with the Inspector (CORE-6/CLI-1, AC4-031). |
| v0.8 | Settings write-through to the shared `config.json` via read-modify-write preserving unknown keys, with `AISIDECAR_*` overrides disclosed (FR4-056, AC4-032); vision-capable model picker with validated, connectivity-indicated endpoint (FR4-057, AC4-033). |
| v0.9 | Beta readiness (plan milestone B0): single root folder, multi-root import moved to Section 12 (FR4-007); first-run and missing-runtime guidance (FR4-058, AC4-034); diagnostic file logging with UI-surfaced save/import failures (FR4-059, AC4-035); packaging/signing/notarization/icon/version/release evidence tracked by reference to `agent_docs/06-packaging-single-app-plan.md`. |
| v0.10 | Collapsed revision histories into this table; status pointers refreshed. |
| v0.11 | Alpha-build Options-page and navigation fixes, scheduled in `agent_docs/08-post-review-hardening-plan.md` R1 (before the beta tag): per-run vision-model override on the Options page distinct from the persisted Settings default (FR4-060, AC4-036); the XMP conflict policy surfaced in Options → Advanced with the Core `backup-and-merge` default (FR4-061, AC4-037); Back from the Review step returns to Options non-destructively and a re-run confirms before discarding completed analysis/review data (FR4-062, AC4-038). |

## 0.1 Current Dependency Status

Phases 1–3 (CLI) are complete. GUI status lives in README.md/AGENTS.md; the outstanding overall-release caveat is Phase 1 Milestone 9 calibration/quality evidence or an explicit release-note deferral.

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
- controlled vocabulary selection for normalization runs and read-only display of vocabulary-derived facts (editing deferred — Section 12);
- batch normalization inspection with session context input (v0.7);
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

FR4-046a - **Review autosave (sidecar-only mode).** The GUI shall autosave in-progress review state to a recovery session file (Phase 3 session format) in the GUI state directory, after every 25 review decisions or 5 minutes since the last save, whichever comes first (defaults; tunable in config). On relaunch after an unclean exit the GUI shall offer to restore from the recovery file. Recovery files are superseded by explicit session export and removed on clean completion of the flow they protect.

FR4-047 - **Database mode (experimental opt-in).** The SQLite working database shall be offered as an experimental option under Settings → Advanced ("Working database (experimental)"), off by default. Enabling it creates the database under `~/Library/Application Support/CupricAspect/` — never inside the app bundle, which is read-only and code-signed. Disabling it returns the GUI to sidecar-only behavior without loss of any sidecar, session, or vocabulary file, and offers to keep or delete the database file. The toggle's UI copy shall state, in plain language, what the database adds (persisted review state without manual session export, cross-session external-change detection, keyword non-resurrection memory, granular crash resumability) and that the feature is experimental.

FR4-049 - **Export status in the raw sidecar.** On every successful XMP export of an asset, the export pipelines (Core change CORE-4 — shared by CLI and GUI) shall write an additive, optional `xmp_export` block into that asset's `.ai.json`: target XMP path, content hash of the written XMP, writer recipe version, engine version, and timestamp. The block follows PW-011/012 additive schema evolution — older readers ignore it; analyze paths never write it (it belongs to export, preserving the analyze-never-touches-XMP invariant's spirit: analysis output remains pure, export appends its own provenance). Queue-state derivation uses it as follows: block present **and** target XMP present → `exported`; XMP present without the block → `XMP present (external)`, never `exported`; block present but XMP missing → `XMP missing (was exported)`.

FR4-050 - **Single window.** The MVP is a single-window application: one main window, no ⌘N second window, no multi-window state model. Auxiliary content (About, confirmations) uses sheets or panels.

FR4-051 - **Ollama status policy.** Endpoint/model connectivity shall be verified at app launch, immediately before each run (the FR4-009 preflight), and on explicit user refresh — never by continuous background polling. Status indicators (the "connected"/"verified" dots) reflect the most recent check and its time; a stale or failed check renders as such rather than as "disconnected" alarm or silent success.

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

FR4-007 - (Amended v0.9.) The user shall be able to select one root folder for scanning; nested folders are included via the recursive toggle (on by default). Multi-root import in one session is out of the MVP (Section 12).

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

FR4-012 - (Descoped in v0.6.) The MVP shall allow re-running analysis for selected assets or a whole folder under the current configuration, with `skip` or `overwrite` existing-sidecar semantics. Reprocessing filtered by arbitrary recorded provenance dimensions (prompt version, render recipe, vocabulary version, normalization session, XMP writer recipe version, source-verification result) is deferred to Section 12 — recorded provenance already contains everything needed, and database mode makes the queries practical.

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

FR4-021 – FR4-025 - (Deferred in v0.7 — Section 12.) All vocabulary tooling (inspector, editor, flag toggles, synonym editing) is out of the MVP: vocabulary tooling is not currently an enabled part of the product, and no MVP feature may depend on it. In the MVP the GUI shall only (a) let the user pick the vocabulary JSON file a normalization run uses (defaulting to the bundled starter vocabulary) and (b) display vocabulary-derived facts the engine reports (match state, `requires_review`, direct-apply policy). Vocabulary files are edited externally; surfaces that would benefit from vocabulary edits shall point the user at the file path and the re-run loop (FR4-054), never at an in-app editor.

FR4-026 - (Amended v0.7.) The user shall be able to inspect batch normalization decisions before XMP export in a **Normalization Inspector**: per keyword — outcome (`accepted` / `withheld` / `skipped`), originating stage (`direct_model_observation`, `user_session_context`, `local_affinity_propagation`, `global_backstop_propagation`, `phase2_fallback`), governing rule, support (asset count and support units), and skip reasons rendered as human-readable text; expandable per-asset detail with supporting assets and conflicts. Filters: by outcome, by stage, and a "needs attention" view (requires-review, conflicts, unmatched vocabulary). The Inspector is read-only over the session document — **the GUI shall not offer per-keyword keep/merge/rename/drop or any other per-keyword decision control; the normalization engine has no such inputs.**

FR4-027 - The GUI shall show conflicting model observations and explain why a tag was or was not propagated.

FR4-052 - **Session context panel (v0.7).** Before a normalization run, the GUI shall offer the engine's per-run human inputs: Subject, Habitat, and Event text fields mapping to `--session-subject/-habitat/-event`, a per-field propagation toggle (off by default, mapping to the `--allow-session-*-propagation` gates), and the unknown-context policy (`reject` default / `write-unnormalized`). Field-level feedback shall show the vocabulary match state before the run where practical (matched → canonical path; unmatched → the policy choice and its consequence). After a run, the FR3-025 lists (non-supporting and conflicted assets per context value) shall be reachable from the Inspector.

FR4-053 - **Accepted-only export surface (v0.7).** "Write normalized XMP" exports accepted decisions exactly as the engine planned them; withheld and skipped keywords are visibly excluded with their reasons. "Save session only" and session import remain available from the same surface.

FR4-054 - **Model-free re-run loop (v0.7).** The GUI shall offer "Re-run normalization" after vocabulary-file or session-context changes, using the engine's `fromJSON` mode over existing `.ai.json` sidecars — no model calls. The Inspector shall indicate when its session predates the current vocabulary file (content hash mismatch).

FR4-055 - **Shared decision explainer (v0.7).** The human-readable rendering of stages, governing rules, and skip reasons shall live in `AISidecarCore` (one mapping), consumed by both the Inspector and the `aisidecar explain-session` command (plan CORE-6/CLI-1), so GUI and CLI explanations cannot drift.

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

AC4-005 - (Deferred in v0.7 — moved to Section 12 with the vocabulary tooling. No MVP acceptance depends on vocabulary editing.)

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

AC4-027 - Killing the app mid-review after at least one autosave interval, then relaunching, offers recovery; accepting restores the review decisions present at the last autosave, and declining leaves the recovery file available until a new review begins.

AC4-028 - An asset whose XMP sidecar existed before any app export renders as "XMP present (external)" and never as "exported"; after an app export, it renders as "exported"; deleting the exported XMP afterwards renders "XMP missing (was exported)".

AC4-029 - The session context panel: a value matching the vocabulary shows its canonical path before the run; an unmatched value surfaces the reject / write-unnormalized choice with its consequence; propagation toggles are off by default; after a run, conflicted assets for a context value are listed and did not receive it.

AC4-030 - The Normalization Inspector explains every non-exported keyword: each withheld/skipped row shows its stage, governing rule, and skip reasons in plain language; conflicts list the competing keywords and assets; "Write normalized XMP" writes exactly the accepted set; no per-keyword decision control exists anywhere in the flow.

AC4-031 - `aisidecar explain-session <session> --keyword <term>` prints the same stage/rule/support/conflict/skip facts for that keyword that the Inspector displays, sourced from the same Core explainer, for a session produced by either the CLI or the GUI.

AC4-032 - Changing a run default in Settings updates `config.json` such that a subsequent CLI resolve reflects it, while hand-added keys in the file survive the write; an invalid endpoint is rejected without writing.

AC4-033 - The model picker lists exactly the installed tags whose Ollama capabilities include `vision`, sorted; selecting one persists it as the default model.

AC4-034 - On a machine without Ollama, launch and each run attempt produce actionable install/start guidance and no hang or crash; with Ollama running but no vision model installed, the model picker area explains the situation and names a pull command.

AC4-035 - A failed run leaves a readable log file under the app state directory containing the structured errors; a failing "Save session only" or session import shows the error in the UI.

AC4-036 - On the Options step, the vision-model dropdown lists the installed vision-capable tags; selecting a non-default model runs that batch against it and preflight re-checks it, while `config.json` and the Settings default remain unchanged; the override is gone after a new import or relaunch.

AC4-037 - The Options → Advanced existing-XMP control defaults to Backup & Merge; a write under Merge or Backup & Merge preserves a keyword already present in the target `.xmp`, Backup & Merge additionally writes a `.xmp.bak`, and Fail refuses when an `.xmp` exists; the default equals the Core/CLI built-in.

AC4-038 - Back from the Review step lands on Options with results and review decisions intact (Review → Options → Review without re-running shows the same review); pressing Start again then prompts to confirm the discard, Cancel keeps the data, and a first run with nothing prior does not prompt.

## 12. Future Groundwork Beyond the GUI MVP

The GUI phase should leave room for:

- multi-root folder import in one session, eliminated from the MVP in v0.9 (FR4-007);
- vocabulary tooling, deferred in full from FR4-021–025 (v0.7 — probable future inclusion once vocabulary tooling is an enabled part of the product): an inspector (browse, validate, policy display), `requires_review`/auto-approval flag toggles, guided "map keyword → synonym / new entry" actions from the Normalization Inspector, and eventually the full editor (add/edit/delete entries, synonym definition with live collision detection, import/export with fresh content hashes) plus matching `aisidecar vocab add-synonym` / `vocab add-entry` CLI commands;
- provenance-dimension reprocessing deferred from FR4-012: re-run filtered by prompt version, render recipe, vocabulary version, normalization session, writer recipe version, or source-verification result;
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

FR4-040 - The application shall provide two interface shells over the same feature state: a linear **Wizard** (five steps: Photos, What to do, Options, Working, Review) and a nonlinear **Studio** (sidebar navigation: Analyze, Normalize, Write XMP, Apply Prior Session, Settings). Wizard is the first-launch default. **MVP scoping (v0.6):** the Wizard is the MVP shell; Studio ships in its own milestone after the core feature flow completes and before the experimental database milestone. Until Studio lands, the "Nonlinear UI" toggle is visible but disabled, labeled "coming soon", and FR4-041/AC4-021 apply from the Studio milestone onward.

FR4-041 - The shell choice shall be a Settings toggle ("Nonlinear UI"), persisted across launches (`UserDefaults` key `cupricaspect.nonlinear`). Switching shells shall not discard in-flight state: selected folders, chosen action, options, and unexported results survive the switch.

FR4-042 - The application shall support Light, Dark, and Auto themes and three accent palettes (copper — default, amber/"Brass", patina), persisted across launches. Auto shall follow the macOS system appearance and update live when it changes.

FR4-043 - The animated aperture component (design doc Section 5) is the brand mark and the working indicator: idle-open when no job runs; breathing/spinning while a job runs. When the system reduce-motion setting is on, it shall render statically and entrance/progress animations shall be disabled.

FR4-044 - Option controls shall map one-to-one onto existing Core enums (`AnalysisMode`, `ExistingPolicy`, `GPSContextMode`, `XMPPairScope`, `XMPConflictPolicy` (v0.11), `stage_concurrency`); the GUI shall not invent option values that Core does not accept. The existing-sidecar control offers Skip / Overwrite / Fail in both shells; the existing-XMP control offers Fail / Merge / Backup & Merge (FR4-061).

FR4-045 - Every count, rate, filename, thumbnail, and progress figure shown in the shells shall come from real pipeline, database, or filesystem state; prototype sample data shall not ship.

FR4-056 - **Settings write-through (v0.8).** Run defaults edited in Settings (model tag, model endpoint, render mode, GPS context, existing-sidecar policy) shall persist to the shared config file via a read-modify-write that preserves unknown keys. The precedence chain is unchanged; Settings shall disclose active `AISIDECAR_*` environment overrides.

FR4-057 - **Vision model picker (v0.8).** Settings shall list installed Ollama models reporting the `vision` capability (Core `listInstalledVisionTags`, the preflight's own probing), let the user pick one (persisted per FR4-056), flag a configured-but-unavailable model, and offer an editable, validated endpoint with a connectivity indicator under the FR4-051 no-polling policy.

FR4-058 - **First-run and missing-runtime guidance (v0.9).** When Ollama is unreachable at launch or before a run, the GUI shall present the install/start guidance (mirroring the README troubleshooting) rather than a bare failure. When Ollama is reachable but no installed model reports the `vision` capability, the GUI shall say so and suggest a starter vision model with its `ollama pull` command.

FR4-059 - **Diagnostic file logging (v0.9).** The GUI shall route pipeline logger output to a size-bounded log file under the app state directory and show its location in Settings. User-initiated file operations (session save/import, config writes) shall surface failures in the UI; no silent `try?` on user-visible actions.

FR4-060 - **Per-run vision-model override (v0.11).** The Options step shall present the vision model as a selectable dropdown of installed vision-capable Ollama tags (the same source as the Settings picker, FR4-057), applying the choice as a **one-time override for that run only**. Choosing a model here shall not write `config.json` and shall not change the persisted Settings default (FR4-056); leaving it untouched shall use the resolved config model exactly as before. The override maps onto the model precedence slot the CLI `--model` flag occupies (a CLI-equivalent override, per FR4-013/invariant 13) and shall not persist across imports or relaunch. Preflight (FR4-051) shall validate the effective (override-or-resolved) model.

FR4-061 - **XMP conflict policy visible in Options (v0.11).** The Options → Advanced disclosure shall expose the existing-XMP conflict policy as a control mapping one-to-one onto Core `XMPConflictPolicy` (Fail / Merge / Backup & Merge; per FR4-044 no invented values), **defaulting to `backup-and-merge`** — the Core/CLI built-in, which merges new keywords into an existing `.xmp` after writing a timestamped backup. The GUI default shall equal the Core built-in so GUI and CLI never diverge (FR4-056 spirit). The disclosure shall state the behavior at the point of decision (merge preserves keywords already in the `.xmp`; Backup & Merge writes a `.xmp.bak` first). The selected policy shall drive the export write path rather than a hardcoded default.

FR4-062 - **Non-destructive Back from Review; confirmed re-run (v0.11).** Back from the Review step (Wizard Step 5, both the analyze/write flow and the normalize Inspector) shall return to the Options step, skipping the Working step, and shall be non-destructive — completed results and in-memory review decisions survive the navigation. Re-running analysis from Options when a completed run/review or a built normalization session already exists shall require a confirmation naming the loss ("Re-run … discards the current results and N review decisions") with a Cancel that aborts and preserves the data; a first run with nothing to lose shall not prompt.

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
