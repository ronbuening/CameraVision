# Phase 3 Requirements - CLI Normalized Batch Tagger

Version: 0.2
Date: 2026-06-10
Supersedes: 0.1
Binary: `aisidecar` (subcommands: `normalize`, `apply-session`)
Core library: `AISidecarCore`
Minimum deployment target: macOS 15
Default vision model: `gemma4:26b-a4b-it-qat`
Primary output artifacts: normalization session file, normalized XMP sidecar files, batch normalization report

This document inherits the Project-Wide Conventions of the Phase 1 requirements (Section 1 there) and the metadata-writing requirements of Phase 2. Neither is restated here.

## 0. Changes from v0.1

1. The tools are the `normalize` and `apply-session` subcommands of `aisidecar`, not a separate binary (PW-001).
2. The controlled vocabulary is JSON only, with a published JSON Schema and a content hash; YAML support is removed (FR3-002).
3. Vocabulary structural integrity rules are defined: unique canonical paths, single-target synonyms, strict tree, defined text folding (FR3-003a-e).
4. Consensus semantics are defined precisely, with cross-image agreement frequency as the primary signal and hierarchy-aware ancestor counting (FR3-011, FR3-013a-c).
5. The undefined `batch-folder-context` normalization mode is removed; the name is reserved (Section 4).
6. `--unknown-subject-policy` is added to the flag list with defined values and a default (Section 4, FR3-023).
7. "Conflicts strongly" is given a measurable definition via sibling/mutual-exclusion semantics (FR3-024, FR3-024a).
8. Session files bind per-asset decisions to source identity hashes so stale sessions are detectable (FR3-030a).
9. All confidence handling operates on the Phase 1 ordinal bands; numeric confidence statistics are removed.

## 1. Purpose

Phase 3 shall expand the command-line toolchain so whole-folder scans produce consistent, normalized metadata. The target is a realistic photographic workflow where a folder often contains multiple images of the same subject, event, habitat, or scene type, but the model describes the subject inconsistently across frames.

This phase adds a controlled vocabulary, synonym mapping, batch-level consensus, and normalization reports. It remains command-line only.

## 2. Builds Upon Phase 2

Phase 3 shall reuse, from `AISidecarCore`:

- scanner, identity, and batch processing;
- whole-image and subject-isolated model runs;
- raw JSON sidecar handling with banded candidates and conditional `species` observations;
- candidate extraction and keyword text rules (FR2-006a-c);
- the XMP merge writer, backup, restore, and round-trip validation;
- dry-run change planning;
- ExifTool batch invocation;
- same-base-name group resolution;
- export report generation.

Phase 3 shall not replace the Phase 2 writer. It adds a normalization layer between candidate extraction and XMP export.

## 3. Scope

Phase 3 shall normalize tags across images in a batch or folder.

It shall solve these first-order problems:

```text
Model says "egret" on one frame and "white heron" on another.
Model says "marsh" on one frame and "wetland" on another.
Model says "bird" on several frames and "Great Blue Heron" on a few stronger frames.
The user knows the folder subject and wants consistent tags applied across the set.
The model produces redundant flat tags that should map into one hierarchy.
```

It shall not implement a GUI review workflow, face recognition, identity tracking, or automated species certainty.

## 4. Command-Line Interface Requirements

Required command shapes:

```bash
# Full pipeline: analyze images, normalize, write session + XMP
aisidecar normalize <folder> --recursive --mode both

# Build a session from existing .ai.json sidecars without re-running the model
aisidecar normalize --from-json <json-folder>

# Build a session only; defer XMP export
aisidecar normalize <folder> --session-only

# Write XMP from a previously produced session file, no model runs
aisidecar apply-session <normalization-session-file>
```

Accepted flags: the project-wide glossary (PW-004), the Phase 2 export flags, plus:

```text
--vocabulary <path>
--normalization-mode <off|single-image|batch-conservative>
--session-subject <text>
--session-habitat <text>
--session-event <text>
--min-confidence <low|medium|high>
--consensus-threshold <float 0..1>
--allow-session-subject-propagation
--unknown-subject-policy <reject|write-unnormalized>
--session-only
--from-json <path>
--write-report <path>
```

Defaults:

```text
--normalization-mode        batch-conservative
--min-confidence            medium
--consensus-threshold       0.6
--unknown-subject-policy    reject
```

The v0.1 `batch-folder-context` mode is removed: it was named but never specified, and an unspecified mode is a bug generator. The name is reserved for a future revision that defines folder-level co-occurrence as weak evidence for mid-specificity tags.

`--require-review-specific-tags` is removed as a flag: review requirements are vocabulary policy (`requires_review`), not invocation policy, and the vocabulary defaults are conservative (FR3-003).

## 5. Controlled Vocabulary Requirements

FR3-001 - The program shall support a local controlled vocabulary file.

FR3-002 - The vocabulary format shall be JSON, validated against a published JSON Schema shipped with the project. YAML shall not be supported: everything else in the project is JSON, JSON Schema validation is native to the toolchain, and a second parser buys nothing. SQLite arrives in Phase 4 as the GUI's working store, importing this same format.

FR3-002a - The vocabulary file shall carry its own `schema_version` (`ai-sidecar-vocabulary/1.0`) governed by PW-011/012, and loaders shall compute and report a SHA-256 content hash, which is the vocabulary identity recorded in sessions (FR3-028).

FR3-003 - Each vocabulary entry shall support:

```text
canonical_path                e.g. "Wildlife|Birds|Herons and Egrets|Great Egret"
flat_keyword                  the exported flat form, e.g. "Great Egret"
namespace                     one of the FR3-004 namespaces
parent_path
synonyms                      array of strings
requires_review               default: true for Species/Taxonomy, People,
                              Location Type entries naming places; false otherwise
auto_apply_allowed            default: false for entries with requires_review
mutually_exclusive_group      optional string; entries sharing a group value
                              cannot both be true of one image (FR3-024a)
export_flat_keyword           default: true
export_hierarchical_keyword   default: true
notes
```

FR3-003a - Canonical paths shall be unique across the vocabulary. Loading a file violating this shall fail with `E_VOCABULARY_INVALID`.

FR3-003b - A synonym shall map to exactly one canonical path. A synonym appearing under two entries, or a string that is both a canonical term of one entry and a synonym of another, shall fail loading with `E_VOCABULARY_INVALID` and a listing of the collisions. Ambiguous vocabularies are rejected at load, not resolved at runtime.

FR3-003c - The hierarchy implied by `parent_path` shall be a strict tree: no cycles, no orphans (every non-root `parent_path` must exist). Violations fail loading.

FR3-003d - Text folding for synonym matching: Unicode NFC, case folding, whitespace collapsing. Diacritics shall not be folded — "Háj" and "Haj" are different words — and stemming shall not be performed.

FR3-003e - Matching preserves and outputs the canonical spelling and casing of the vocabulary entry (subsumes v0.1 FR3-005/006).

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

FR3-007 - The program shall support a user-supplied seed subject through `--session-subject`.

FR3-008 - User-supplied session context shall be treated as user evidence, not model evidence, throughout aggregation, provenance, and reporting.

## 6. Batch Normalization Requirements

FR3-009 - The program shall create a batch normalization session for each folder or explicit file list.

FR3-010 - The session shall aggregate model candidates from all images before writing final XMP sidecars.

FR3-011 - For each canonicalized candidate, the session shall compute: supporting image count, eligible image count, agreement frequency (supporting/eligible), the distribution of confidence bands, and the contributing input roles. Cross-image agreement frequency is the primary consensus signal; confidence bands are a secondary filter and tiebreaker. Self-reported model confidence is not well calibrated and shall never outrank agreement frequency in any decision rule.

FR3-012 - The session shall distinguish per-image tags from batch-level tags.

FR3-013 - Broad tags with high agreement, such as `Bird`, `Wildlife`, `Outdoor`, `Wetland`, or `Portrait`, may be propagated conservatively across the batch.

FR3-013a - Propagation rule, precisely: a candidate is batch-propagatable when, after `--min-confidence` filtering of per-image observations, `agreement_frequency >= consensus_threshold`, AND the vocabulary entry has `auto_apply_allowed = true`, AND no conflicting candidate (FR3-024a) itself meets the consensus threshold.

FR3-013b - Counting is hierarchy-aware: an observation of a descendant supports every ancestor on its canonical path. A frame tagged `Great Blue Heron` counts as support for `Herons and Egrets`, `Birds`, and `Wildlife`. Without ancestor implication, broad-tag propagation under-counts in exactly the folders where the model performed best.

FR3-013c - `--min-confidence` filters observations before frequency counting, not after.

FR3-014 - Specific tags — entries with `requires_review = true` — shall not be propagated automatically regardless of agreement, unless a user-supplied session subject plus the explicit allow flag is present (FR3-015).

FR3-015 - When `--session-subject` is supplied, the program may apply that subject to all images in the session only if `--allow-session-subject-propagation` is also set.

FR3-016 - A subject propagated from session context shall record `source = user_session_context`, never `source = model`.

FR3-017 - The normalizer shall collapse duplicate and synonymous candidates into a single canonical path.

FR3-018 - The normalizer shall remove redundant flat keywords that only repeat canonical hierarchy nodes, according to the entry's export rules.

FR3-019 - The normalizer shall avoid destructive simplification. Mapping upward to a defensible ancestor is allowed (`white heron` -> `Herons and Egrets`); mapping sideways or downward to a more specific node (`white heron` -> `Great Egret`) is forbidden unless a vocabulary rule or session context explicitly supports it.

FR3-020 - The normalizer shall maintain separate provenance records for whole-image and subject-isolated observations.

## 7. Same-Subject Folder Requirements

FR3-021 - The same-subject assumption shall be activated only by explicit user flags, never hidden inference.

FR3-022 - `--session-subject` accepts plain text and shall be matched against the vocabulary using FR3-003d folding.

FR3-023 - If `--session-subject` cannot be matched to a vocabulary entry, `--unknown-subject-policy` governs: `reject` (default) fails the session before any model run or write, instructing the user to add the term to the vocabulary; `write-unnormalized` records and exports it as a flat user keyword with `source = user_session_context` and no hierarchy. The default is `reject` because a session subject important enough to propagate across a folder is important enough to canonicalize first.

FR3-024 - Folder-level subject propagation shall warn when individual model observations conflict with the supplied subject (definition in FR3-024a).

FR3-024a - Conflict definition: image observations conflict with the session subject when they support, at or above `--min-confidence`, a vocabulary entry that is (a) a sibling of the session subject (same `parent_path`, different leaf — session subject `Great Egret`, image strongly tagged `Snowy Egret`), or (b) a member of the same `mutually_exclusive_group`. Mere absence of support is not conflict; it is weak support, reported separately (FR3-025).

FR3-025 - The session report shall list images that did not support the session subject at or above the minimum band, and separately, images that conflicted under FR3-024a. Conflicted images shall not receive the propagated subject; weakly supporting images shall, with the weak support noted in provenance.

FR3-026 - Phase 3 makes no claim of individual animal or person identity tracking. Same-subject behavior is batch-context normalization, not biometric or individual identity recognition.

## 8. Normalization Session File Requirements

FR3-027 - The program shall write a normalization session file before any XMP export.

Minimum structure:

```json
{
  "schema_version": "ai-sidecar-normalization/1.0",
  "session": {},
  "vocabulary": { "path": "string", "sha256": "string", "schema_version": "string" },
  "source_ai_sidecars": [],
  "batch_candidates": [],
  "per_asset_decisions": [],
  "warnings": [],
  "errors": []
}
```

FR3-028 - The session file shall record the vocabulary SHA-256 content hash; the human-readable version string is a label, the hash is the identity.

FR3-029 - The session file shall record normalization mode, thresholds, session-subject inputs, pair scopes, and export flags — the complete resolved configuration per PW-008.

FR3-030 - The session file shall be usable as input to `apply-session` without re-running the vision model.

FR3-030a - Each `per_asset_decisions` entry shall bind to the asset's source identity hash (FR1-006a), not only its path. `apply-session` shall verify identities before writing; a mismatch fails that asset with `E_SESSION_STALE` (image changed between analysis and write) and continues the batch. An `--allow-stale` override may force the write, recorded in the report.

## 9. XMP Export Requirements

FR3-031 - Phase 3 shall use the Phase 2 XMP merge writer, validation, backup, and group-resolution behavior unchanged.

FR3-032 - Phase 3 shall write only normalized tags approved by policy (FR3-013a-c, FR3-014/015).

FR3-033 - Phase 3 shall write flat `XMP-dc:Subject` and Lightroom-style hierarchical `XMP-lr:HierarchicalSubject` per entry export rules and the Phase 2 flags.

FR3-034 - Existing sidecar metadata shall be preserved exactly as Phase 2 specifies, including the round-trip diff (FR2-028).

FR3-035 - Phase 3 shall write a batch normalization report explaining, per tag: what was canonicalized from what, what was propagated and under which rule, what was skipped and why (band, frequency, `requires_review`, conflict), and which images were flagged as weak or conflicting.

## 10. Acceptance Criteria

AC3-001 - The program can process a folder of images and produce Phase 1 AI JSON sidecars, a Phase 3 session file, Phase 2 XMP sidecars, and a normalization report in one invocation.

AC3-002 - Synonyms map to one canonical keyword path with canonical spelling preserved.

AC3-003 - Duplicate tags are not exported repeatedly.

AC3-004 - A broad tag observed (directly or via descendants) on at least the consensus fraction of images, on an `auto_apply_allowed` entry, propagates across the batch; the same tag below threshold does not.

AC3-005 - A `requires_review` tag never propagates from model evidence alone, at any agreement level.

AC3-006 - A session subject propagates only when both `--session-subject` and `--allow-session-subject-propagation` are given, and is recorded as `user_session_context`.

AC3-007 - `apply-session` writes from an existing session file without model runs, and refuses assets whose identity hash changed.

AC3-008 - A vocabulary with a duplicated synonym or a hierarchy cycle is rejected at load with a precise error listing.

AC3-009 - Existing XMP sidecar metadata remains preserved, verified by the Phase 2 round-trip diff.

AC3-010 - The session report explains what was normalized, propagated, and skipped, with the governing rule named in each case.

AC3-011 - An unmatched session subject is rejected by default and exported as an unnormalized user keyword under `write-unnormalized`.

AC3-012 - Hierarchy-aware counting demonstrably increases an ancestor's agreement frequency when descendants are observed.

## 11. Future Groundwork

Phase 3 establishes the decision layer the GUI phase consumes directly:

- the JSON vocabulary format, schema, integrity rules, and hash identity;
- synonym canonicalization with defined folding;
- per-image versus batch-level candidate distinction with hierarchy-aware statistics;
- provenance-aware normalization separating user evidence from model evidence;
- session files openable by the GUI and bound to asset identities;
- policy-driven auto-apply via vocabulary fields;
- conflict detection via siblings and mutual-exclusion groups;
- batch-level reports.

Phase 4 shall turn this into an interactive review and correction workflow over the same engine.

## Reference Basis

This document shares the Reference Basis of the Phase 1 requirements (v0.2), incorporated by reference. Items load-bearing for this phase specifically:

- IPTC Photo Metadata: Keywords implemented in XMP as `dc:subject`: https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata
- Adobe Lightroom Classic hierarchical keyword conventions and XMP sidecars: https://helpx.adobe.com/lightroom-classic/help/create-xmp-acr-files.html
- Capture One XMP sidecar reading: https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files
- ExifTool: https://exiftool.org/
