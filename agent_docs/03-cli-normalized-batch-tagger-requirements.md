# Phase 3 Requirements - CLI Normalized Batch Tagger

Version: 0.3
Date: 2026-06-12
Supersedes: 0.2
Builds on: Phase 1 Requirements v0.4 (`01-cli-raw-json-sidecar-requirements.md`) and Phase 2 Requirements v0.4 (`02-cli-xmp-sidecar-requirements-updated.md`)
Binary: `aisidecar` (subcommands: `normalize`, `apply-session`)
Core library: `AISidecarCore`
Minimum deployment target: macOS 15
Default vision model: `gemma4:26b-a4b-it-qat`
Primary output artifacts: normalization session file, normalized XMP sidecar files, batch normalization report

This document inherits the Project-Wide Conventions of the Phase 1 requirements and the owned-XMP metadata-writing requirements of Phase 2. They are not restated except where Phase 3 narrows or clarifies their use.

## 0. Changes from v0.2

This revision updates Phase 3 for the Phase 2 decision to use a project-owned XMP sidecar engine instead of ExifTool.

1. Phase 3 now inherits `OwnedXMPSidecarEngine` behind `MetadataWriteEngine`. It no longer inherits, requires, invokes, packages, reports, or validates through ExifTool.
2. Existing XMP preservation is semantic, not byte-for-byte. Phase 3 relies on Phase 2's owned parser, `XMPMetadataSnapshot`, and `XMPUnmanagedContentFingerprint` validation.
3. XMP parse and unsupported-RDF failures are inherited from Phase 2: malformed XML fails as `E_XMP_PARSE_FAILED`; well-formed but unsafe RDF/XMP shapes fail as `E_XMP_UNSUPPORTED_RDF`.
4. Phase 3 writes multi-level hierarchical keywords only from the controlled vocabulary's `canonical_path`, never from raw model text containing the hierarchy separator.
5. `normalize --from-json` and `apply-session` inherit Phase 2 source-resolution and source-verification behavior, including `--source-root`, `--source-verification`, `E_SOURCE_MISSING`, and `E_SOURCE_IDENTITY_MISMATCH`.
6. `apply-session` is explicitly model-free, render-free, and analysis-free. It consumes a normalization session file, verifies source identity, builds normalized XMP write plans, and writes through the owned XMP engine.
7. Reports now record the owned XMP engine name/version and XMP writer recipe version, not an ExifTool version.
8. Acceptance criteria are updated so sidecar validation is performed by the owned parser plus Lightroom Classic and Capture One release smoke checks.

For continuity, all substantive v0.2 changes remain active: the single `aisidecar` binary, JSON-only vocabulary, vocabulary integrity rules, hierarchy-aware consensus, removal of the undefined `batch-folder-context` mode, `--unknown-subject-policy`, measurable conflict semantics, session identity binding, and ordinal confidence bands.

## 1. Purpose

Phase 3 shall expand the command-line toolchain so whole-folder scans produce consistent, normalized metadata. The target workflow is a real photographic batch: multiple frames often contain the same subject, event, habitat, or scene type, while the model may describe those things inconsistently across files.

This phase adds a controlled vocabulary, synonym mapping, batch-level consensus, user-supplied session context, normalized write plans, and normalization reports. It remains command-line only.

Phase 3 is the policy and decision layer. It does not replace Phase 2's sidecar engine. It prepares normalized terms and provenance, then hands the write plan to the same `MetadataWriteEngine` and `OwnedXMPSidecarEngine` used by `aisidecar write-xmp`.

## 2. Builds Upon Phase 2

Phase 3 shall reuse, from `AISidecarCore`:

- scanner, identity, and batch-processing modules;
- Phase 1 whole-image and subject-isolated model runs through `AnalyzePipeline`;
- raw JSON sidecar reading, schema-evolution handling, and source verification;
- candidate extraction records with ordinal confidence bands, evidence strings, input role, source field, model-run index, and source provenance;
- keyword text normalization and export policy from Phase 2 where applicable;
- same-base-name group planning and `--pair-scope <union|raw-only|jpeg-only>` behavior;
- XMP target naming and `--output-dir` staging behavior;
- dry-run change planning;
- export progress logs, export reports, and human-readable summaries;
- `MetadataWriteEngine` with the required `OwnedXMPSidecarEngine` implementation;
- `XMPDocumentParser`, `XMPDocumentWriter`, `XMPKeywordReader`, `XMPKeywordMerger`, `XMPMetadataSnapshot`, and `XMPUnmanagedContentFingerprint`;
- semantic XMP merge, backup, restore, validation, and failure behavior.

Phase 3 shall not contain a separate XMP writer. Any normalization-specific export behavior must be expressed as a normalized write plan consumed by Phase 2's owned sidecar engine.

## 3. Scope

Phase 3 shall normalize tags across images in a batch, folder, explicit file list, or existing set of Phase 1 `.ai.json` sidecars.

It shall solve these first-order problems:

```text
Model says "egret" on one frame and "white heron" on another.
Model says "marsh" on one frame and "wetland" on another.
Model says "bird" on several frames and "Great Blue Heron" on a few stronger frames.
The user knows the folder subject and wants consistent tags applied across the set.
The model produces redundant flat tags that should map into one controlled hierarchy.
A RAW+JPEG pair shares one XMP sidecar and must receive one normalized write plan.
```

It shall not implement a GUI review workflow, face recognition, individual identity tracking, automated species certainty, OCR/text extraction, embedded metadata writing, or direct Lightroom/Capture One catalog manipulation.

## 4. Command-Line Interface Requirements

Required command shapes:

```bash
# Full pipeline: analyze images, normalize, write session + XMP
aisidecar normalize <folder> --recursive --mode both

# Build a normalization session from existing Phase 1 sidecars without model runs
aisidecar normalize --from-json <json-folder> --recursive --source-root <image-root>

# Build a normalization session only; defer XMP export
aisidecar normalize <folder> --session-only

# Write XMP from a previously produced session file, no model runs
aisidecar apply-session <normalization-session-file>

# Write from a session into a staged XMP tree rather than beside source images
aisidecar apply-session <normalization-session-file> --output-dir <xmp-staging-root>
```

Accepted project-wide flags in analyze-and-normalize mode:

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

Accepted project-wide flags in `normalize --from-json` mode:

```text
--recursive
--output-dir <path>
--config <path>
--log-level <error|warn|info|debug>
--log-format <text|json>
--dry-run
```

Accepted project-wide flags in `apply-session` mode:

```text
--output-dir <path>
--config <path>
--log-level <error|warn|info|debug>
--log-format <text|json>
--dry-run
```

Model, rendering, subject-isolation, derivative-cache, and model-response-repair flags are invalid with `apply-session` because no model or image-analysis work occurs. They are also invalid with `normalize --from-json` because existing Phase 1 sidecars are the input. Passing invalid flags shall fail as `E_CONFIG_INVALID` rather than being silently ignored.

Phase 2 export flags accepted by `normalize` and `apply-session` where applicable:

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

Phase 3-specific flags:

```text
--vocabulary <path>
--normalization-mode <off|single-image|batch-conservative>
--session-subject <text>
--session-habitat <text>
--session-event <text>
--consensus-threshold <float 0..1>
--allow-session-subject-propagation
--unknown-subject-policy <reject|write-unnormalized>
--session-only
--write-report <path>
--allow-stale
```

Defaults:

```text
--normalization-mode              batch-conservative
--min-confidence                  medium
--consensus-threshold             0.6
--unknown-subject-policy          reject
--source-verification             fail
--write-flat-keywords             enabled
--write-hierarchical-keywords     enabled
--backup-sidecars                 enabled
--xmp-conflict-policy             backup-and-merge
--pair-scope                      union
--allow-stale                     disabled
```

FR3-CLI-001 - `--from-json` and positional image input are mutually exclusive for `normalize`.

FR3-CLI-002 - `--source-root` is valid only with `normalize --from-json` and `apply-session` when the session was produced from staged or moved sidecars. It resolves recorded source-relative paths back to current source images.

FR3-CLI-003 - `--write-ai-json` is meaningful only in analyze-and-normalize mode. With `normalize --from-json` or `apply-session`, explicit use shall fail as `E_CONFIG_INVALID`.

FR3-CLI-004 - In `normalize`, `--existing` governs raw `.ai.json` output produced by analysis. Existing XMP sidecars are governed by `--xmp-conflict-policy`.

FR3-CLI-005 - `--session-only` suppresses XMP writing but shall still produce the normalization session file and report. It shall not create, modify, back up, or validate `.xmp` files.

FR3-CLI-006 - The v0.1 `batch-folder-context` mode remains removed. The name is reserved for a future revision that defines folder-level co-occurrence as weak evidence for mid-specificity tags.

FR3-CLI-007 - `--require-review-specific-tags` shall not exist. Review requirements are vocabulary policy through `requires_review`, not invocation policy.

## 5. Controlled Vocabulary Requirements

FR3-001 - The program shall support a local controlled vocabulary file.

FR3-002 - The vocabulary format shall be JSON, validated against a published JSON Schema shipped with the project. YAML shall not be supported.

FR3-002a - The vocabulary file shall carry its own `schema_version` (`ai-sidecar-vocabulary/1.0`) governed by PW-011/PW-012.

FR3-002b - Loaders shall compute a SHA-256 content hash of the vocabulary file after canonical byte reading. This hash is the vocabulary identity recorded in sessions and reports.

FR3-003 - Each vocabulary entry shall support:

```text
canonical_path                e.g. "Wildlife|Birds|Herons and Egrets|Great Egret"
flat_keyword                  exported flat form, e.g. "Great Egret"
namespace                     one of the FR3-004 namespaces
parent_path                   null for root entries; otherwise an existing canonical_path
synonyms                      array of strings
requires_review               default: true for Species/Taxonomy, People,
                              Location Type entries naming exact places,
                              rare species, exact-location implications;
                              false otherwise
auto_apply_allowed            default: false for entries with requires_review
mutually_exclusive_group      optional string; entries sharing a group value
                              cannot both be true of one image
export_flat_keyword           default: true
export_hierarchical_keyword   default: true
notes                         optional text
```

FR3-003a - Canonical paths shall be unique across the vocabulary. Violations shall fail loading with `E_VOCABULARY_INVALID`.

FR3-003b - A synonym shall map to exactly one canonical path. A synonym appearing under two entries, or a string that is both a canonical term of one entry and a synonym of another, shall fail loading with `E_VOCABULARY_INVALID` and a listing of the collisions.

FR3-003c - The hierarchy implied by `parent_path` shall be a strict tree: no cycles and no orphans. Every non-root `parent_path` must exist.

FR3-003d - Text folding for synonym matching shall use Unicode NFC, case folding, and whitespace collapsing. Diacritics shall not be folded, and stemming shall not be performed.

FR3-003e - Matching preserves and outputs the canonical spelling and casing of the vocabulary entry.

FR3-003f - `canonical_path` uses `|` as the vocabulary hierarchy separator. Empty path levels are invalid. Individual path levels may not contain literal `|` after parsing.

FR3-003g - Raw model candidates containing `|` remain invalid for direct export under Phase 2 rules. Phase 3 may export hierarchical keywords containing `|` only when the separator is introduced by a valid controlled-vocabulary `canonical_path` or by a user session subject matched to that vocabulary.

FR3-003h - `flat_keyword` shall not contain `|`. If a vocabulary entry violates this, loading fails with `E_VOCABULARY_INVALID`.

FR3-004 - The vocabulary shall support at least these namespaces:

```text
Subject
Species / Taxonomy
Habitat
Behavior
Scene
Location Type
Lighting
Composition
Technical Quality
Event
People
Objects
Text / Signage
Workflow
```

FR3-005 - Vocabulary defaults shall be conservative. Entries in `Species / Taxonomy`, `People`, named-place `Location Type`, rare-species, exact-location, and named-event areas shall default to `requires_review = true` and `auto_apply_allowed = false` unless explicitly overridden by the vocabulary file.

FR3-006 - The normalizer shall expose a vocabulary loader API usable by both CLI and GUI targets. The GUI may edit vocabulary files later, but Phase 3 owns the validation and canonicalization semantics.

FR3-007 - The program shall support a user-supplied seed subject through `--session-subject`.

FR3-008 - User-supplied session context shall be treated as user evidence, not model evidence, throughout aggregation, provenance, and reporting.

## 6. Batch Normalization Requirements

FR3-009 - The program shall create one batch normalization session for each folder, explicit file list, or `.ai.json` sidecar collection.

FR3-010 - The session shall aggregate eligible candidates from all images before writing final XMP sidecars unless `--normalization-mode single-image` is selected.

FR3-011 - For each canonicalized candidate, the session shall compute: supporting image count, eligible image count, agreement frequency, confidence-band distribution, source-field distribution, and contributing input roles. Agreement frequency is the primary consensus signal; confidence bands are secondary filters and tiebreakers. Self-reported model confidence shall never outrank cross-image agreement in a decision rule.

FR3-012 - The session shall distinguish per-image tags from batch-level tags.

FR3-013 - Broad tags with high agreement, such as `Bird`, `Wildlife`, `Outdoor`, `Wetland`, or `Portrait`, may be propagated conservatively across the batch.

FR3-013a - Propagation rule: a candidate is batch-propagatable when, after `--min-confidence` filtering of per-image observations, `agreement_frequency >= consensus_threshold`, the vocabulary entry has `auto_apply_allowed = true`, and no conflicting candidate itself meets the consensus threshold.

FR3-013b - Counting is hierarchy-aware. An observation of a descendant supports every ancestor on its canonical path. A frame tagged `Great Blue Heron` counts as support for `Herons and Egrets`, `Birds`, and `Wildlife`.

FR3-013c - `--min-confidence` filters observations before frequency counting, not after.

FR3-013d - The normalizer shall compute agreement over eligible images. Images with model failure, unsupported format, source-verification failure, or no usable Phase 1 sidecar are excluded from the denominator and listed in the report.

FR3-014 - Specific tags — entries with `requires_review = true` — shall not be propagated automatically from model evidence regardless of agreement level.

FR3-015 - When `--session-subject` is supplied, the program may apply that subject to all non-conflicting images in the session only if `--allow-session-subject-propagation` is also set.

FR3-016 - A subject propagated from session context shall record `source = user_session_context`, never `source = model`.

FR3-017 - The normalizer shall collapse duplicate and synonymous candidates into a single canonical path.

FR3-018 - The normalizer shall remove redundant flat keywords that merely repeat canonical hierarchy nodes, according to each vocabulary entry's export rules.

FR3-019 - The normalizer shall avoid destructive simplification. Mapping upward to a defensible ancestor is allowed (`white heron` -> `Herons and Egrets`). Mapping sideways or downward to a more specific node (`white heron` -> `Great Egret`) is forbidden unless a vocabulary synonym/rule or user session context explicitly supports it.

FR3-020 - The normalizer shall maintain separate provenance records for whole-image observations, subject-isolated observations, normalized batch context, and user session context.

## 7. Same-Subject Folder Requirements

FR3-021 - The same-subject assumption shall be activated only by explicit user flags, never hidden inference.

FR3-022 - `--session-subject` accepts plain text and shall be matched against the vocabulary using FR3-003d folding.

FR3-023 - If `--session-subject` cannot be matched to a vocabulary entry, `--unknown-subject-policy` governs:

```text
reject              default; fail the session before any model run or write
write-unnormalized  record and export it as a flat user keyword with
                    source = user_session_context and no hierarchy
```

The default is `reject` because a session subject important enough to propagate across a folder is important enough to canonicalize first.

FR3-024 - Folder-level subject propagation shall warn when individual model observations conflict with the supplied subject.

FR3-024a - Conflict definition: image observations conflict with the session subject when they support, at or above `--min-confidence`, a vocabulary entry that is either (a) a sibling of the session subject, meaning same `parent_path` and different leaf, or (b) a member of the same `mutually_exclusive_group`. Mere absence of support is not conflict.

FR3-025 - The session report shall list images that did not support the session subject at or above the minimum band, and separately, images that conflicted under FR3-024a. Conflicted images shall not receive the propagated subject. Weakly supporting images may receive it, with weak support noted in provenance.

FR3-026 - Phase 3 makes no claim of individual animal or person identity tracking. Same-subject behavior is batch-context normalization, not biometric or individual identity recognition.

## 8. Normalization Session File Requirements

FR3-027 - The program shall write a normalization session file before any XMP export unless the command is a dry-run that explicitly requests report-only output.

FR3-027a - The session file schema identifier shall be `ai-sidecar-normalization/1.0`.

FR3-027b - The session file shall be valid JSON and shall be governed by PW-011/PW-012.

Minimum structure:

```json
{
  "schema_version": "ai-sidecar-normalization/1.0",
  "session": {
    "normalization_mode": "batch-conservative",
    "created_at": "ISO-8601",
    "scan_root": "string or null",
    "source_root": "string or null",
    "output_dir": "string or null"
  },
  "vocabulary": {
    "path": "string",
    "sha256": "string",
    "schema_version": "ai-sidecar-vocabulary/1.0"
  },
  "resolved_configuration": {},
  "xmp_writer": {
    "engine": "OwnedXMPSidecarEngine",
    "engine_version": "string",
    "writer_recipe_version": "string"
  },
  "source_ai_sidecars": [],
  "source_assets": [],
  "same_base_name_groups": [],
  "batch_candidates": [],
  "per_asset_decisions": [],
  "xmp_write_plans": [],
  "warnings": [],
  "errors": []
}
```

FR3-028 - The session file shall record the vocabulary SHA-256 content hash. The human-readable version string is a label; the hash is the identity.

FR3-029 - The session file shall record normalization mode, thresholds, session-subject inputs, pair scope, source-verification policy, output-dir behavior, and export flags — the complete resolved configuration per PW-008.

FR3-030 - The session file shall be usable as input to `apply-session` without re-running the vision model.

FR3-030a - Each `per_asset_decisions` entry shall bind to the asset's source identity hash, not only its path. `apply-session` shall verify identities before writing. A mismatch fails that asset with `E_SESSION_STALE` and continues the batch.

FR3-030b - `--allow-stale` may force an `apply-session` write despite source identity mismatch. The report shall record the override per asset. This flag shall not be available by configuration file default; it must be explicit on the invocation.

FR3-030c - A normalization session shall not store a stale copy of the current XMP sidecar as the source of truth for later writeback. `apply-session` must read the current sidecar at write time and merge against current disk content.

FR3-030d - The session may store the planned XMP target path, but `apply-session` shall be able to recompute target paths from current source resolution and `--output-dir`. Recomputed paths shall be reported when they differ from stored paths.

## 9. XMP Export Requirements

FR3-031 - Phase 3 shall use the Phase 2 `MetadataWriteEngine`, `OwnedXMPSidecarEngine`, backup, restore, semantic validation, and same-base-name group behavior unchanged.

FR3-031a - Phase 3 shall not invoke ExifTool or any other external metadata command-line tool for required runtime behavior.

FR3-032 - Phase 3 shall write only normalized tags approved by policy under FR3-013 through FR3-016.

FR3-033 - Phase 3 shall write flat `XMP-dc:Subject` and Lightroom-style hierarchical `XMP-lr:HierarchicalSubject` per vocabulary entry export rules and Phase 2 export flags.

FR3-033a - For flat export, Phase 3 writes each entry's `flat_keyword`.

FR3-033b - For hierarchical export, Phase 3 writes the entry's `canonical_path` using `|` separators. This is controlled-vocabulary output and is the only Phase 3 source of multi-level hierarchical keywords.

FR3-033c - If `export_flat_keyword = false`, the entry shall not contribute to `dc:subject`. If `export_hierarchical_keyword = false`, the entry shall not contribute to `lr:HierarchicalSubject`.

FR3-033d - `write-unnormalized` session context may write only a flat keyword. It shall not invent a hierarchy.

FR3-034 - Existing sidecar metadata shall be preserved semantically as Phase 2 specifies. Validation shall use the owned parser, `XMPMetadataSnapshot`, and `XMPUnmanagedContentFingerprint`, excluding only the managed keyword fields intentionally changed.

FR3-034a - Malformed XMP sidecars shall fail as `E_XMP_PARSE_FAILED`. Unsupported but well-formed RDF/XMP shapes that cannot be safely merged shall fail as `E_XMP_UNSUPPORTED_RDF`. In both cases the source image file and existing sidecar shall be left unchanged.

FR3-034b - The batch shall continue after per-sidecar export failures. Failures shall be written to the progress log, session report, and export report.

FR3-034c - Phase 3 export reports shall record the owned XMP engine name/version and writer recipe version for every run.

FR3-035 - Phase 3 shall write a batch normalization report explaining, per tag and per asset: what was canonicalized from what, what was propagated and under which rule, what was skipped and why, what conflicts were detected, which images were weakly supported, what XMP target was planned, and what XMP validation result occurred.

FR3-036 - Report skip reasons shall include at least:

```text
below_confidence_threshold
unmatched_vocabulary
requires_review
consensus_below_threshold
conflict
contains_hierarchy_separator
specific_tag_policy
source_missing
source_identity_mismatch
session_stale
xmp_parse_failed
xmp_unsupported_rdf
xmp_validation_failed
disabled_flat_export
disabled_hierarchical_export
duplicate
```

FR3-037 - Folder runs shall produce:

```text
normalization-session-<ISO-8601-timestamp>.json
normalization-report-<ISO-8601-timestamp>.json
normalization-summary-<ISO-8601-timestamp>.md
normalization-progress-<ISO-8601-timestamp>.jsonl
```

These files shall be written under `--output-dir` when supplied, otherwise beside the scan root, JSON scan root, or session file as appropriate.

FR3-038 - The report schema identifier shall be `ai-sidecar-normalization-report/1.0`.

FR3-039 - Dry-run mode shall build the full normalization session and XMP change plans, but shall not create, modify, back up, restore, or validate XMP sidecars on disk.

## 10. Acceptance Criteria

AC3-001 - The program can process a folder of images and produce Phase 1 AI JSON sidecars, a Phase 3 session file, normalized Phase 2 XMP sidecars, and a normalization report in one invocation.

AC3-002 - Synonyms map to one canonical keyword path with canonical spelling preserved.

AC3-003 - Duplicate tags are not exported repeatedly.

AC3-004 - A broad tag observed directly or via descendants on at least the consensus fraction of eligible images, on an `auto_apply_allowed` entry, propagates across the batch. The same tag below threshold does not.

AC3-005 - A `requires_review` tag never propagates from model evidence alone, at any agreement level.

AC3-006 - A session subject propagates only when both `--session-subject` and `--allow-session-subject-propagation` are given, and is recorded as `user_session_context`.

AC3-007 - `apply-session` writes from an existing session file without model runs, rendering, subject isolation, or raw sidecar rewrites, and refuses assets whose identity hash changed unless `--allow-stale` is explicit.

AC3-008 - A vocabulary with a duplicated synonym, duplicated canonical path, orphan parent, pipe-bearing flat keyword, or hierarchy cycle is rejected at load with a precise error listing.

AC3-009 - Existing XMP sidecar metadata remains semantically preserved, verified by the owned parser, metadata snapshot comparison, and unmanaged-content fingerprint.

AC3-010 - The session report explains what was normalized, propagated, and skipped, with the governing rule named in each case.

AC3-011 - An unmatched session subject is rejected by default and exported only as an unnormalized flat user keyword under `write-unnormalized`.

AC3-012 - Hierarchy-aware counting demonstrably increases an ancestor's agreement frequency when descendants are observed.

AC3-013 - Normalized hierarchical output uses vocabulary `canonical_path` values and never exports raw model text containing `|`.

AC3-014 - A malformed existing XMP sidecar fails closed as `E_XMP_PARSE_FAILED`; an unsupported but well-formed RDF/XMP shape fails closed as `E_XMP_UNSUPPORTED_RDF`; neither failure modifies the existing sidecar or source image.

AC3-015 - Exported normalized sidecars can be read back by the owned XMP parser, and release smoke checks confirm Lightroom Classic and Capture One can import the written flat keywords.

AC3-016 - Phase 3 does not require, invoke, package, or report an ExifTool runtime dependency.

AC3-017 - `--session-only` produces a valid session and report while creating or modifying no `.xmp` files.

AC3-018 - Same-base-name RAW+JPEG groups produce exactly one normalized XMP write plan per target sidecar, respecting `--pair-scope`.

## 11. Future Groundwork

Phase 3 establishes the decision layer the GUI consumes directly:

- JSON vocabulary format, schema, integrity rules, and hash identity;
- synonym canonicalization with defined folding;
- controlled hierarchical paths safe for XMP export;
- per-image versus batch-level candidate distinction with hierarchy-aware statistics;
- provenance-aware normalization separating model evidence from user evidence;
- session files openable by the GUI and bound to asset identities;
- normalized XMP write plans consumed by `OwnedXMPSidecarEngine`;
- policy-driven auto-apply via vocabulary fields;
- conflict detection via siblings and mutual-exclusion groups;
- semantic XMP validation outcomes suitable for GUI display;
- batch-level reports and summaries.

Phase 4 shall turn this into an interactive review and correction workflow over the same engine.

## Reference Basis

This document incorporates the Reference Basis of Phase 1 v0.4 and Phase 2 v0.4. Items load-bearing for this phase specifically:

- Adobe XMP specifications: https://developer.adobe.com/xmp/docs/xmp-specifications/
- W3C RDF/XML syntax and RDF container vocabulary: https://www.w3.org/TR/rdf-syntax-grammar/
- Apple Foundation XML document processing: https://developer.apple.com/documentation/foundation/xmldocument
- IPTC Photo Metadata Standard 2025.1, Keywords implemented as `dc:subject`: https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata
- Adobe Lightroom Classic XMP sidecar behavior and metadata actions: https://helpx.adobe.com/lightroom-classic/help/create-xmp-acr-files.html and https://helpx.adobe.com/lightroom-classic/help/advanced-metadata-actions.html
- Capture One XMP sidecar behavior and Auto Sync Sidecar XMP settings: https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files
