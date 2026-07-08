# Post-M11 Feature Roadmap — New and Expanded Features

Version: 1.0
Date: 2026-07-07
Position in sequence: **after** `agent_docs/08-post-review-hardening-plan.md` R1–R4 and phase-4 milestones M9–M11 (see plan 08 §1.1 for the full order). Nothing here starts before M11's release evidence closes.
Audience: maintainer (feature selection) and junior engineer / Sonnet-level agent (execution outline).

## 0. How to use this document

This is the feature *outline*: each candidate carries requirements, an implementation approach, acceptance criteria, and a test plan at outline fidelity. Per project process, when a feature is **picked**, it gets the full treatment before code: a numbered requirements doc (the `01`–`04` pattern, with formal FR/AC IDs and a traceability matrix) and an implementation plan with milestones. The IDs below (`F1-R1`, `F1-AC1`, …) are outline-scoped; formal IDs are assigned in that requirements pass.

Ground rules for every feature, no exceptions:

- All invariants in `agent_docs/invariants.md` apply — especially: analyze never touches XMP (1), source images never modified (2), GPS never becomes keywords (3), all XMP writes through the owned guarded engine (4), additive schemas (8), tests deterministic and offline (12), Core/CLI/GUI split (13).
- **Local-first is the product.** No feature may upload images, derivatives, or metadata. Anything needing a model runs through the local Ollama runtime or Apple's on-device frameworks (Vision, NaturalLanguage).
- One feature at a time; each feature's milestones independently committable with `swift test` green.

## 1. Feature index

| ID | Feature | Tier | Size | Depends on | Origin |
|---|---|---|---|---|---|
| F1 | Vocabulary tooling suite | A | L (staged) | M11 | FR4-021–025 deferral, req 04 §12 |
| F2 | Multi-root folder import | A | M | M9 (Studio), M10 helpful | FR4-007 restoration, req 04 §12 |
| F3 | Provenance-dimension reprocessing | A | M | M10 (database mode) | FR4-012 full form, req 04 §12 |
| F4 | Distribution maturity: CLI install, auto-update, CI | A | M | v0.1.0-beta.1 shipped | packaging plan WI-3/§7, out-of-B0 list |
| F5 | Visual similarity (embedding) search | B | L | F2 helpful; M10 for persistence | req 04 §12; unlocks FR4-019 "visually similar" |
| F6 | OCR text pass | B | M | none | req 04 §12 |
| F7 | Map/GPS filtering (read-only) | B | M | none | req 04 §12 |
| F8 | Model comparison runs | B | M | none | req 04 §12 |
| F9 | User correction learning (local mining) | B | M | F1 (consumes its actions) | req 04 §12 |
| F10 | Caption/title candidates and export | B | M | F12 groundwork for the write side | **new proposal** (not in §12) |
| F11 | Embedded metadata writing (JPEG/TIFF/DNG) | C | L | long sidecar-safety track record | req 04 §12, guarded |
| F12 | Scoped XMP namespace expansion | C | M per field | per-field decision | req 04 §12, guarded |
| F13 | DAM profile exports (Photo Mechanic et al.) | C | M | real user demand | req 04 §12 |

Recommended default order: **F1 → F4 → F2 → F3**, then reassess Tier B by user feedback (F5 is the highest-leverage bet; F6/F7 are the cheapest). Tier C only with explicit maintainer sign-off per its guard notes.

---

## 2. Tier A — natural next steps

### F1 — Vocabulary tooling suite (staged: F1a inspector → F1b guided mapping → F1c editor + CLI)

**Motivation.** The vocabulary is the heart of Phase 3, but today it is a hand-edited JSON file: no browsing, no validation UI, no way to act on the Normalization Inspector's "unmatched" outcomes without leaving the app. This was FR4-021–025, deferred in requirements v0.7 as "probable future inclusion."

**Requirements (outline).**
- F1-R1 (F1a) — A read-only Vocabulary Inspector: browse the loaded vocabulary as a hierarchy, search by canonical path / flat keyword / synonym, and display per-entry policy facts (`direct_apply_policy`, `requires_review`, synonyms, source line). Runs `VocabularyValidator` on load and renders its findings.
- F1-R2 (F1a) — Toggling `requires_review` / auto-approval flags on entries, written back through a vocabulary writer that preserves file order and comments-equivalent structure, refreshing the content hash (sessions referencing the old hash correctly show stale per the existing SHA-256 indicator).
- F1-R3 (F1b) — Guided actions from the Normalization Inspector on unmatched/ambiguous keywords: "map to existing entry as synonym," "create new entry from this keyword," each previewing the vocabulary diff before write, with live collision detection against the exact-fold, separator-fold, and synonym indexes (must respect invariant 10 and the R4-4 ambiguity guards).
- F1-R4 (F1c) — Full editor: add/edit/delete entries, synonym definition with live collision detection, import/export vocabulary files with fresh content hashes.
- F1-R5 (F1c) — Matching CLI commands `aisidecar vocab validate`, `vocab add-synonym`, `vocab add-entry` sharing the same Core mutation code (invariant 13); additive subcommands only (invariant 14 keeps the single `aisidecar` binary).
- F1-R6 — Vocabulary writes are atomic (`AtomicFileWriter`), never modify the bundled default vocabulary in the app bundle (read-only, invariant 20's spirit), and always target a user-owned copy; first mutation of the bundled default triggers a "save your copy as…" flow.

**Approach.** Core gains `Normalization/VocabularyEditing.swift` (mutation model: parse → mutate entry set → re-validate → serialize deterministically) reusing `VocabularyLoader`/`Validator`/`Index`. GUI: `Features/Vocabulary/` (`VocabularyModel`, `VocabularyInspectorView`, editing sheets), embedded shell-agnostic like every other feature so both Wizard-adjacent (a toolbar entry from the Normalize step) and Studio (its own sidebar view) get it. CLI: one new `VocabCommand.swift` with subcommands. Collision detection = a dry-run insert against the three lookup maps returning the conflicting entries.

**Acceptance criteria (outline).**
- F1-AC1 — Open a 5.8 MB-scale vocabulary; browse/search stays responsive (no main-thread loads; index built off-main).
- F1-AC2 — Adding a synonym that collides with an existing flat keyword or synonym is blocked with both entries named; adding a non-colliding synonym round-trips through `VocabularyLoader` and changes normalization outcomes on the next run.
- F1-AC3 — The Inspector's "map keyword → synonym" action, applied to a real unmatched keyword, produces a vocabulary in which a re-run canonicalizes that keyword — verified end-to-end model-free via `fromJSON`.
- F1-AC4 — `vocab add-entry`/`add-synonym` on the CLI produce byte-identical output to the GUI path for the same mutation.
- F1-AC5 — The bundled default vocabulary file is never modified; mutation attempts route to the user-copy flow.

**Tests.** Core: mutation round-trip determinism (parse→mutate→serialize→parse equals mutate of parsed), collision matrix (flat/synonym/separator-fold × add-entry/add-synonym), content-hash refresh, bundled-vocabulary write refusal. GUI: model-level tests for search/filter and collision presentation. CLI: golden output tests for each subcommand. All offline (fixture vocabularies exist in `Tests/AISidecarCoreTests/Fixtures/`).

### F2 — Multi-root folder import

**Motivation.** FR4-007 was amended to single-root for the MVP; real libraries span drives ("2024 on the NAS, current shoot on the SD card"). Eliminated in v0.9, listed first in req 04 §12.

**Requirements (outline).**
- F2-R1 — The import step accepts multiple root folders in one session; the queue shows per-root grouping with per-root recursive toggles and per-root asset counts.
- F2-R2 — Analysis, review, normalization, and export operate over the union; every existing per-asset behavior (pair grouping, `--output-dir` mirroring, session documents) keys on (root, relative-path) so same-base-name files under **different roots never group** (this is the R4-1 lesson generalized — make it impossible by construction).
- F2-R3 — Session documents record the root list; `apply-session` and the GUI Apply flow re-resolve each root independently and report per-root missing/moved status.
- F2-R4 — Sidecar-only relaunch reconstruction (M8 audit) extends to the root list (UserDefaults reopen-last extends to a root set).
- F2-R5 — CLI parity is explicit: `analyze`/`normalize` accept repeated input paths **or** the feature stays GUI-only with the file-list path as the CLI equivalent — decide in the requirements pass; do not ship divergent grouping semantics between them.

**Approach.** Core: `ImageScanner.inventory`/scan already work per root — add a thin `MultiRootScanPlan` that concatenates per-root results tagging each with its root; extend `NormalizationInputResolver` group keys to (rootID, directory, basename). GUI: `FolderImportModel` holds `[ImportRoot]`; queue section headers per root. Watch the R2-3 rescan-generation pattern — one generation token across all roots.

**Acceptance criteria.** F2-AC1 — Two roots containing same-base-name files produce two independent XMP targets. F2-AC2 — A root on an unmounted volume degrades to a per-root error banner; the other roots' flow completes. F2-AC3 — Kill/relaunch restores the root set and re-derives the union queue. F2-AC4 — A session built from two roots re-applies after one root moved, with the moved root's assets reported missing, not silently dropped.

**Tests.** Core: group-key separation across roots, session round-trip with root list, per-root inventory failure isolation. GUI: model tests for multi-root queue derivation and reopen persistence. Fixture: extend `generate-synthetic-fixture.swift` with a `--roots N` mode.

### F3 — Provenance-dimension reprocessing

**Motivation.** FR4-012's full form: "re-run everything analyzed with prompt v3" or "re-normalize everything decided under vocabulary hash X" — the provenance is already recorded in every sidecar and session; nothing can query it.

**Requirements (outline).**
- F3-R1 — Filter the queue by recorded provenance dimensions: prompt version, render recipe version, model tag, vocabulary content hash, normalization session ID, writer recipe version, source-verification result.
- F3-R2 — A filtered selection feeds the existing run actions ("re-analyze these 214", "re-normalize these"), with `--existing overwrite` scoped to exactly the selection.
- F3-R3 — Sidecar-only mode supports this by scanning `.ai.json` provenance on demand (slow path, progress-reported); database mode (M10) answers from `model_runs`/`sidecar_snapshots` indexes (fast path). Ship after M10 so both paths exist; the sidecar-only path is the correctness reference.
- F3-R4 — CLI parity: `aisidecar analyze --where prompt-version=v2` style filter flags (additive), sharing the Core filter engine.

**Approach.** Core: `Pipeline/ProvenanceQuery.swift` — a predicate model (`dimension == / != value`) evaluated against a decoded sidecar's provenance block (partial-decode struct; R2-5's `xmp_export`-only decode pattern generalizes here) and against the M10 database when enabled. GUI: filter bar on the queue (Studio's natural home; minimal Wizard exposure). Scoped overwrite = pass the selection as an explicit file list into the existing pipelines (the file-list path already exists in `normalize`).

**Acceptance criteria.** F3-AC1 — A folder with mixed prompt versions filters correctly in both modes and both agree exactly. F3-AC2 — Scoped re-run overwrites only the selection (adjacent sidecars byte-identical after). F3-AC3 — 5,000-asset sidecar-only scan completes with progress and stays cancellable.

**Tests.** Core: predicate evaluation over fixture sidecars covering every dimension; mode-equivalence test (same fixture set, file-scan vs database answers); scoped-overwrite isolation test. Golden: filter flags' help output.

### F4 — Distribution maturity: CLI install action, auto-update, CI

**Motivation.** Beta ships as a hand-delivered DMG with an embedded CLI nobody can invoke. These are the three deferred packaging items (WI-3, Sparkle, packaging plan §7) that turn it into a maintainable product.

**Requirements (outline).**
- F4-R1 (WI-3) — GUI menu action "Install Command Line Tool": symlink `Contents/Helpers/aisidecar` into `/usr/local/bin` (create dir if missing); on permission failure show manual `ln -s`/PATH instructions — never escalate privileges. Detect and repair a stale symlink after the app moves. (Packaging plan WI-3 acceptance verbatim.)
- F4-R2 — Sparkle 2 auto-update: appcast hosted on GitHub releases, EdDSA-signed updates, update check on launch + manual "Check for Updates…", off by default until the user opts in on first run (local-first posture: no silent phone-home).
- F4-R3 — GitHub Actions CI: `swift test` on every PR (offline by design — invariant 12 means no Ollama in CI); release workflow on tags runs `Scripts/build-release.sh` with signing/notarization secrets; artifacts attached with checksums (packaging plan §7; the release checklist becomes the workflow).
- F4-R4 (WI-7) — extend `agent_docs/release-checklist.md` into the human-readable mirror of the release workflow. The checklist itself is first written during the beta-tag run (plan 08 §1.1 step 3), so this item revises an existing document rather than authoring one.

**Approach.** F4-R1: small AppKit-interop action in `Features/Settings/` + a Core `CLIInstaller` (testable path logic; the symlink syscall wrapped). F4-R2: SwiftPM dependency on Sparkle 2; `SUUpdater` wiring in the app; appcast generation appended to `build-release.sh`; note Sparkle is the project's first third-party GUI dependency — flag in the requirements pass. F4-R3: two workflow files; keep unit tests offline.

**Acceptance criteria.** F4-AC1 — WI-3's: fresh macOS user account → install action → `aisidecar --help` works in a new terminal; move the app → action detects and repairs the stale link. F4-AC2 — A staged 0.1.0-beta.2 appcast updates a running beta.1 install with signature verification. F4-AC3 — A PR with a failing test blocks; a tag produces a signed, notarized, stapled DMG artifact.

**Tests.** `CLIInstaller` path/permission logic unit tests (temp-dir fake `/usr/local/bin`); appcast generation golden test in the build script's bats-style check or a Swift test over the generator; CI proves itself.

---

## 3. Tier B — bigger bets, pick by demand

### F5 — Visual similarity (embedding) search

**Motivation.** Req 04 §12: unlocks a real "visually similar" scope for FR4-019 ("apply this edit to visually similar photos") and similarity browsing. Biggest workflow multiplier on large libraries.

**Requirements (outline).**
- F5-R1 — Compute a per-asset image embedding locally (baseline: Apple Vision `VNGenerateImageFeaturePrintRequest` on the existing whole-image derivative — no new model dependency, fully offline; an Ollama embedding model is a config-gated alternative evaluated in the requirements pass).
- F5-R2 — Embeddings are derivatives: stored in the derivative cache keyed by (source identity, embedding recipe version), regenerable, purge-covered, never in the sidecar (keeps `.ai.json` model-run-focused and small; additive schema note if this changes).
- F5-R3 — "Similar to this" query returns a ranked, thresholded asset list; review gains "apply verdict/edit to visually similar" with the similarity set shown and individually deselectable **before** apply — never silently (conservative-defaults NFR).
- F5-R4 — Similarity never auto-approves anything; it only scopes an explicit user action (same posture as `editEverywhere` after R1-7).
- F5-R5 — Sidecar-only mode computes on demand per session; database mode (M10) persists vectors in a `derivatives`-adjacent table for instant recall.

**Approach.** Core: `SubjectIsolation`'s Vision-request pattern is the template — `Rendering/ImageEmbeddingService.swift` (request wrapper, recipe version constant, distance function on `VNFeaturePrintObservation` or raw vector). Brute-force distance is fine to 10k assets (measure at M11 scale before adding any index structure). GUI: similarity drawer in Review + queue filter.

**Acceptance criteria.** F5-AC1 — On the 5,000-asset synthetic fixture (extended with visually-clustered images), "similar to X" returns X's cluster above threshold and completes < 2 s warm. F5-AC2 — Apply-to-similar changes exactly the confirmed set. F5-AC3 — `purge` removes embeddings; nothing breaks; recompute is transparent. F5-AC4 — Offline test suite stays green with a mock feature-print provider (invariant 12: Vision itself is on-device but tests use recorded vectors for determinism).

**Tests.** Distance-function unit tests over recorded vectors; cache-key/recipe-version tests mirroring `DerivativeCacheTests`; review-scoping tests mirroring the R1-7 pattern (never touches withheld decisions); a deterministic mock provider seam like `MockVisionModelRunner`.

### F6 — OCR text pass

**Motivation.** Req 04 §12. Signs, race bibs, aircraft tails, storefronts — text in images is high-precision keyword evidence current vision prompts under-report.

**Requirements (outline).**
- F6-R1 — Optional analyze-time pass (`--ocr on|off`, config `ocr`, default off) running Apple Vision `VNRecognizeTextRequest` on the whole-image derivative.
- F6-R2 — Results recorded in the raw sidecar as a new additive block (`ocr` — recognized strings, confidence, bounding boxes, recognition-level/recipe version), PW-011/012 additive.
- F6-R3 — OCR strings become **candidates with a distinct provenance kind** (`ocr_text`), flowing through the existing candidate → normalization → review path — subject to vocabulary matching, the GPS coordinate guard (R4-3's broadened regexes apply to OCR text too), and review like every other candidate. Never auto-exported raw.
- F6-R4 — Analyze remains XMP-silent (invariant 1) — OCR touches only `.ai.json`.

**Approach.** Core: `Rendering/TextRecognitionService.swift` (same service pattern as subject isolation, mockable provider protocol); `CandidateExtractor` gains the `ocr_text` kind; prompt/schema untouched (OCR is a parallel channel, not a prompt change). GUI: a toggle in Step 3 options + provenance chip styling in review (kind tooltip already exists from M4).

**Acceptance criteria.** F6-AC1 — Fixture image with known text yields `ocr` block + candidates with correct kind. F6-AC2 — An OCR string matching a vocabulary synonym canonicalizes; an unmatched one lands in the normal unmatched flow. F6-AC3 — A coordinate-like OCR string (GPS overlay burned into an image) is blocked from keyword export. F6-AC4 — `--ocr off` produces byte-identical sidecars to today.

**Tests.** Mock text provider with recorded results (offline); candidate-kind propagation through canonicalizer/consensus; GPS-guard cases; golden sidecar with the additive block.

### F7 — Map/GPS filtering (read-only)

**Motivation.** Req 04 §12: "map/GPS filtering without AI-inferred GPS writes." The EXIF GPS data is already read for `--gps-context`; users can't browse by it.

**Requirements (outline).**
- F7-R1 — Queue filtering by location: a MapKit map view showing asset pins (from EXIF GPS only — never model output), rectangle/radius selection filtering the queue; plus a "has GPS / no GPS" quick filter.
- F7-R2 — Strictly read-only: no GPS writing, no reverse-geocoded keywords, nothing crosses into candidates or XMP (invariant 3 extended: this feature adds **no new path** from coordinates toward keywords). Reverse geocoding, if ever proposed, is its own Tier C feature with its own requirements doc — CoreLocation's geocoder is a network service and collides with local-first.
- F7-R3 — Offline: MapKit tiles require network; the feature degrades to a coordinate-list filter without it, and the app never blocks on tile loads.

**Approach.** Core: expose the already-parsed EXIF coordinates in `ScanInventory`/asset records (they're read in the GPS-context path today — surface, don't re-read). GUI: `Features/Map/` view over the queue, selection → the same explicit-file-list scoping F3 uses.

**Acceptance criteria.** F7-AC1 — Fixture with known coordinates pins correctly and rectangle-select filters exactly. F7-AC2 — Grep-level assertion stands: no code path from this feature reaches `CandidateExtractor`, the XMP planner, or session documents. F7-AC3 — Airplane-mode launch: filter works via the list fallback.

**Tests.** Coordinate surfacing unit tests; selection-predicate tests; the AC2 guard as a targeted unit test on the queue-filter output type (it must carry no coordinate strings into run inputs beyond file paths).

### F8 — Model comparison runs

**Motivation.** Req 04 §12: "model comparison runs over recorded provenance." Users switching models (or Ollama tags churning, as the README's Gemma note shows) have no way to ask "is the new model better on my photos?"

**Requirements (outline).**
- F8-R1 — `aisidecar compare` (or a benchmark-harness extension — decide in the requirements pass; benchmark already owns multi-run orchestration): run N models over the same folder into separate `--output-dir` staging trees, then produce a comparison report: per-asset candidate agreement/overlap, per-model timing, schema-violation and failure rates, vocabulary-match rates when a vocabulary is supplied.
- F8-R2 — Comparison consumes recorded provenance — it can also run **report-only** over two existing sidecar trees from prior runs (no model calls), which is the deterministic testable core.
- F8-R3 — Report formats follow the reporting conventions: machine JSON + human markdown via `ArtifactNames`-registered names.
- F8-R4 — GUI exposure is read-only rendering of a comparison report (defer any GUI run-orchestration until demand).

**Approach.** Core: `Benchmarking/ModelComparison.swift` — pure function over two+ decoded sidecar sets (agreement = normalized-keyword set operations reusing `VocabularyTextFolder` folding); orchestration reuses `AnalyzePipeline` serially per model (invariant 15's serial-preflight spirit; never two models resident concurrently — memory).
**Acceptance criteria.** F8-AC1 — Report-only mode over fixture trees produces the golden report. F8-AC2 — Live two-model run (manual smoke) produces per-model sidecar trees that each independently pass existing validation, plus the report. F8-AC3 — A model that fails mid-run yields a partial-comparison report that says so, exit code per R3-1 policy.
**Tests.** Agreement-math unit tests (including case/Unicode folding edges); golden comparison report; orchestration with two mock runners returning divergent fixtures.

### F9 — User correction learning (local mining)

**Motivation.** Req 04 §12. Every review session records verdicts and edits; today that history teaches nothing. Mining it locally ("you've renamed 'bird of prey' → 'Raptor' 11 times") feeds F1b's guided mapping with evidence-backed suggestions. No ML training — frequency mining over session documents.

**Requirements (outline).**
- F9-R1 — A miner over a folder of session documents extracts recurring patterns: repeated identical edits (rename A→B ≥ k times), repeated rejections of a canonical path, repeated approvals of unmatched keywords.
- F9-R2 — Output is a **suggestion list** consumed by F1b's guided-mapping UI ("add 'bird of prey' as a synonym of Raptor — seen 11×; preview"); nothing is ever applied automatically (conservative defaults).
- F9-R3 — Runs on demand only; reads sessions the user points it at (or the GUI state dir's saved sessions); no background scanning.
- F9-R4 — Privacy note in the requirements pass: sessions may embed folder paths; suggestions must not leak paths into vocabulary files.

**Approach.** Core: `Normalization/SessionMiner.swift` — pure function `[NormalizationSessionDocument] → [VocabularySuggestion]`, threshold-configurable. GUI: a "Suggestions" pane inside the F1 Vocabulary Inspector. CLI: `aisidecar vocab suggest --from-sessions <dir>`.
**Acceptance criteria.** F9-AC1 — Fixture sessions with a planted 11× rename produce exactly that suggestion with count. F9-AC2 — Applying a suggestion routes through F1b's collision-checked path. F9-AC3 — Below-threshold patterns produce nothing.
**Tests.** Pure-function mining tests over fixture sessions (determinism: stable ordering by count then fold); integration test with F1b apply path.

### F10 — Caption/title candidates and export (**new proposal**, not in req 04 §12)

**Motivation.** The model sees the whole image; users hand-write captions anyway. A one-sentence caption candidate (XMP `dc:description`) and short title (`dc:title`) per asset is high-value and fits the existing candidate→review→export shape. Proposed here for maintainer consideration; it expands both the prompt contract and the XMP write surface, so it deliberately rides on F12's per-field scoping rules for the write side.

**Requirements (outline).**
- F10-R1 — New prompt/schema version requesting `caption` and `title` alongside keywords; recorded in the raw sidecar as candidates of kind `caption`/`title` (additive schema; prompt/schema versioning already exists).
- F10-R2 — Review UI shows caption/title as editable single-value fields per asset (not chips); accept/edit/reject verdicts; session document carries them (additive).
- F10-R3 — Export writes `dc:description`/`dc:title` **only** through the owned engine with F12's per-field rules: language-alternative (`rdf:Alt` `x-default`) handling added to the parser/writer as a *managed field* with full merge/fingerprint/validation coverage; never overwrite a non-empty existing value without an explicit per-asset confirmation recorded in the plan.
- F10-R4 — GPS/coordinate guard applies to caption text destined for export? **No** — captions are prose, not keywords; but the requirements pass must decide whether GPS-context-derived place names may appear in captions (recommendation: yes with provenance recorded, since invariant 3 governs *keywords*; note it explicitly either way).

**Approach.** Prompt registry + response schema new versions; `CandidateExtractor` new kinds; `XMPDocumentParser/Writer` learn `rdf:Alt` for exactly these two properties (today `rdf:Alt` is deliberately rejected — this is the first scoped expansion, done under F12 rules with fail-closed behavior for any Alt shape beyond single `x-default`); change-plan/report/fingerprint extended.
**Acceptance criteria.** F10-AC1 — Live run yields caption/title candidates; review edit round-trips through the session. F10-AC2 — Export writes valid `dc:description` read back by LR Classic and C1 (release-evidence pattern). F10-AC3 — Existing description in a foreign XMP is preserved unless explicitly confirmed; the plan shows old→new. F10-AC4 — Every non-`x-default`-single Alt shape still fails closed.
**Tests.** Schema-validation fixtures for the new prompt version; parser/writer Alt round-trip + fail-closed matrix; merge/fingerprint goldens; mock-runner end-to-end.

---

## 4. Tier C — guarded features (explicit maintainer sign-off required)

### F11 — Embedded metadata writing (JPEG/TIFF/DNG)

Req 04 §12 with its own guard: "only after the sidecar-only engine has proven safe." This **modifies source image files**, i.e. it relaxes invariant 2 — the single most dangerous change the project could make.
- **Preconditions (all):** at least two shipped releases of sidecar XMP writing with zero data-loss reports; F12-scoped field list; a written risk analysis approved by the maintainer; invariants doc amended first (per its own header: stop and ask).
- **Requirements sketch:** opt-in per run and per format; embedded writes only for formats with safe-rewrite paths (JPEG APP1/XMP packet, TIFF/DNG XMP tag); full-file backup before write (not just XMP backup); byte-level image-data integrity verification after write (pixel stream hash unchanged); RAW formats other than DNG permanently excluded.
- **Acceptance sketch:** round-trip on fixture files verified by decoding pre/post pixel data to identical hashes; LR/C1 read the embedded XMP; a torn write (kill mid-write) leaves the original restorable from backup.
- **Tests:** exhaustive fixture matrix per format; corruption-injection tests; the pixel-hash invariant as a permanent regression test.

### F12 — Scoped XMP namespace expansion

Req 04 §12: "broader XMP namespace editing only when each namespace and field is explicitly scoped." This is the *process* feature that F10 and F13 depend on:
- Each new managed field gets: requirements-doc entry naming namespace URI, property form(s) supported, merge policy, fingerprint coverage, fail-closed rules for unsupported shapes, and LR/C1 compatibility evidence.
- The parser/writer's narrow-engine posture stays: anything not explicitly scoped still fails closed (`xmpUnsupportedRDF`).
- First candidates: `dc:description`/`dc:title` (F10), `xmp:Rating` **write** support (read/preserve exists today), `photoshop:*` IPTC-mapped fields by demand.
- Tests per field: parse/merge/fingerprint/validate goldens + fail-closed matrix, added in the same commit as the field.

### F13 — DAM profile exports (Photo Mechanic and friends)

Req 04 §12. Ship only on real user demand — a profile is a mapping from the session's decisions to a target-specific output (Photo Mechanic structured keywords file, plain keyword TXT per image, CSV manifest).
- **Requirements sketch:** profiles are read-only *additional* outputs beside XMP (never replacing the owned XMP path); one profile = one Core `ExportProfile` implementation + fixtures from the target app's documented format; naming registered in `ArtifactNames`.
- **Acceptance sketch:** target app imports the artifact on a real machine (release-evidence pattern).
- **Tests:** golden output per profile from a fixture session.

---

## 5. Explicitly not planned (unchanged "shall nots")

From requirements 04 §3 and the packaging plan §8 — these stay out absent a new requirements decision: RAW editing / develop settings, cloud upload of any kind, face recognition, direct Lightroom/Capture One catalog manipulation, external metadata-tool orchestration (ExifTool et al.) at runtime, bundling Ollama or model weights, Mac App Store / sandboxing (revisit only post-MVP with its own plan), Windows/Linux.

## 6. Sequencing and process reminders

1. Nothing here starts before M11 closes (plan 08 §1.1 item 7 precedes item 8).
2. Default order: F1 → F4 → F2 → F3; then choose from Tier B with the maintainer (F5 for leverage, F6/F7 for cheap wins, F8/F9 opportunistically, F10 only together with F12's first scoping pass).
3. Every picked feature: requirements doc first (formal FR/AC IDs + traceability), then an implementation plan with milestones, then code — matching the phase 1–4 pattern. Update AGENTS.md's documentation index and this roadmap's table (mark picked/shipped) in the same pass.
4. Tier C requires explicit maintainer sign-off recorded in the feature's requirements doc; F11 additionally requires the invariants-doc amendment to precede any code.
