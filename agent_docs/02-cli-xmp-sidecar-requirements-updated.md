# Phase 2 Requirements - CLI XMP Sidecar Writer

Version: 0.4
Date: 2026-06-12
Supersedes: 0.3
Builds on: Phase 1 Requirements v0.4 (`01-cli-raw-json-sidecar-requirements.md`)
Binary: `aisidecar` (subcommand: `write-xmp`)
Core library: `AISidecarCore`
Minimum deployment target: macOS 15
Default vision model: `gemma4:26b-a4b-it-qat`
Primary output artifact: XMP sidecar file

This document inherits the Project-Wide Conventions of the Phase 1 requirements: binary/subcommand structure, flag glossary, configuration resolution, error taxonomy, schema evolution, provenance principles, and concurrency model. They are not restated except where Phase 2 narrows or clarifies their use.

## 0. Changes from v0.3

This revision replaces the required ExifTool runtime dependency with a project-owned XMP sidecar implementation.

1. `MetadataWriteEngine` remains the policy boundary, but the required Phase 2 implementation is now `OwnedXMPSidecarEngine`, not ExifTool.
2. The owned engine is deliberately narrow: it creates, reads, merges, validates, and atomically writes `.xmp` sidecars only. It manages only `XMP-dc:Subject` and `XMP-lr:HierarchicalSubject` in Phase 2.
3. ExifTool shall not be required at runtime, shall not be packaged with the application, and shall not be part of Phase 2 acceptance. It may remain an optional developer compatibility check outside the shipped product.
4. Existing XMP preservation is now defined as semantic preservation. The engine may change whitespace, namespace-prefix ordering, attribute ordering, or XML formatting, but it must preserve all unmanaged metadata nodes and attributes in parsed form.
5. Phase 2 now requires owned XMP modules: `XMPDocumentParser`, `XMPDocumentWriter`, `XMPKeywordReader`, `XMPKeywordMerger`, `XMPMetadataSnapshot`, `XMPUnmanagedContentFingerprint`, and `OwnedXMPSidecarEngine`.
6. Post-write validation is performed by the owned parser and snapshot/fingerprint comparison, with Lightroom Classic and Capture One compatibility smoke checks retained for release evidence.
7. Export reports now record the owned XMP engine name/version and XMP writer recipe version instead of an ExifTool version.
8. Phase 2 adds four error codes to the additive project taxonomy: `E_SOURCE_MISSING`, `E_SOURCE_IDENTITY_MISMATCH`, `E_XMP_PARSE_FAILED`, and `E_XMP_UNSUPPORTED_RDF`.
9. The prior ExifTool-specific error `E_EXIFTOOL_MISSING` remains in the inherited additive taxonomy for compatibility, but it is not used by the Phase 2 runtime path.

## 0.1 Rereviewed Phase 1 State

Implemented and stable enough to build on:

- the SwiftPM package structure with `AISidecarCore` and `AISidecarCLI`;
- the shared `aisidecar` binary with `analyze`, `benchmark`, and `purge`;
- file/folder scanning, relative-path capture, source identity hashing, mirrored raw-sidecar output, atomic writes, existing-output policy, progress logs, summaries, and interruption/resume behavior;
- orientation-correct sRGB model-input rendering with model profiles, derivative provenance, derivative cache reuse, LRU eviction, debug derivative copies, and purge controls;
- two-resolution Apple Vision/Core Image subject isolation with deterministic instance selection, merge policy, failure records, and subject-isolation provenance;
- Ollama model preparation and execution behind `VisionModelRunner`, with mock and recorded-fixture runners;
- v1.3 prompts and response schemas, including ordinal confidence bands, candidate evidence, conditional biological `species`, and no Phase 1 `visible_text` field;
- raw JSON schema-evolution handling for additive `ai-sidecar-json/1.x` rewrites;
- no-XMP tests and benchmark checks.

Still pending for final Phase 1 signoff:

- full Milestone 9 benchmark matrix on the target machine;
- final default decisions for `ModelInputProfile`, `model_keep_alive`, and `stage_concurrency`;
- foreground-mask failure classification, tag-quality review, and manual multi-subject instance-selection spot checks;
- rights-cleared HEIC, TIFF, NEF, and RAF timing/format coverage or documented deferral;
- the final AC1-001 through AC1-015 acceptance pass, including live local-model, Apple Vision, and RAW decoder smoke evidence where required.

Phase 2 implementation shall not reopen Phase 1 rendering, isolation, prompting, or model-runtime design unless a Phase 2 acceptance failure exposes an actual interface defect.

## 0.2 Current Implementation Status

Phase 2 Milestones 0-2 are implemented as a non-writing preflight. The repository now has:

- `aisidecar write-xmp --help` and command-shape validation;
- Phase 2 export configuration defaults with `CLI > AISIDECAR_* > JSON config > built-in default` precedence;
- Phase 2 policy enums for source verification, XMP conflict policy, minimum confidence, and pair scope;
- placeholder schema identifiers `ai-sidecar-xmp-export/1.0` and `ai-sidecar-xmp-change-plan/1.0`;
- additive source-verification error codes `E_SOURCE_MISSING` and `E_SOURCE_IDENTITY_MISMATCH`;
- no-XMP regression coverage for `analyze`, `benchmark`, `purge`, and `analyze --export-model-inputs`;
- `RawJSONSidecarReader` plus `write-xmp --from-json` sidecar scanning and source resolution;
- source identity verification policies for `fail`, `warn`, and `skip`;
- `CandidateExtractor`, keyword text normalization, confidence-band filtering, de-duplication, skipped-candidate diagnostics, and conservative specific-tag filtering.

Milestones 0-2 intentionally do not parse or write XMP, create reports, or execute change plans. The `write-xmp --from-json` path resolves and extracts raw sidecar candidates, then stops before export execution. The remaining Phase 2 error codes, `E_XMP_PARSE_FAILED` and `E_XMP_UNSUPPORTED_RDF`, are introduced with the owned XMP engine milestone where they are first used.

## 1. Purpose

Phase 2 shall add `aisidecar write-xmp`: a conservative metadata-writing command that extracts accepted candidate terms from Phase 1 raw `.ai.json` sidecars and writes them to XMP sidecar files.

The command may either consume existing Phase 1 sidecars or run the Phase 1 analysis pipeline first. Its job is metadata export, not tag normalization, human review, OCR, embedded metadata editing, GUI state management, or camera-application automation.

## 2. Builds Upon Phase 1

Phase 2 shall reuse these Phase 1 modules from `AISidecarCore` without rewrites:

- `ImageScanner`, `SupportedImageType`, and `SourceImage`;
- `SourceIdentity` and the configured identity policy;
- `RawJSONSidecar`, `RawJSONSidecarWriter`, `SidecarNaming`, `AtomicFileWriter`, and the schema-evolution document wrapper;
- `AnalyzePipeline` for analyze-and-write mode;
- `ImageRenderer`, `DerivativeCache`, `ModelInputProfile`, and `SubjectIsolationService` indirectly through `AnalyzePipeline`;
- `VisionModelRunner`, `OllamaVisionRunner`, `MockVisionModelRunner`, and `RecordedFixtureRunner` indirectly through `AnalyzePipeline`;
- project-wide configuration resolution, structured errors, logging, progress logs, batch summaries, interruption monitoring, and no-XMP regression tests.

Phase 2 shall add a `RawJSONSidecarReader` if the current repository does not already expose one. The reader shall accept `ai-sidecar-json/1.x`, refuse higher major versions with `E_SCHEMA_UNSUPPORTED`, and preserve unknown fields only when a raw sidecar is intentionally rewritten.

## 3. Scope

The subcommand shall support two workflow styles:

```text
Write-from-json:
  aisidecar write-xmp --from-json <json-file-or-folder>
  existing .ai.json -> source verification -> extraction -> XMP

Analyze-and-write:
  aisidecar write-xmp <file-or-folder>
  image -> Phase 1 analysis -> raw .ai.json preservation -> extraction -> XMP
```

Implementation order shall be `write-from-json` first, then analyze-and-write. This ordering is normative because it isolates the XMP write layer before reusing the live model pipeline.

Explicitly not Phase 2:

- cross-image canonical tag normalization;
- batch consensus, folder-level subject consistency, or controlled vocabulary decisions;
- GUI review queue or human approval UI;
- OCR/text extraction or a `visible_text` output path;
- embedded metadata writing to JPEG, TIFF, HEIC, PNG, or DNG;
- writing AI-inferred camera, lens, date, exposure, GPS, named-person, exact-location, rating, label, develop/edit, Lightroom, Adobe Camera Raw, or Capture One adjustment fields;
- changing proprietary RAW files;
- modifying the behavior of `aisidecar analyze`, `benchmark`, `purge`, or `analyze --export-model-inputs` except for shared-library refactoring that keeps their acceptance behavior identical.

## 4. Command-Line Interface Requirements

Required command shapes:

```bash
aisidecar write-xmp --from-json <json-file-or-folder>
aisidecar write-xmp --from-json <json-folder> --recursive --source-root <image-root>

aisidecar write-xmp <image-file-or-folder> --mode both
```

Accepted project-wide flags in analyze-and-write mode:

```text
--mode <whole|subject|both>
--existing <skip|overwrite|fail>
--recursive
--output-dir <path>
--model <tag>
--model-endpoint <url>
--profile <name>
--config <path>
--log-level <error|warn|info|debug>
--log-format <text|json>
--dry-run
--debug-derivatives
--clear-derivative-cache-on-start
--clear-derivative-cache-after-success
--model-response-repair-attempts <n>
```

Accepted project-wide flags in write-from-json mode:

```text
--recursive
--output-dir <path>
--config <path>
--log-level <error|warn|info|debug>
--log-format <text|json>
--dry-run
```

Model, rendering, subject-isolation, and derivative-cache flags are invalid with `--from-json` because no analysis or derivative generation occurs. Passing them with `--from-json` shall fail as `E_CONFIG_INVALID` rather than being silently ignored.

Phase 2-specific flags:

```text
--from-json <path>
--source-root <path>
--source-verification <fail|warn|skip>
--write-flat-keywords / --no-write-flat-keywords
--write-hierarchical-keywords / --no-write-hierarchical-keywords
--backup-sidecars / --no-backup-sidecars
--xmp-conflict-policy <fail|merge|backup-and-merge>
--min-confidence <low|medium|high>
--allow-specific-tags
--pair-scope <union|raw-only|jpeg-only>
--write-ai-json / --no-write-ai-json
```

Default behavior shall be conservative:

```text
--write-flat-keywords             enabled
--write-hierarchical-keywords     enabled, but one-level only in Phase 2
--dry-run                         disabled
--backup-sidecars                 enabled
--xmp-conflict-policy             backup-and-merge
--min-confidence                  medium
--allow-specific-tags             disabled
--pair-scope                      union
--write-ai-json                   enabled in analyze-and-write mode
--source-verification             fail
```

FR2-CLI-001 - `--from-json` and positional image input are mutually exclusive.

FR2-CLI-002 - `--source-root` is valid only with `--from-json`. It maps each raw sidecar's recorded `source.relativePath` back to an image under the supplied root.

FR2-CLI-003 - `--write-ai-json` is meaningful only in analyze-and-write mode. With `--from-json`, it shall be accepted only if omitted; explicit use with `--from-json` shall fail as `E_CONFIG_INVALID`.

FR2-CLI-004 - In `write-xmp`, `--existing` governs raw `.ai.json` output produced by analyze-and-write. Existing XMP sidecars are governed by `--xmp-conflict-policy`.

## 5. Input and Source Verification Requirements

FR2-000 - `--from-json <json-file>` shall read one Phase 1 raw sidecar. `--from-json <folder>` shall scan for `.ai.json` files, recursively only when `--recursive` is supplied.

FR2-000a - Raw JSON sidecars shall be read under PW-012. Readers shall accept `ai-sidecar-json/1.x`, preserve unknown fields when rewriting a raw sidecar, and refuse unsupported major versions with `E_SCHEMA_UNSUPPORTED`.

FR2-000b - For `--from-json`, the source image shall be resolved in this order:

1. `--source-root` joined to the raw sidecar's recorded `source.relativePath`, when both are available;
2. the raw sidecar's recorded absolute `source.path`, when it exists;
3. a sibling file beside the raw sidecar whose name is the `.ai.json` basename with the `.ai.json` suffix removed, when it exists;
4. fail the file as `E_SOURCE_MISSING`.

FR2-000c - For `--from-json`, the current source identity shall be compared to the raw sidecar's recorded identity by default. A mismatch shall fail the file as `E_SOURCE_IDENTITY_MISMATCH` under `--source-verification fail`, shall continue with a report warning under `warn`, and shall not be computed under `skip`.

FR2-000d - `--source-verification skip` shall still require a resolvable source path unless `--output-dir` is supplied and the XMP target can be derived from `source.relativePath`. This is a staging exception, not the normal workflow.

FR2-000e - Analyze-and-write mode uses the current source identity produced by the Phase 1 scan and does not need the from-json source resolution path.

## 6. XMP Sidecar Naming and Output Tree Requirements

FR2-001 - In the Phase 2 MVP, every source image maps to a sidecar named `<base>.xmp`:

```text
_DSC1234.NEF  -> _DSC1234.xmp
_DSC1234.RAF  -> _DSC1234.xmp
_DSC1234.ARW  -> _DSC1234.xmp
_DSC1234.JPG  -> _DSC1234.xmp
_DSC1234.TIF  -> _DSC1234.xmp
_DSC1234.DNG  -> _DSC1234.xmp
```

FR2-001a - This sidecar-only rule is intentional even for formats that commonly support embedded metadata. Embedded writing is out of scope until a later phase because Phase 2 must prove merge, backup, validation, and reporting safely before touching image files.

FR2-001b - Without `--output-dir`, XMP sidecars shall be written beside the resolved source image. This is the normal Lightroom Classic and Capture One workflow.

FR2-001c - With `--output-dir`, XMP sidecars shall be written under the output directory, mirroring the source relative tree. This is a staging/export workflow; the report shall warn that the files must be moved beside the source images or explicitly imported/synchronized by the target application.

FR2-001d - Case-insensitive XMP target collisions shall be detected before writing. Affected files shall fail with `E_SIDECAR_COLLISION` without aborting the batch.

FR2-002 - Same-base-name files with different extensions share one XMP sidecar in normal sidecar workflows. The program shall detect such groups during scan/planning before any export begins.

FR2-002a - Merge semantics for shared sidecars: by default (`--pair-scope union`), candidate sets from all members of the group shall be unioned, normalized, de-duplicated case-insensitively, and written once, with per-candidate provenance recording which source image produced each term.

FR2-002b - `--pair-scope raw-only` shall restrict extraction to members classified as RAW-like source types. `--pair-scope jpeg-only` shall restrict extraction to `JPG`/`JPEG` members. If the requested scope selects no member, the group shall fail with `E_VALIDATION_FAILED` and a report entry.

FR2-002c - Exactly one merge-write shall be performed per XMP target per batch. Interleaved or sequential per-member writes to the same sidecar are forbidden.

FR2-002d - The export report shall list every detected same-base-name group, the scope applied, the selected members, skipped members, per-source contribution counts, and resulting target XMP path.

FR2-003 - Detected groups shall produce a warning in the report. The warning is informational when `--pair-scope union` is used and becomes a policy warning when a restrictive scope is used.

FR2-004 - Phase 2 shall not modify source image files. Proprietary RAW file hashes shall be verifiably unchanged after any run, and the same non-modification rule shall also hold for JPEG, TIFF, HEIC, PNG, and DNG during the sidecar-only MVP.

## 7. Candidate Extraction Requirements

FR2-013 - The program shall extract candidate terms from Phase 1 model JSON using the Phase 1 response schema, including conditional `species` candidates when present, and respecting schema evolution under PW-012.

FR2-013a - Candidate-bearing fields in Phase 1 v1.3 responses are:

```text
genre_or_photography_type
species
main_subjects
secondary_subjects
scene_context
habitat_or_setting
behavior_or_action
proposed_keywords
```

The extractor shall ignore `summary` and `uncertainty_notes` for export.

FR2-013b - Candidate records shall preserve these fields in the intermediate extraction record where available:

```json
{
  "term": "string",
  "confidence": "high | medium | low",
  "evidence": "string or null",
  "source_field": "proposed_keywords",
  "input_role": "whole_image | subject_isolated",
  "source_sidecar": "path",
  "source_image": "path",
  "model_run_index": 0
}
```

FR2-014 - If both whole-image and subject-isolated runs exist, their contributions shall remain distinct in the extraction record and in report provenance.

FR2-015 - Whole-image candidates shall be preferred for scene, setting, habitat, lighting, background, and broad photographic context. The subject-isolated schema cannot produce scene or habitat fields by construction.

FR2-016 - Subject-isolated candidates shall be preferred for subject morphology, object/species detail, and fine subject classification.

FR2-017 - Phase 2 shall not perform cross-image normalization. De-duplication is within a single image or within a same-base-name group only.

FR2-018 - Candidates below `--min-confidence` shall not be exported. The band ordering is `low < medium < high`; the default threshold is `medium`. Numeric confidence shall not be introduced.

FR2-019 - Specific tags — species names, binomials, named places, named events, named people, rare species, and exact-location implications — shall be excluded unless `--allow-specific-tags` is supplied.

FR2-019a - Specific-tag detection in Phase 2 is heuristic and shall err toward exclusion. It shall include at least: binomial patterns, capitalized multi-word terms, candidates from the `species` field, terms with evidence indicating an exact identification, and terms matching obvious proper-place/person/event patterns. Phase 3's vocabulary `requires_review` field replaces this heuristic.

FR2-019b - Broad taxonomy and generic subject terms such as `bird`, `shorebird`, `raptor`, `flower`, `tree`, `mammal`, `architecture`, `portrait`, and `landscape` are not specific merely because they describe a subject.

FR2-019c - Skipped terms shall be reported with a reason: `below_confidence_threshold`, `specific_tag_policy`, `contains_hierarchy_separator`, `empty_after_normalization`, `duplicate`, `disabled_flat_export`, or `disabled_hierarchical_export`.

## 8. Keyword Text and Metadata Mapping Requirements

FR2-006 - Accepted flat keywords shall be written to `XMP-dc:Subject` when flat keyword export is enabled.

FR2-006a - Keyword text normalization, applied before de-duplication and writing: Unicode NFC normalization; leading/trailing whitespace trimmed; internal whitespace runs collapsed to a single space. Model casing is preserved in Phase 2.

FR2-006b - Terms containing the hierarchy separator `|` shall be rejected from export entirely — flat and hierarchical — with a warning in the report. Silently mangling a term is worse than dropping a tag the user can add by hand.

FR2-006c - Empty terms after normalization shall be dropped silently from write output but counted in extraction diagnostics.

FR2-006d - De-duplication shall be case-insensitive after normalization, but the first accepted casing shall be preserved in the write plan. If the same normalized term appears in multiple roles or source fields, all provenance entries shall be retained under one exported term.

FR2-007 - Accepted hierarchical keywords shall be written to `XMP-lr:HierarchicalSubject` when hierarchical export is enabled.

FR2-007a - Phase 2 shall not invent parent paths. Hierarchical export writes one-level entries identical to the accepted flat term unless a future schema supplies a safe hierarchy. No `|` separator shall be introduced by Phase 2.

FR2-008 - Caption/description writing shall remain disabled and unavailable in Phase 2. A future flag may write only user-approved generated text to `XMP-dc:Description`; no such flag shall ship in the MVP.

FR2-009 - Title writing shall remain disabled and unavailable in Phase 2. A future flag may write only user-approved generated text to `XMP-dc:Title`; no such flag shall ship in the MVP.

FR2-010 - Rating and color-label writing shall remain disabled and unavailable in Phase 2.

FR2-011 - The program shall not write AI-inferred camera, lens, date, exposure, GPS, named-person, exact-location, copyright, creator, credit, or rights facts.

FR2-012 - The program shall not write Adobe Camera Raw, Lightroom develop, or Capture One adjustment settings.

## 9. XMP Merge, Conflict, Backup, and Validation Requirements

FR2-020 - Existing XMP sidecars shall be read before writing unless `--xmp-conflict-policy fail` is selected, in which case the file shall be marked `E_SIDECAR_EXISTS` and left unchanged.

FR2-021 - Existing flat keywords shall be preserved by default.

FR2-022 - Existing hierarchical keywords shall be preserved by default.

FR2-023 - Unknown XMP namespaces shall be preserved semantically.

FR2-023a - Semantic preservation means unmanaged XML elements, attributes, namespace declarations, RDF descriptions, bags, sequences, alternatives, and scalar properties that the owned engine can parse shall still be present after the write. Byte-for-byte preservation, whitespace preservation, namespace-prefix ordering, and attribute ordering are not required.

FR2-024 - Existing develop/edit settings shall be preserved semantically. This includes Lightroom, Adobe Camera Raw, Capture One, and other application namespaces so long as they are represented as parseable XMP/RDF/XML.

FR2-025 - Sidecar updates shall be merge-based, not full replacement of metadata meaning. The engine may serialize a new XML document, but the only intentional metadata changes shall be additions to the managed keyword fields.

FR2-026 - Sidecar writes shall be atomic: create or copy to a temporary file in the destination directory, apply the write plan to the temporary file, validate it, then replace the target.

FR2-027 - Existing sidecars shall be backed up before modification when `--backup-sidecars` is enabled. Backups shall use a deterministic suffix:

```text
<name>.xmp.bak-<ISO-8601-timestamp>
```

Backups shall be referenced in the export report.

FR2-027a - `--xmp-conflict-policy fail` means existing XMP sidecars are not modified.

FR2-027b - `--xmp-conflict-policy merge` means existing sidecars are merged. Backups are controlled by `--backup-sidecars`.

FR2-027c - `--xmp-conflict-policy backup-and-merge` means existing sidecars are merged only after a backup is created. Passing `--xmp-conflict-policy backup-and-merge --no-backup-sidecars` shall fail at startup as `E_CONFIG_INVALID`.

FR2-028 - After writing, the program shall re-read the sidecar with the owned parser and validate both addition and preservation:

1. every expected flat keyword is present when flat export is enabled;
2. every expected hierarchical keyword is present when hierarchical export is enabled;
3. pre-existing flat keywords survived;
4. pre-existing hierarchical keywords survived;
5. pre-existing unmanaged XMP content survived semantically, including unknown namespaces and develop/edit namespaces visible to the owned parser.

FR2-028a - Preservation validation shall compare a pre-write and post-write `XMPMetadataSnapshot`, excluding only the target fields being intentionally updated. Bag/list fields shall be compared as sets when order is not semantically meaningful.

FR2-028b - Preservation validation shall also compare an `XMPUnmanagedContentFingerprint` built from all non-managed XML/RDF nodes and attributes that the parser recognizes. The fingerprint is semantic, not textual.

FR2-028c - On validation failure: the backup shall be restored when available, the file shall be marked `E_VALIDATION_FAILED`, the failure shall be detailed in the export report, and the batch shall continue. A validation failure shall never leave the restored-from state ambiguous.

FR2-029 - Metadata writing shall go through a `MetadataWriteEngine` protocol. The Phase 2 implementation shall be `OwnedXMPSidecarEngine`, a project-owned XMP sidecar engine.

FR2-029a - `OwnedXMPSidecarEngine` shall not attempt to become a general metadata library. It shall support `.xmp` sidecar files and only the Phase 2 managed fields: `XMP-dc:Subject` and `XMP-lr:HierarchicalSubject`.

FR2-029b - ExifTool shall not be required, invoked, or packaged by the Phase 2 runtime. Optional developer scripts may use external metadata tools for manual comparison, but acceptance shall not depend on them.

FR2-029c - The owned engine shall be split into explicit modules:

```text
XMPDocumentParser
XMPDocumentWriter
XMPKeywordReader
XMPKeywordMerger
XMPMetadataSnapshot
XMPUnmanagedContentFingerprint
OwnedXMPSidecarEngine
```

FR2-029d - For a new sidecar, the writer shall generate a canonical RDF/XML XMP packet with the XMP wrapper, `rdf:RDF`, an `rdf:Description rdf:about=""`, `dc:subject/rdf:Bag`, and, when enabled, `lr:hierarchicalSubject/rdf:Bag`.

FR2-029e - For an existing sidecar, the parser shall locate or create a suitable `rdf:Description`, locate or create the two managed bags, read existing `rdf:li` values, merge new normalized values, and leave unmanaged nodes semantically intact.

FR2-029f - Unsupported but well-formed XMP/RDF shapes that cannot be safely merged shall fail closed with `E_XMP_UNSUPPORTED_RDF` rather than being rewritten. Malformed XML or unreadable XMP shall fail as `E_XMP_PARSE_FAILED`.

FR2-029g - The engine wrapper shall expose dry-run rendering of intended changes so dry-run, write, validation, and reporting share one change-plan representation.

FR2-029h - Owned-engine parse, merge, write, and validation failures shall map to structured errors with a bounded diagnostic excerpt retained in the report. Diagnostics shall not include full sidecar contents unless a debug mode is explicitly added later.

## 10. Output and Reporting Requirements

FR2-030 - Phase 2 shall produce or update `.xmp` sidecars only from `aisidecar write-xmp`.

FR2-031 - Analyze-and-write mode shall preserve or create raw `.ai.json` sidecars unless `--no-write-ai-json` is supplied. `--no-write-ai-json` still records model-run provenance in memory for the export report, but it is not the default because auditability matters.

FR2-032 - Folder runs shall produce:

```text
xmp-export-progress-<ISO-8601-timestamp>.jsonl
xmp-export-report-<ISO-8601-timestamp>.json
xmp-export-summary-<ISO-8601-timestamp>.md
```

These files shall be written under `--output-dir` when supplied, otherwise beside the scan root or JSON scan root.

FR2-032a - The export report schema identifier shall be `ai-sidecar-xmp-export/1.0`.

FR2-032b - The dry-run change-plan schema identifier shall be `ai-sidecar-xmp-change-plan/1.0`.

FR2-032c - Progress records shall be self-contained JSONL entries and shall be flushed after each completed XMP target, not after each source member. This matches the one-write-per-XMP-target rule.

FR2-033 - Dry-run mode shall show the complete intended XMP change plan — per target sidecar: source members, tags to add, existing tags to preserve, tags skipped and why, groups detected, conflicts, backup plan, validation plan, and whether the run would write or fail — without modifying sidecars or source files.

FR2-034 - Export reports shall list files processed, sidecars created, sidecars modified, tags added with provenance, tags skipped with reasons, same-base-name groups and applied scope, conflicts, validation results, backups created/restored, source-verification results, owned XMP engine name/version, XMP writer recipe version, and structured errors with codes.

FR2-034a - Export summaries shall end with post-export application instructions: Lightroom Classic requires the user to select already-imported photos and invoke Metadata > Read Metadata from Files to import outside sidecar changes; Capture One behavior depends on Metadata preferences, especially Auto Sync Sidecar XMP / Load / Full Sync. The summary shall state both every time.

FR2-034b - Single-file runs shall print the same essential information to stdout. A full JSON report for single-file runs is optional unless `--dry-run` is used, in which case the change plan shall be emitted.

## 11. Acceptance Criteria

AC2-001 - The program can generate an XMP sidecar from one image using a fresh model run.

AC2-002 - The program can generate an XMP sidecar from an existing Phase 1 `.ai.json` sidecar.

AC2-003 - Accepted flat keywords appear in `XMP-dc:Subject`.

AC2-004 - Accepted hierarchical keywords appear in `XMP-lr:HierarchicalSubject` when enabled.

AC2-005 - Existing keywords are preserved after export, verified by the round-trip diff.

AC2-006 - Existing unknown XMP namespaces are preserved after export, verified by the round-trip diff.

AC2-007 - Source image file hashes remain unchanged after export, including proprietary RAW files.

AC2-008 - A RAW+JPEG pair produces exactly one XMP sidecar containing the unioned, de-duplicated candidates with per-source provenance, and the group is reported.

AC2-009 - Dry-run mode produces a complete proposed-change plan without writing files.

AC2-010 - Exported sidecars can be read back by the owned XMP parser, validation records the owned engine name/version and writer recipe version, and release smoke checks confirm Lightroom Classic and Capture One can import the written keywords.

AC2-011 - A term containing `|` is rejected with a warning rather than exported or mangled.

AC2-012 - With defaults, no species-level or named-place tag is exported; with `--allow-specific-tags`, eligible specific terms are exported.

AC2-013 - A simulated validation failure restores the backup and the batch continues.

AC2-014 - In `--from-json` mode, a source identity mismatch fails by default and succeeds with a warning under `--source-verification warn`.

AC2-015 - In `--from-json` mode, `--source-root` correctly maps a mirrored raw-sidecar tree back to the original source-image tree.

AC2-016 - `--output-dir` writes a mirrored XMP staging tree and detects case-insensitive target collisions before writing.

AC2-017 - `--xmp-conflict-policy fail`, `merge`, and `backup-and-merge` all behave as specified, including rejecting `backup-and-merge` with `--no-backup-sidecars`.

AC2-018 - `aisidecar analyze`, `aisidecar benchmark`, `aisidecar purge`, and `aisidecar analyze --export-model-inputs` still create or modify no `.xmp` files after Phase 2 code is merged.

AC2-019 - Folder export reports include Lightroom Classic and Capture One post-export instructions.

AC2-020 - Phase 2 release includes either archived Phase 1 final signoff evidence or an explicit release note listing any deferred Phase 1 evidence. Implementation may finish before this, but release may not.

## 12. Future Groundwork

Phase 2 establishes the metadata-writing foundation for Phase 3 and Phase 4:

- `MetadataWriteEngine` and the owned `OwnedXMPSidecarEngine`;
- `XMPDocumentParser`, `XMPDocumentWriter`, `XMPKeywordReader`, `XMPKeywordMerger`, `XMPMetadataSnapshot`, and `XMPUnmanagedContentFingerprint`;
- raw-sidecar reading and source verification;
- candidate extraction with role/source provenance;
- keyword text normalization and conservative export policy;
- same-base-name group planning;
- XMP naming, output staging, semantic merge, backup, restore, and validation;
- dry-run change planning;
- export report and progress schemas;
- no-XMP regression protection around Phase 1 commands.

Phase 3 shall extend this with batch-level tag normalization, vocabulary review, canonical casing, controlled hierarchy construction, and folder-level subject consistency. Phase 4 shall wrap the same write/merge/validation layer in a GUI.

## Reference Basis

Primary compatibility references checked for this revision:

- Adobe XMP specifications: https://developer.adobe.com/xmp/docs/xmp-specifications/
- ISO 16684-1 / XMP data model and serialization overview: https://www.iso.org/obp/ui/
- W3C RDF/XML syntax and RDF container vocabulary: https://www.w3.org/TR/rdf-syntax-grammar/
- Apple Foundation XML document processing: https://developer.apple.com/documentation/foundation/xmldocument
- IPTC Photo Metadata Standard 2025.1, Keywords implemented as `dc:subject`: https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata
- Adobe Lightroom Classic sidecar and metadata actions: https://helpx.adobe.com/lightroom-classic/help/create-xmp-acr-files.html and https://helpx.adobe.com/lightroom-classic/help/advanced-metadata-actions.html
- Capture One XMP sidecar behavior and Auto Sync Sidecar XMP settings: https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files
