# Phase 4 Requirements - GUI Sidecar Tagger MVP

Version: 0.2
Date: 2026-06-10
Supersedes: 0.1
Working name: `SidecarTagger.app`
Core library: `AISidecarCore` (shared with the `aisidecar` CLI by construction, per PW-002)
Minimum deployment target: macOS 15
Default vision model: `gemma4:26b-a4b-it-qat`
Primary output artifact: reviewed XMP sidecar files, with a local working database

This document inherits the Project-Wide Conventions of the Phase 1 requirements (Section 1 there) and the export/normalization behavior of Phases 2-3. They are not restated here.

## 0. Changes from v0.1

1. Out-of-band sidecar edits — keywords changed in Lightroom or Capture One between GUI sessions — are now an explicit, first-class requirement: snapshot hashes, pre-export freshness checks, re-merge, and surfaced change indicators (FR4-030a-c). This is the GUI's single most important trust property after never-touch-RAW.
2. The SQLite working database carries a versioned schema with forward migrations and a documented state export (NFR4-007/008).
3. "Apply a corrected tag to similar images" is scoped to computable similarity for the MVP: same batch, same session, same folder, or images sharing a candidate tag. Visual-embedding similarity remains future work (FR4-019).
4. A concrete responsiveness scale target is set: a 5,000-image session (FR4-039, NFR4-003a).
5. Crash-resumability names its mechanism instead of asserting the property: per-state-change DB transactions plus the Phase 1 JSONL pipeline contract (NFR4-004).
6. Queue and failure states surface the Phase 1 error taxonomy codes directly (FR4-011).
7. Architecture confirms SwiftUI on macOS 15 and SQLite via a thin, owned data layer.

## 1. Purpose

Phase 4 shall turn the three command-line phases into the original GUI MVP: a local-first macOS application for AI-assisted subject and scene tagging that writes clean XMP sidecars for Lightroom Classic, Capture One, and similar tools.

The GUI shall not replace Lightroom, Capture One, Photo Mechanic, or a DAM. It provides controlled review, correction, normalization, and sidecar export around the analysis pipeline already proven by the CLI phases.

## 2. Builds Upon Phase 3

Phase 4 shall reuse, from `AISidecarCore`:

- the Phase 1 scanner, identity, renderer, subject-isolation chain, model runner (live, mock, recorded), raw JSON schema, error taxonomy, and provenance structure;
- the Phase 2 `MetadataWriteEngine`, merge behavior, backup/restore, round-trip validation, group resolution, and export reports;
- the Phase 3 vocabulary format and integrity rules, normalization sessions, synonym canonicalization, propagation rules, and conflict detection.

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
- sidecar export;
- export validation;
- compatibility reporting for Lightroom/Capture One.

The GUI shall not perform RAW editing, develop-setting management, cloud upload, face recognition, direct Lightroom catalog manipulation, or direct Capture One catalog/session manipulation.

## 4. Architecture Requirements

FR4-001 - The GUI shall be a native macOS application built with SwiftUI, targeting macOS 15 (PW-003). AppKit interop is permitted where SwiftUI is insufficient (e.g., high-performance grid cells), but the application architecture is SwiftUI.

FR4-002 - All processing shall be performed by `AISidecarCore`; the GUI target contains presentation and orchestration only (PW-002).

FR4-003 - The GUI shall use a local SQLite database as working state, accessed through a thin data layer owned by the project (no heavyweight ORM).

FR4-004 - The database shall store assets (with source identity hashes), metadata snapshots (with sidecar content hashes and mtimes), derivative records, model runs, tag candidates, approved tags, vocabulary, normalization sessions, export actions, and review actions.

FR4-005 - The GUI shall treat XMP sidecars as export artifacts, not as the only working memory. The database is the working truth between sessions; the sidecar on disk is the interchange truth, and reconciling the two is FR4-030a-c.

FR4-006 - The GUI shall import existing Phase 1 `.ai.json`, Phase 2 XMP, Phase 3 vocabulary, and Phase 3 normalization session files, honoring the schema-evolution rule (PW-011/012).

## 5. User Workflow Requirements

FR4-007 - The user shall be able to select one or more folders for scanning.

FR4-008 - The user shall be able to choose analysis mode: whole image, subject isolated, or both.

FR4-009 - The user shall be able to choose or confirm the model tag, defaulting to `gemma4:26b-a4b-it-qat`, with the tag verified against the local runtime per FR1-030b and the digest recorded.

FR4-010 - The user shall be able to start, pause, resume, and cancel scan, render, model, normalization, and export jobs.

FR4-011 - The application shall show queue state per asset: discovered, metadata read, rendered, analyzed, normalized, awaiting review, approved, exported, failed. Failed states shall display the Phase 1 error taxonomy code and message, and shall be filterable by code.

FR4-012 - The application shall allow reprocessing by model, prompt version, render recipe, or vocabulary version, using the provenance recorded with each artifact.

## 6. Review UI Requirements

FR4-013 - The review screen shall show the full image.

FR4-014 - The review screen shall show the subject-isolated derivative when available, including the recorded instance count and selected-instance indication (FR1-019c).

FR4-015 - The review screen shall show which model run produced each candidate: whole image, subject isolated, normalized batch context, or user context.

FR4-016 - The review screen shall show flat keyword, hierarchical keyword, confidence band, evidence string, alternatives, and provenance.

FR4-017 - The user shall be able to approve, reject, edit, or defer each candidate tag.

FR4-018 - The user shall be able to approve/reject tags in batches.

FR4-019 - The user shall be able to apply a corrected tag, with explicit confirmation, to a defined scope: the current batch, the current normalization session, the current folder, or all images currently carrying a specified candidate tag. "Visually similar" is not a computable scope in the MVP — embedding search is explicitly future work (Section 12) — and the UI shall not offer it until it is.

FR4-020 - Tags whose vocabulary entries set `requires_review` (species-level, named-place, named-person, rare-species, exact-location) shall require manual review. This is vocabulary policy surfaced in the UI, not a parallel GUI policy; the user changes it by editing the vocabulary entry.

## 7. Vocabulary and Normalization UI Requirements

FR4-021 - The GUI shall include a controlled vocabulary editor operating on the Phase 3 JSON format and enforcing its integrity rules (FR3-003a-e) at edit time, with violations explained inline rather than at save time.

FR4-022 - The user shall be able to add, edit, delete, import, and export vocabulary entries; export shall produce a valid Phase 3 vocabulary file with a fresh content hash.

FR4-023 - The user shall be able to define synonyms, with collision detection live in the editor.

FR4-024 - The user shall be able to mark a tag as requiring review.

FR4-025 - The user shall be able to mark a tag as eligible or ineligible for auto-approval.

FR4-026 - The user shall be able to inspect batch normalization decisions before XMP export, including the governing rule for each decision (FR3-035).

FR4-027 - The GUI shall show conflicting model observations (per FR3-024a semantics) and explain why a tag was or was not propagated.

## 8. Sidecar Export Requirements

FR4-028 - The GUI shall use the Phase 2/3 sidecar merge writer, backup, and validation unchanged.

FR4-029 - The GUI shall support dry-run export, rendering the Phase 2 change plan visually.

FR4-030 - The GUI shall preserve existing sidecar metadata by default, verified by the Phase 2 round-trip diff.

FR4-030a - At snapshot time (import or refresh), the application shall record each sidecar's content hash and mtime in the database.

FR4-030b - Before any export write, the application shall perform a freshness check: if the on-disk sidecar's hash differs from the snapshot, the application shall re-read the current sidecar, re-merge approved tags against its current content, and mark the asset "changed outside the app" in the UI and the export report. A merge against a stale snapshot can silently resurrect keywords the user deleted in Lightroom; this requirement exists to make that impossible.

FR4-030c - The user shall be able to trigger a manual refresh that re-snapshots sidecars and highlights external changes without exporting.

FR4-031 - The GUI shall write approved flat keywords to `XMP-dc:Subject`.

FR4-032 - The GUI shall write approved hierarchical keywords to `XMP-lr:HierarchicalSubject` when enabled.

FR4-033 - The GUI shall never modify proprietary RAW files.

FR4-034 - The GUI shall surface RAW+JPEG same-base-name groups with the Phase 2 scope options (`union|raw-only|jpeg-only`) before export.

FR4-035 - The GUI shall validate exported sidecars (Phase 2 round-trip diff) and present failures, restorations, and backups in the export report.

## 9. Compatibility Requirements

FR4-036 - The GUI shall include a Lightroom Classic compatibility profile that prioritizes XMP sidecar export and Lightroom-style hierarchical keywords.

FR4-037 - The GUI shall include a Capture One compatibility profile that prioritizes flat keywords in `dc:subject` and warns that Lightroom-specific hierarchy may not behave identically.

FR4-038 - Export reports shall give the post-export instructions specified in FR2-034a (Read Metadata from Files in Lightroom Classic; sidecar sync preferences in Capture One).

FR4-039 - The application shall remain responsive — scrolling, filtering, and selection without perceptible stalls — with a working session of 5,000 images. This number is a design input, not an aspiration: it implies precomputed thumbnails persisted via the derivative cache/database, virtualized grid views, and lazy full-preview loading, and those shall be designed in from the start rather than retrofitted after the first real import.

## 10. Non-Functional Requirements

NFR4-001 - The application shall process images locally by default.

NFR4-002 - The application shall not upload source images, derivatives, metadata, or model output to a cloud service in the MVP.

NFR4-003 - Long-running operations shall run in background queues while the UI remains responsive, using the PW-015 pipeline (bounded render stage, serialized model stage, resident model).

NFR4-003a - Responsiveness is measured against the FR4-039 scale target.

NFR4-004 - The application shall be crash-resumable. Mechanism, not assertion: every asset state change is a database transaction, and in-flight pipeline work follows the Phase 1 contract (atomic artifact writes, JSONL progress); on relaunch, state is reconstructed from the database and the progress log, and no asset can be in an ambiguous state.

NFR4-005 - The application shall record model, prompt, render, vocabulary, normalization, and export provenance per PW-013.

NFR4-006 - The application shall prefer conservative metadata over aggressive but unreliable automation.

NFR4-007 - The database schema shall carry a version; the application shall apply forward migrations automatically, shall refuse to open a database from a newer schema with a clear message, and shall never destructively migrate without a completed backup of the database file.

NFR4-008 - The application shall provide an export of approved-tag state in the Phase 3 session-file format, so the working database is never the only copy of accumulated review work.

## 11. Acceptance Criteria

AC4-001 - The user can import a folder of mixed RAW and JPEG files.

AC4-002 - The GUI can run whole-image analysis, subject-isolated analysis, or both.

AC4-003 - The GUI shows both whole-image and subject-isolated model outputs where available, with instance information for multi-subject frames.

AC4-004 - The user can approve, reject, or edit proposed tags, with confidence bands and evidence visible.

AC4-005 - The user can manage a controlled vocabulary and synonyms, with integrity violations caught at edit time.

AC4-006 - The GUI can apply Phase 3 batch normalization and show the governing rule and provenance for each result.

AC4-007 - The GUI writes approved tags to XMP sidecars without modifying proprietary RAW files.

AC4-008 - Existing XMP metadata is preserved, verified by round-trip diff.

AC4-009 - A sidecar edited in Lightroom Classic between GUI sessions is detected before export, re-merged against current content, and flagged in the UI and report; the externally added keyword survives, and a keyword deleted externally is not resurrected.

AC4-010 - Exported sidecars validate through ExifTool.

AC4-011 - The user can generate a compatibility/export report including post-export instructions.

AC4-012 - The app can resume after being closed mid-batch with no asset in an ambiguous state.

AC4-013 - The core engine remains callable by the `aisidecar` CLI, demonstrated by running a CLI batch against the same `AISidecarCore` build.

AC4-014 - A 5,000-image session scrolls and filters without perceptible stalls on the target hardware.

AC4-015 - Opening a database from an older schema migrates it forward after backing it up; opening one from a newer schema is refused with a clear message.

## 12. Future Groundwork Beyond the GUI MVP

The GUI phase should leave room for:

- visual embedding search (which then unlocks a "visually similar" scope for FR4-019);
- stronger species-specific assist models;
- OCR-specific passes using Apple Vision text recognition or a dedicated text model path;
- map/GPS filtering without AI-inferred GPS writes;
- Photo Mechanic or DAM profile exports;
- model comparison runs over the recorded provenance;
- user correction learning;
- a native XMP write engine replacing ExifTool behind `MetadataWriteEngine`, if app-distribution packaging ever demands it;
- direct plug-in integrations, if later justified.

## Reference Basis

This document shares the Reference Basis of the Phase 1 requirements (v0.2), incorporated by reference. Items load-bearing for this phase specifically:

- Adobe Lightroom Classic XMP sidecar behavior, including reading metadata from files: https://helpx.adobe.com/lightroom-classic/help/create-xmp-acr-files.html
- Capture One XMP sidecar reading and synchronization preferences: https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files
- ExifTool: https://exiftool.org/
- IPTC Photo Metadata: https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata
