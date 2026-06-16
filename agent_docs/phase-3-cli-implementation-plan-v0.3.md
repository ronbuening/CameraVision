# Implementation Plan - Phase 3 CLI Normalized Batch Tagger

Version: 0.3
Date: 2026-06-15
Supersedes: 0.2
Implements: Phase 3 Requirements v0.7 (`03-cli-normalized-batch-tagger-requirements-v0.7.md`)
Builds on: Phase 1 Requirements v0.4 (`01-cli-raw-json-sidecar-requirements.md`), Phase 2 Requirements v0.5 (`02-cli-xmp-sidecar-requirements-updated.md`), and Phase 2 Implementation Plan v0.4 (`phase-2-cli-implementation-plan.md`)
Binary: `aisidecar` (adds subcommands: `normalize`, `apply-session`)
Core library: `AISidecarCore`
Minimum deployment target: macOS 15, Swift 6 strict concurrency
Default model: `gemma4:26b-a4b-it-qat` for analyze-and-normalize mode
Metadata runtime: existing project-owned `OwnedXMPSidecarEngine`

Traceability in this plan points at Phase 3 v0.7 requirement IDs (`FR3-xxx`, `FR3-AFF-xxx`, `AC3-xxx`, `AC3-AFF-xxx`), inherited Phase 2 IDs (`FR2-xxx`, `AC2-xxx`), and inherited project-wide IDs (`PW-xxx`, `FR1-xxx`).

## 0. Changes from v0.2

This revision aligns the plan with Phase 3 Requirements v0.7. It keeps the same milestone structure but makes implementation policy more explicit and testable.

1. Adds the ordered normalization decision pipeline as the controlling implementation sequence.
2. Adds vocabulary `direct_apply_policy` modules and tests, separating direct writes from propagation.
3. Adds full session-context handling for subject, habitat, and event values.
4. Adds affinity-input source extraction, privacy/redaction, deterministic rounding/sorting, edge-storage invariants, local conflict mass, and global-backstop minimum-count implementation tasks.
5. Adds dry-run/session-only/apply-session artifact truth-table tests.
6. Adds starter-vocabulary appendix implementation tasks and fixture coverage.
7. Adds scalable candidate-neighbor graph construction for larger batches.
8. Adds a traceability matrix mapping requirement families to modules, tests, and milestones.

## 0.1 Changes from v0.1

This revision adds the metadata-affinity normalization design to the Phase 3 implementation plan.

1. Milestone 4 now builds an `AssetAffinityGraph` and `LocalWeightedConsensus` engine before propagation.
2. The repository layout adds dedicated affinity input, profile, scorer, graph, cluster, and local-consensus modules.
3. Vocabulary implementation now includes `propagation_scope` and `specificity` fields.
4. Session and report work now includes affinity inputs, component scores, edge bands, local clusters, local weighted agreement, support mass, and proximity-specific block reasons.
5. Automated tests now include affinity scorer, graph, local consensus, profile, and propagation/blocking cases.
6. Risks, smoke checks, and definition of done now reflect proximity-weighted local consensus rather than flat folder consensus.

## 0.2 Current Implementation Status

Phase 2 Milestones 0-10 and the pre-Phase-3 GPS context milestone are implemented. The repository now has the reusable `write-xmp` CLI surface, export configuration resolution, source verification, raw sidecar reader, candidate extraction, GPS/coordinate-only evidence guards, XMP naming, same-base-name RAW/JPEG grouping, pair-scope handling, dry-run XMP change planning, `MetadataWriteEngine`, `MockMetadataWriteEngine`, `OwnedXMPSidecarEngine`, owned XMP parser/writer/reader/merger/snapshot/fingerprint modules, backup/restore, semantic merge validation, source hash rechecks, progress logs, JSON reports, Markdown summaries, interruption handling, from-json export, analyze-and-write export, offline tests, and Lightroom Classic/Capture One compatibility smoke evidence.

The Phase 2 writer path is the implementation baseline for Phase 3. Phase 3 must not add another XMP writer, another metadata executable dependency, or another sidecar merge stack. Its normalized output must become a write plan consumed by the same `MetadataWriteEngine` and `OwnedXMPSidecarEngine` used by `aisidecar write-xmp`.

Phase 3 itself is not implemented. The first implementation unit is CLI scaffolding for `aisidecar normalize` and `aisidecar apply-session`, configuration validation, schema identifiers, and core vocabulary/session model types. The v0.7 requirements add the ordered decision pipeline, direct-apply policy, full session-context handling, metadata-affinity graph construction, local weighted consensus, privacy/redaction, deterministic scoring, local conflict mass, global-backstop minimums, artifact truth-table behavior, starter vocabulary coverage, scalable graph construction, and traceability matrix requirements as part of the first production normalization path.

The Phase 1 release signoff is still separate. Phase 3 implementation may begin from the Phase 2 baseline, but Phase 3 release should either archive Phase 1 Milestone 9 calibration/quality evidence or explicitly defer it with the missing checks, reason, and residual risk.

Latest inherited verification recorded in the Phase 2 plan:

```text
swift test                                      223 tests, 1 skipped, 0 failures
swift run aisidecar write-xmp --help            passed
```

Before Phase 3 Milestone 0 is marked complete, record a new baseline that includes the new command help paths:

```bash
swift test
swift run aisidecar --help
swift run aisidecar normalize --help
swift run aisidecar apply-session --help
swift run aisidecar write-xmp --help
swift run aisidecar benchmark --self-test
swift run aisidecar purge --help
```

## 1. Implementation Position

Phase 3 is a normalization and decision phase, not a new analysis engine and not a metadata-writing phase. It consumes Phase 1/2 candidate records, applies controlled-vocabulary policy, builds a metadata-affinity graph, computes proximity-weighted local consensus with a limited global backstop, records a durable normalization session, and then delegates actual XMP sidecar writing to Phase 2.

The safest implementation order is the FR3-ORD-001 decision sequence, implemented fixture-first:

1. add command/config/schema scaffolding and artifact location resolution without writing XMP;
2. implement vocabulary loading, the starter vocabulary, and direct-apply default derivation;
3. implement session/input resolution from existing `.ai.json` files, image folders, and file lists;
4. implement candidate observation extraction, confidence filtering, and per-image canonicalization without batch propagation;
5. add affinity input extraction, graph scoring, deterministic pruning, local weighted consensus, local conflict mass, global backstop minimums, and user session context;
6. run final deterministic conflict/tie-breaking and adapt normalized decisions into the existing Phase 2 export planner;
7. implement reports, summaries, progress logs, session-only, and dry-run truth-table behavior;
8. implement `apply-session` without model, rendering, re-normalization, affinity recomputation, or vocabulary decision changes;
9. wire analyze-and-normalize mode last.

This order keeps the first half of the phase offline, deterministic, and fixture-driven. Live model execution should not be required until the analyze-and-normalize integration milestone.

`normalize --from-json` should be the primary early path. It uses recorded raw sidecars and synthetic fixtures, allowing vocabulary, consensus, session, report, and XMP-plan behavior to be tested without Ollama, Apple Vision, RAW decoding, derivative rendering, or model-response repair.

`apply-session` must be deliberately narrow. It consumes a frozen normalization session, verifies source identity, recomputes current target paths, reads the current XMP sidecar at write time, merges through the owned engine, and reports stale-session overrides. It must not re-run the model, re-extract candidates, reload the vocabulary to change decisions, or accept normalization-decision flags.

## 2. Technical Stack

```text
Language:
  Swift 6, strict concurrency, Sendable value types for session/report/planning data

Project system:
  Swift Package Manager
  Existing targets: AISidecarCore, AISidecarCLI, AISidecarCoreTests

CLI parsing:
  Swift ArgumentParser; NormalizeCommand and ApplySessionCommand compose only valid flags

Input sources:
  Existing ImageScanner and SourceImage for image folders/files;
  new file-list resolver for newline-delimited source paths;
  existing RawJSONSidecarReader and RawJSONSidecarInputResolver for --from-json

Vocabulary:
  JSON only; Codable loader plus explicit integrity validation;
  schema id ai-sidecar-vocabulary/1.0;
  SHA-256 vocabulary identity through CryptoKit;
  Unicode NFC, case folding, and whitespace folding for synonym lookup

Normalization:
  CandidateExtractor output from Phase 2 as the source observation layer;
  vocabulary match index; direct apply policy; canonical-path graph; hierarchy-aware count propagation;
  metadata-affinity graph over same-base-name asset nodes;
  deterministic time/GPS/filename/list-adjacency decay scoring;
  camera/lens gear score as reinforcement only;
  local weighted agreement, support mass, eligible mass, supporting-neighbor gates, and local conflict mass;
  global backstop minimum counts; deterministic rounding, sorting, pruning, and tie-breaking;
  ordinal confidence bands only as filters/tie-breakers; no numeric model confidence introduced

Session/reporting:
  Codable JSON session and report documents;
  schema ids ai-sidecar-normalization/1.0 and ai-sidecar-normalization-report/1.0;
  artifact truth-table behavior; affinity edges, component scores, score bands;
  local consensus records, conflict mass records, privacy/redaction status, and XMP write plans;
  JSONL progress log and Markdown summary using the Phase 2 reporting pattern

XMP metadata engine:
  Existing MetadataWriteEngine and OwnedXMPSidecarEngine only;
  XMPDocumentParser, XMPDocumentWriter, XMPKeywordReader, XMPKeywordMerger,
  XMPMetadataSnapshot, and XMPUnmanagedContentFingerprint inherited unchanged

File safety:
  Existing AtomicFileWriter, XMPBackupManager, XMPMergeValidator, source hash checks,
  restore-on-validation-failure behavior, and per-target progress flushing

Testing:
  XCTest; offline vocabulary/session/consensus fixtures;
  MockMetadataWriteEngine for policy/pipeline tests;
  owned-engine fixture reuse for XMP preservation;
  no required live model, ExifTool, application automation, or network in CI
```

## 3. Repository Layout

Planned additions are shown only where Phase 3 creates or changes files.

```text
CameraVision/
  Sources/
    AISidecarCore/
      Configuration/
        NormalizationConfiguration.swift          // M0 config, defaults, validation
        NormalizationInvocation.swift             // M0 normalized command shape
      Normalization/
        VocabularyDocument.swift                  // M1 ai-sidecar-vocabulary/1.0 models
        VocabularyEntry.swift                     // M1 entry model, propagation_scope, specificity, defaults
        DirectApplyPolicy.swift                     // M1 allow/withhold/flat_only/user_only direct decision policy
        VocabularyLoader.swift                    // M1 JSON load, schema id, hash
        VocabularyValidator.swift                 // M1 uniqueness/tree/collision checks
        VocabularyIndex.swift                     // M1 synonym/canonical lookup index
        VocabularyTextFolder.swift                // M1 NFC/case/whitespace folding
        DefaultVocabulary.swift                   // M1 bundled vocabulary access
        StarterVocabularyFixtures.swift            // M1 Appendix A fixtures and required starter entries
        NormalizationSchemaIdentifiers.swift      // M0/M2 schema constants
        NormalizationDecisionOrder.swift           // M0/M3 FR3-ORD-001 stage ordering and tie-break metadata
        NormalizationArtifactPlanner.swift          // M0/M6 artifact truth-table planner
        NormalizationInputResolver.swift          // M2 folder/file-list/from-json inputs
        NormalizationSessionDocument.swift        // M2 ai-sidecar-normalization/1.0
        NormalizationSourceAsset.swift            // M2 identity-bound asset records
        AssetAffinityInputs.swift                 // M2/M4 capture-time/GPS/gear/filename inputs
        AssetAffinityInputExtractor.swift          // M4 workflow-specific affinity input source extraction
        AssetAffinityPrivacy.swift                  // M4 redaction, camera serial hashing, exact-input persistence policy
        AssetAffinityProfile.swift                // M0/M4 named weights, cutoffs, thresholds
        CaptureTimeAffinityScorer.swift           // M4 time half-life scoring
        GPSAffinityScorer.swift                   // M4 haversine/distance scoring
        FilenameSequenceAffinityScorer.swift      // M4 filename and file-list adjacency scoring
        CameraLensAffinityScorer.swift            // M4 gear boost scoring
        AssetAffinityGraph.swift                  // M4 nodes, edges, bands, storage thresholds
        CandidateNeighborGenerator.swift           // M4 scalable deterministic neighbor candidate windows
        AffinityScoreFormatter.swift                // M4 six-decimal rounding, score bands, stable sorting
        LocalWeightedConsensus.swift              // M4 support mass and local agreement records
        LocalConflictMass.swift                    // M4 neighborhood conflict mass and block rules
        GlobalBackstopConsensus.swift               // M4 global threshold plus minimum-count backstop
        NormalizationClusterBuilder.swift         // M4 explanatory local clusters for reports
        CandidateObservation.swift                // M3 extracted observation layer
        CandidateCanonicalizer.swift              // M3 vocabulary matching and policy
        NormalizationDecision.swift               // M3 per-asset decisions and skips
        BatchConsensusEngine.swift                // M4 global backstop and hierarchy-aware counts
        SessionContextResolver.swift              // M4 user session subject/habitat/event
        NormalizationConflictDetector.swift       // M4 siblings and mutually-exclusive groups
        NormalizedXMPChangePlanner.swift          // M5 adapter to Phase 2 export plans
        SessionStalenessChecker.swift             // M7 apply-session identity checks
      Pipeline/
        NormalizePipeline.swift                   // M2-M6 from-json/file/folder/session paths
        ApplySessionPipeline.swift                // M7 session -> current XMP writes
        AnalyzeAndNormalizePipeline.swift         // M8 AnalyzePipeline -> NormalizePipeline
      Reporting/
        NormalizationProgressLog.swift            // M6 JSONL records
        NormalizationReport.swift                 // M6 ai-sidecar-normalization-report/1.0
        NormalizationSummary.swift                // M6 Markdown summary and app instructions
      Resources/
        Schemas/
          ai-sidecar-vocabulary-1.0.schema.json   // M1 published schema fixture
          ai-sidecar-normalization-1.0.schema.json// M2 published schema fixture
          ai-sidecar-normalization-report-1.0.schema.json // M6 schema fixture
        Vocabularies/
          default-vocabulary.json                 // M1 conservative starter vocabulary
    AISidecarCLI/
      NormalizeCommand.swift                      // M0 argument handling only
      ApplySessionCommand.swift                   // M0/M7 argument handling only
      AISidecarCommand.swift                      // M0 registers subcommands
  Tests/
    AISidecarCoreTests/
      NormalizationInvocationTests.swift          // M0 CLI/config shape
      VocabularyLoaderTests.swift                 // M1 loading/default/hash/schema id
      VocabularyValidatorTests.swift              // M1 collision/tree/default policy tests
      DirectApplyPolicyTests.swift                 // M1 direct write policy independent from propagation
      StarterVocabularyTests.swift                  // M1 Appendix A minimum starter entries and fixtures
      FileListInputResolverTests.swift            // M2 path resolution and duplicates
      NormalizationSessionTests.swift             // M2 session schema and identity binding
      NormalizationDecisionOrderTests.swift        // M2/M3 FR3-ORD-001 stage order and tie-breaks
      NormalizationArtifactPlannerTests.swift       // M6 dry-run/session-only/apply-session artifact truth table
      AssetAffinityScorerTests.swift             // M4 component scoring, profile thresholds, gear boost
      AssetAffinityInputExtractorTests.swift       // M4 workflow-specific metadata sources and apply-session no-recompute
      AssetAffinityPrivacyTests.swift              // M4 redaction/default exact-input suppression
      AssetAffinityGraphTests.swift              // M4 node collapse, edge storage, neighbor caps
      CandidateNeighborGeneratorTests.swift       // M4 large-batch deterministic candidate windows
      AffinityScoreFormatterTests.swift            // M4 rounding, bands, stable sort order
      LocalWeightedConsensusTests.swift          // M4 support mass and local agreement
      LocalConflictMassTests.swift                // M4 direct and neighborhood conflict mass
      GlobalBackstopConsensusTests.swift           // M4 minimum eligible/supporting assets
      CandidateCanonicalizerTests.swift           // M3 synonym/unmatched/off/single-image
      BatchConsensusEngineTests.swift             // M4 thresholds, hierarchy, review blocks, global backstop
      SessionContextResolverTests.swift           // M4 user evidence and conflicts
      NormalizedXMPChangePlanTests.swift          // M5 normalized plans and pair groups
      NormalizationReportTests.swift              // M6 report/summary/progress artifacts
      ApplySessionPipelineTests.swift             // M7 stale/moved/current-XMP merge tests
      AnalyzeAndNormalizePipelineTests.swift      // M8 mocked analyze integration
      NoXMPRegressionTests.swift                  // M0/M9 inherited command guard extension
      Fixtures/
        normalization/
        vocabularies/
        ai-json/
        xmp/
        source-images/
```

Do not put XML/RDF implementation details into any `Normalization/` module. Normalization modules produce terms, decisions, provenance, and plans. XML parsing and writing remain behind `MetadataWriteEngine`.

## 3.1 v0.3 Implementation Deltas Across Existing Milestones

These deltas are normative for the milestone sections that follow. They avoid spreading the same policy language across every milestone while keeping the original Phase 3 implementation order intact.

1. Milestone 0 shall include artifact-location planning and strict validation for `--unknown-session-context-policy`, `--allow-specific-tags` fallback scope, affinity profile overrides, and `apply-session` rejection of normalization-decision flags.
2. Milestone 1 shall implement `direct_apply_policy`, starter-vocabulary Appendix A entries, and fixture coverage for direct-apply defaults independent from propagation defaults.
3. Milestone 2 shall persist `session_context`, privacy/redaction policy, deterministic policy metadata, artifact output records, local conflict mass records, and source identity bindings in the normalization session schema.
4. Milestone 3 shall treat confidence bands as ordinal filters and tie-breakers only; surviving observations contribute one support unit. Direct model observations shall pass through `DirectApplyPolicy` before any propagation is considered.
5. Milestone 4 shall add `AssetAffinityInputExtractor`, `CandidateNeighborGenerator`, `AffinityScoreFormatter`, `LocalConflictMass`, `GlobalBackstopConsensus`, and `AssetAffinityPrivacy`. Large batches shall use deterministic candidate-neighbor windows before pruning; decision-contributing edges must remain auditable.
6. Milestone 4 shall complete session context for subject, habitat, and event values, including unknown-session-context policy, conflict behavior, user provenance, and the rule that GPS cannot create named-place keywords.
7. Milestone 5 shall adapt only approved direct, local, global, and user-context decisions into Phase 2 XMP write plans; it shall not let `--allow-specific-tags` override controlled vocabulary policy.
8. Milestone 6 shall implement the dry-run/session-only/apply-session artifact truth table and privacy-redacted report fields.
9. Milestone 7 shall prove `apply-session` reads stored decisions, verifies source identity, recomputes target paths only, and does not recompute vocabulary, candidate extraction, affinity, local consensus, or propagation.
10. Milestone 10 shall include fixture tests for direct-apply policy, session habitat/event context, confidence weighting, local conflict mass, global minimum counts, deterministic rounding/sorting/pruning, privacy redaction, artifact truth-table behavior, starter vocabulary, and scalable graph construction.

## 4. Milestone 0 - Command Scaffold, Configuration, and Regression Guard

Status: planned.

Tasks:

1. Add `normalize` and `apply-session` to `AISidecarCommand` with help text and no-write validation-only execution (FR3-CLI-001 through FR3-CLI-009).
2. Add `NormalizationConfiguration` with the existing precedence rule: CLI flag > `AISIDECAR_*` environment variable > JSON config > built-in default (PW-007).
3. Add Phase 3 config fields: vocabulary path, file-list path, normalization mode, session subject/habitat/event, consensus threshold, affinity mode, affinity profile, min-affinity-for-consensus, session-only, unknown-session-context policy, separate session subject/habitat/event propagation flags, affinity privacy mode, write-report path, and allow-stale.
4. Restrict `apply-session` flags to relocation, source-verification, backup, conflict-policy, dry-run, logging, and stale-session behavior. Reject model/rendering/normalization-decision flags as `E_CONFIG_INVALID`.
5. Add schema constants for `ai-sidecar-vocabulary/1.0`, `ai-sidecar-normalization/1.0`, and `ai-sidecar-normalization-report/1.0`.
6. Add Phase 3 structured errors `E_VOCABULARY_INVALID` and `E_SESSION_STALE` to the additive taxonomy.
7. Extend no-XMP regression tests so `normalize --help`, `apply-session --help`, invalid invocation tests, and `normalize --session-only` fixture paths create or modify no `.xmp` files.
8. Keep non-help execution non-writing until later milestones produce a safe session and normalized plan.

Exit criteria:

```text
swift run aisidecar normalize --help       passed
swift run aisidecar apply-session --help   passed
swift test --filter NormalizationInvocationTests
swift test --filter NoXMPRegressionTests
swift test
```

No vocabulary decisions, session writing, model runs, XMP planning, or XMP writing exist yet at this milestone.

## 5. Milestone 1 - Vocabulary Schema, Loader, Integrity Checks, and Starter Vocabulary

Status: planned.

Tasks:

1. Implement `VocabularyDocument`, `VocabularyEntry`, and Codable load for `ai-sidecar-vocabulary/1.0` (FR3-001 through FR3-004).
2. Add `Resources/Vocabularies/default-vocabulary.json` and load it when `--vocabulary` is omitted (FR3-001a/b, AC3-019).
3. Compute SHA-256 over the canonical bytes read from the vocabulary file or bundled resource and record that hash as vocabulary identity (FR3-002b/028).
4. Implement entry defaults: conservative `requires_review`, propagation-only `auto_apply_allowed`, `direct_apply_policy`, `propagation_scope`, and `specificity` handling for species/taxonomy, people, named places, rare species, exact-location implications, named events, broad ancestors, behavior/habitat entries, and global-backstop entries (FR3-005 through FR3-005d).
5. Implement `VocabularyTextFolder`: Unicode NFC normalization, case folding, and whitespace collapse; do not fold diacritics and do not stem (FR3-003d).
6. Validate uniqueness of canonical paths, synonym uniqueness, canonical-vs-synonym collisions, parent existence, tree acyclicity, non-empty hierarchy levels, and pipe-free flat keywords (FR3-003a-h).
7. Build `VocabularyIndex` for canonical lookup, synonym lookup, ancestor traversal, descendant support, sibling lookup, namespace filtering, and mutually-exclusive-group lookup.
8. Add vocabulary defaults for `propagation_scope` and `specificity` so broad, mid-specific, direct-only, local, global, and review-required entries have deterministic policy even when optional fields are omitted (FR3-005a/b).
9. Expose a library API that the future GUI can reuse without invoking CLI code (FR3-006).

Core data shape:

```swift
struct VocabularyDocument: Codable, Sendable {
    let schemaVersion: String       // ai-sidecar-vocabulary/1.0
    let entries: [VocabularyEntry]
}

struct VocabularyEntry: Codable, Sendable, Hashable {
    let canonicalPath: String
    let flatKeyword: String
    let namespace: VocabularyNamespace
    let parentPath: String?
    let synonyms: [String]
    let requiresReview: Bool?
    let autoApplyAllowed: Bool?
    let directApplyPolicy: DirectApplyPolicy?
    let mutuallyExclusiveGroup: String?
    let exportFlatKeyword: Bool?
    let exportHierarchicalKeyword: Bool?
    let propagationScope: PropagationScope?
    let specificity: VocabularySpecificity?
    let notes: String?
}
```

Exit criteria: invalid vocabulary fixtures fail before any model run, session write, XMP plan, or XMP write. Tests cover duplicate canonical paths, duplicate synonyms, canonical/synonym collision, orphan parent, hierarchy cycle, empty path level, flat keyword containing `|`, default review policy, direct-apply defaults, propagation-scope defaults, specificity defaults, invalid global propagation policy, starter vocabulary loading, and stable vocabulary hash reporting.

## 6. Milestone 2 - Input Resolution and Normalization Session Schema

Status: implemented.

Implemented notes:

- Added `NormalizationInputResolver` for raw `.ai.json` sidecar collections, explicit UTF-8 file lists, and positional image scans.
- Added `NormalizationSessionDocument`, source asset records, source sidecar records, same-base-name group skeletons, privacy defaults, deterministic policy metadata, and early filename/list affinity input records.
- Added `NormalizePipeline.runSessionOnly` and wired `aisidecar normalize --session-only` to write session/report artifacts without creating, backing up, restoring, or validating `.xmp` sidecars.
- Added the `ai-sidecar-normalization-1.0.schema.json` resource and focused tests for file-list parsing, duplicate collapse, same-base-name grouping, source identity binding, session privacy fields, invocation-only `--allow-stale`, and no-XMP session-only behavior.

Tasks:

1. Implement `NormalizationInputResolver` for positional image file/folder input, `--file-list <path>`, and `normalize --from-json <path>` (FR3-009, FR3-CLI-001/008, AC3-021).
2. Reuse Phase 2 `RawJSONSidecarReader` and `RawJSONSidecarInputResolver` for `.ai.json` inputs, including schema-major acceptance, source resolution, `--source-root`, `--source-verification`, and inherited source errors.
3. Implement the UTF-8 file-list format: one source-image path per line, blank lines and `#` comments ignored, relative paths resolved relative to the file-list document, duplicates collapsed with a warning, unsupported paths reported.
4. Add `NormalizationSessionDocument` for `ai-sidecar-normalization/1.0` with session metadata, vocabulary identity, resolved configuration, privacy policy, artifact policy, XMP writer identity, source AI sidecars, source assets, same-base-name groups, affinity payload, batch candidates, local consensus records, per-asset decisions, XMP write plans, warnings, and errors (FR3-027 through FR3-030j).
5. Bind each source asset and per-asset decision to the Phase 1 source identity hash. Do not bind only to paths (FR3-030a).
6. Record output-dir behavior, source-root behavior, pair scope, source-verification policy, min-confidence, normalization mode, affinity mode, affinity profile, min-affinity-for-consensus, artifact policy, privacy mode, and all user session context values in the session file (FR3-029, FR3-030e).
7. Add `AssetAffinityInputs` extraction from available source metadata using the v0.7 source precedence: current resolved image metadata first, sidecar/provenance fallback where valid, filename/relative directory parsing, explicit file-list index, and same-base-name group membership. Missing affinity inputs are recorded but do not fail the session (FR3-AFF-003a through FR3-AFF-003c and FR3-AFF-007 through FR3-AFF-011).
8. Add `--session-only` execution for from-json and file-list inputs that writes the session skeleton and report but no `.xmp` files (FR3-CLI-005, AC3-017).
9. Add `OutputArtifactPolicy` for the v0.7 truth table and `AffinityPrivacyPolicy` for standard/debug-exact audit output.

Core data shape:

```swift
struct NormalizationSessionDocument: Codable, Sendable {
    let schemaVersion: String       // ai-sidecar-normalization/1.0
    let session: NormalizationSessionMetadata
    let vocabulary: VocabularyIdentity
    let resolvedConfiguration: NormalizationConfigurationSnapshot
    let xmpWriter: XMPWriterIdentity
    let sourceAISidecars: [SourceSidecarRecord]
    let sourceAssets: [NormalizationSourceAsset]
    let sameBaseNameGroups: [NormalizationSourceGroup]
    let affinity: NormalizationAffinityRecord
    let batchCandidates: [BatchCandidateSummary]
    let localConsensus: [LocalWeightedConsensusRecord]
    let perAssetDecisions: [PerAssetNormalizationDecision]
    let xmpWritePlans: [NormalizedXMPWritePlan]
    let warnings: [SidecarError]
    let errors: [SidecarError]
}
```

Exit criteria: `normalize --from-json <folder> --recursive --source-root <root> --session-only` and `normalize --file-list <list> --session-only` produce valid session/report artifacts without creating, modifying, backing up, restoring, or validating `.xmp` sidecars.

## 7. Milestone 3 - Candidate Observation Layer and Single-Image Canonicalization

Status: planned.

Tasks:

1. Convert Phase 2 `CandidateExtractionResult` records into `CandidateObservation` values without re-reading raw model JSON ad hoc (FR3-020 and inherited FR2-013 through FR2-019).
2. Preserve source field, input role, confidence band, evidence string, source sidecar, source image, model-run index, skipped-candidate reasons, and source-verification warnings.
3. Implement `CandidateCanonicalizer` using `VocabularyIndex`: exact canonical path/flat keyword/synonym matching after FR3-003d text folding; preserve canonical spelling and casing on output (FR3-003e, FR3-017).
4. Apply `--min-confidence` before counting and enforce unit observation support: duplicate same-asset observations add provenance but do not increase support mass.
5. Implement direct per-asset decisions using `direct_apply_policy` before any propagation.
6. Implement `--allow-specific-tags` only for Phase 2-style fallback/off-mode behavior; it shall not override vocabulary policy.
7. Implement `--normalization-mode off`: produce a Phase 3 session/report but use Phase 2 candidate extraction/export policy without vocabulary mapping or propagation (FR3-010a, AC3-020).
8. Implement `--normalization-mode single-image`: map and de-duplicate per asset or same-base-name group only, with no cross-image propagation (FR3-010b, AC3-020).
9. Apply `--unknown-session-context-policy` for user session values that do not match vocabulary; default reject before model runs/writes, optional flat-only unnormalized user keyword (FR3-023, AC3-011).
10. Enforce that raw model candidates containing `|` remain invalid for direct export; only valid vocabulary `canonical_path` values may introduce hierarchical separators (FR3-003g, AC3-013).
11. Record unmatched vocabulary, below-threshold, direct-apply-withheld, requires-review, specific-tag-policy, disabled-flat, disabled-hierarchical, duplicate, and hierarchy-separator skip reasons.

Exit criteria: fixture sidecars produce deterministic canonicalized per-asset decisions. Tests cover synonym collapse, canonical casing, unmatched terms, Phase 2 pass-through mode, single-image mode, pipe-containing raw candidates, flat-only unnormalized session subject, confidence filtering before matching, and preservation of whole-image versus subject-isolated provenance.

## 8. Milestone 4 - Metadata Affinity Graph, Local Weighted Consensus, and Session Context

Status: planned.

Tasks:

1. Implement `AssetAffinityInputs` extraction from resolved assets and same-base-name groups: source identity hash, capture-time quality, GPS presence, camera make/model/serial handling, lens model/ID handling, relative directory, filename stem, parsed sequence number, and explicit file-list index where present (FR3-AFF-001 through FR3-AFF-003c).
2. Implement `AssetAffinityProfile` with named `conservative`, `balanced`, and `aggressive` presets, config validation, edge-storage invariant checks, component weights, half-lives, cutoffs, gear boost, minimum consensus edge, stored-edge threshold, max-neighbor limit, and global backstop threshold (FR3-AFF-005/006/013a).
3. Implement `AffinityNeighborCandidateIndex` so production graph construction uses deterministic candidate windows before scoring: same-base-name group, explicit file-list window, filename sequence window, capture-time cutoff, GPS grid/window, and relative-directory proximity. Permit all-pairs scoring only for small fixtures or batches at or below the v0.7 threshold (FR3-AFF-013b).
4. Implement component scorers: `CaptureTimeAffinityScorer`, `GPSAffinityScorer`, `FilenameSequenceAffinityScorer`, and `CameraLensAffinityScorer` using the specified decay formula, caps, Haversine distance, filename parsing, file-list adjacency, and gear-as-boost-only rule (FR3-AFF-004 and FR3-AFF-007 through FR3-AFF-012).
5. Implement deterministic persisted scoring: six-decimal JSON score formatting, stable node order, stable edge order, max-neighbor truncation order, and decision tie-break keys (FR3-AFF-013c and FR3-AFF-020 through FR3-AFF-022, FR3-030i/j).
6. Implement `AssetAffinityGraph` over one node per source asset or same-base-name group. Ensure decision-contributing edges are retained in the audit trail even under pruning (FR3-AFF-001/013/013a, AC3-AFF-011/016).
7. Implement `BatchConsensusEngine` for hierarchy-aware global counts and strict global backstop behavior, including minimum eligible/support counts, broad specificity, namespace restrictions, and profile threshold (FR3-011, FR3-013e/f, AC3-AFF-018).
8. Implement `LocalWeightedConsensus` for support mass, eligible mass, local weighted agreement, supporting-neighbor count, maximum supporting affinity, and governing decision rules (FR3-AFF-014/016).
9. Implement hierarchy-aware support: descendant observations support every ancestor on the canonical path (FR3-013b, AC3-012).
10. Implement `LocalConflictMass` for direct target conflict, sibling conflict, mutual-exclusion conflict, conflict support mass, conflict weighted agreement, and conflict block rules (FR3-AFF-017a/b, AC3-AFF-017).
11. Apply `--min-confidence` before frequency counting, local support calculation, or conflict-mass calculation, not after (FR3-013c/013f).
12. Exclude model failures, unsupported formats, source-verification failures, and missing sidecars from denominators; list them in the report (FR3-013d).
13. Implement conservative propagation: vocabulary `auto_apply_allowed = true`, `requires_review = false`, compatible `propagation_scope`, specificity-specific local thresholds, no direct target conflict, no neighbor conflict mass block, no gear-only affinity, and no review-required propagation from model evidence (FR3-013a/014 and FR3-AFF-015/017).
14. Implement session context: `--session-subject`, `--session-habitat`, and `--session-event` are user evidence, not model evidence. Each context role uses its own allow-propagation flag, namespace matching, unknown-context policy, conflict rule, and provenance (FR3-007/008/015/016, FR3-022 through FR3-026c, AC3-006, AC3-026).
15. Implement `NormalizationClusterBuilder` for explanatory local clusters. Clusters support reports and audit only; decisions remain edge/threshold driven (FR3-AFF-018).
16. Record weak support, absence of support, low affinity, low support mass, low supporting-neighbor count, conflict mass, gear-only block, direct conflict, pruned-neighbor limits, source of propagation, and governing rule in per-asset decisions and report summaries.

Exit criteria: batch fixtures demonstrate high-affinity broad ancestor propagation, low-affinity same-folder non-propagation, missing-GPS fallback, present-but-distant GPS penalty, gear-only blocking, `requires_review` non-propagation, conflict suppression, session-subject propagation only with explicit flag, and user evidence recorded separately from model evidence.

## 9. Milestone 5 - Normalized XMP Plan Adapter and Dry-Run Output

Status: planned.

Tasks:

1. Implement `NormalizedXMPChangePlanner` that converts per-asset decisions into Phase 2-compatible planned flat and hierarchical keyword additions (FR3-031 through FR3-033).
2. Use each vocabulary entry's `flat_keyword` for `dc:subject` and `canonical_path` for `lr:HierarchicalSubject`, respecting `export_flat_keyword`, `export_hierarchical_keyword`, and Phase 2 export toggles (FR3-033a-c).
3. Ensure `write-unnormalized` user context writes only a flat keyword and never invents a hierarchy (FR3-033d).
4. Reuse Phase 2 same-base-name group planning, `--pair-scope`, target collision detection, output-dir mirroring, backup plan, validation plan, and one-write-per-XMP-target rule (FR3-031, AC3-018).
5. Preserve all normalization provenance under one planned term when multiple observations, roles, sidecars, or session context entries support it.
6. Implement dry-run for `normalize`: build the full session and normalized XMP write plans, but do not create, modify, back up, restore, or validate XMP sidecars (FR3-039).
7. If existing Phase 2 `XMPChangePlanner` requires Phase 2 `ExportableKeyword` input, add a narrow adapter. Do not fork the XMP planner or write engine.

Exit criteria: dry-run output explains every normalized tag, every skipped tag, every propagated tag, every conflict, every same-base-name group, every planned XMP target, and every affinity-backed propagation/block rule without touching `.xmp` files.

## 10. Milestone 6 - Reports, Summaries, Progress Logs, and Session-Only Finalization

Status: planned.

Tasks:

1. Implement `NormalizationReport` with schema id `ai-sidecar-normalization-report/1.0` (FR3-038).
2. Implement `NormalizationProgressLog` with self-contained JSONL records flushed after each completed session stage and each completed XMP target. XMP-target progress should align with Phase 2's one-record-per-target pattern.
3. Implement `NormalizationSummary` as Markdown for human review. It shall explain what was canonicalized, propagated, skipped, conflicted, weakly supported, planned, written, validated, or failed. For affinity decisions, include score band, basis signals, local weighted agreement, support mass, eligible mass, supporting-neighbor count, and proximity-specific block reasons (FR3-035/036 and FR3-AFF-014/016).
4. Include Lightroom Classic and Capture One post-export instructions using the Phase 2 application-instruction pattern (Phase 3 inheritance notes and FR3-034c).
5. Implement folder-run artifact naming (FR3-037):

```text
normalization-session-<ISO-8601-timestamp>.json
normalization-report-<ISO-8601-timestamp>.json
normalization-summary-<ISO-8601-timestamp>.md
normalization-progress-<ISO-8601-timestamp>.jsonl
```

6. Implement `--write-report <path>` for explicit report output while keeping the default artifact locations under `--output-dir`, scan root, JSON scan root, or session-file directory.
7. Finish `--session-only`: produce valid session/report/summary/progress artifacts and no `.xmp` sidecars, backups, restores, or validation attempts (AC3-017).

Exit criteria: reports are deterministic for fixtures, contain vocabulary hash, owned XMP writer identity, normalized decisions, affinity profile, affinity edges, local weighted consensus records, per-asset provenance, skip reasons, group membership, and application instructions. `--session-only` is covered by no-XMP tests.

## 11. Milestone 7 - Apply-Session Pipeline

Status: planned.

Tasks:

1. Implement `ApplySessionPipeline` that reads `ai-sidecar-normalization/1.0` and refuses unsupported major versions with inherited schema errors (FR3-030, AC3-007).
2. Reject all analysis and normalization-decision flags in `apply-session`, including affinity flags. Stored decisions are authoritative except for source relocation, source verification, stale override, dry-run, backup, and XMP conflict policy (FR3-CLI-009, FR3-030h, AC3-022, AC3-AFF-013).
3. Resolve sources from session paths, current paths, and `--source-root` when supplied. Verify source identities before writing (FR3-030a).
4. Fail stale assets as `E_SESSION_STALE` by default; continue the batch; allow explicit per-invocation `--allow-stale` override and record it per asset (FR3-030b).
5. Recompute target XMP paths from current source resolution and `--output-dir`. Report differences from stored paths (FR3-030d).
6. Read the current XMP sidecar at write time and merge against current disk content. Do not use a stale session copy of the sidecar as writeback source of truth (FR3-030c).
7. Write through `MetadataWriteEngine` and `OwnedXMPSidecarEngine`; reuse Phase 2 backup, restore, validation, source hash check, malformed XMP, unsupported RDF, and batch-continuation behavior (FR3-031/034).
8. Implement `apply-session --dry-run` as current-path/current-staleness/current-XMP preview without writing sidecars.

Exit criteria: session fixture tests prove model-free execution, stale identity rejection, explicit stale override, moved source-root resolution, output-dir target recomputation, current-XMP merge, validation failure restoration, malformed XMP fail-closed behavior, and invalid normalization flag rejection.

## 12. Milestone 8 - Analyze-and-Normalize Integration

Status: planned.

Tasks:

1. Implement `AnalyzeAndNormalizePipeline` as a thin adapter over the existing `AnalyzePipeline` followed by the same `NormalizePipeline` used by `--from-json` (AC3-001).
2. Preserve `.ai.json` sidecars by default. Allow `--no-write-ai-json` only in analyze-and-normalize mode while retaining in-memory provenance for the normalization session/report (FR3-CLI-003).
3. Preserve Phase 1 model-prepare fail-fast behavior. If model preparation fails, no normalization session, XMP plan, or XMP write should start unless a partial-session diagnostic mode is explicitly added later.
4. If analysis succeeds for some files and fails for others, normalize only successful raw sidecars. Failed assets are excluded from global consensus denominators, local eligible mass, and affinity decisions, and are reported under FR3-013d.
5. Keep all model, rendering, derivative-cache, and subject-isolation behavior inside Phase 1. Phase 3 should not reopen renderer, mask, prompt, model-runner, or schema design unless a concrete interface defect appears.
6. Ensure GPS context remains prompt/model-input context only. Coordinates, GPS-only evidence, and location commonness remain non-exportable unless supplied by user vocabulary/session evidence; affinity use of GPS remains internal and non-exportable (FR3-AFF-019).

Exit criteria: mocked analyze-and-normalize tests cover successful folder run, partial analysis failure, `--no-write-ai-json`, model-prepare failure, GPS-context provenance not exported as coordinates/location tags, and reuse of the same normalization path as from-json.

## 13. Milestone 9 - Interruption, Concurrency, and File-Safety Hardening

Status: planned.

Tasks:

1. Make `normalize` and `apply-session` SIGINT/SIGTERM-aware using the Phase 2 interruption model. In-flight XMP target writes may finish, restore, or remain unchanged; no partial target state should be ambiguous.
2. Ensure batch normalization aggregation completes before XMP writes begin. Do not interleave per-image analysis, per-image normalization, and per-member XMP writes to the same sidecar.
3. Preserve the one-write-per-XMP-target rule inherited from Phase 2.
4. Ensure `--dry-run` and `--session-only` can be interrupted without leaving `.xmp` files, backups, restores, or partially validated sidecars.
5. Re-run source hash checks before and after writes through the inherited Phase 2 export path.
6. Make progress records sufficient to diagnose whether interruption happened during input resolution, analysis, vocabulary loading, affinity scoring, normalization, plan construction, backup, write, validation, restore, or report writing.
7. Keep concurrency simple until correctness is proven: batch aggregation and plan construction may be parallelized later, but XMP writes should reuse the Phase 2 per-target safety semantics first.

Exit criteria: interruption tests simulate cancellation before session write, after session write before XMP write, during XMP write with backup, during validation failure restore, and during apply-session stale checks. Source images and existing sidecars remain unchanged or restored.

## 14. Milestone 10 - Automated Tests, Fixtures, and Offline Baseline

Status: planned.

Automated tests:

```text
NormalizationInvocationTests   CLI validation; invalid flag combinations; help output; unknown-session alias; separate session propagation flags; apply-session rejects decision flags
VocabularyLoaderTests          explicit and bundled vocabulary load; schema id; hash identity; unreadable/missing explicit path fails before model/write
VocabularyValidatorTests       duplicate canonical path; duplicate synonym; canonical/synonym collision; orphan parent; cycle; empty path level; pipe-bearing flat keyword; conservative default policy
DirectApplyPolicyTests         allow, withhold, flat_only, user_only; auto_apply propagation-only; requires_review interaction; --allow-specific-tags boundary
StarterVocabularyTests         Appendix minimum entries; synonym mapping; review leaf; broad/local/global entries; stable hash
FileListInputResolverTests     UTF-8 parsing; comments/blank lines; relative paths; duplicates; unsupported source path; mutual exclusivity
NormalizationSessionTests      ai-sidecar-normalization/1.0; resolved config; writer identity; privacy fields; artifact policy; source identity binding; schema evolution
CandidateCanonicalizerTests    synonym mapping; canonical spelling; unmatched terms; raw pipe rejection; off mode; single-image mode; provenance retention; unit observation support
AssetAffinityInputTests        image-source, from-json, file-list metadata precedence; missing/degraded metadata reporting; apply-session non-recomputation
AssetAffinityScorerTests       time/GPS/filename/list-adjacency decay; single-signal caps; gear boost; gear-only block; missing GPS neutral; distant GPS negative
AffinityNeighborCandidateTests bounded time/GPS/filename/list/directory windows; all-pairs small-batch allowance; deterministic candidate generation
AssetAffinityGraphTests        same-base-name node collapse; edge thresholds; max-neighbor limits; stored-edge invariant; deterministic edge order and pruning
LocalWeightedConsensusTests    support mass; eligible mass; local weighted agreement; broad/mid thresholds; low-affinity non-propagation; descendant support
LocalConflictMassTests         direct target conflict; sibling conflict; mutual-exclusion conflict; conflict mass and conflict agreement block rules
GlobalBackstopConsensusTests   hierarchy-aware global support; minimum eligible/support counts; namespace restrictions; broad-only default; min-confidence prefilter; denominator exclusions
SessionContextPolicyTests      subject/habitat/event match; unknown reject; write-unnormalized flat-only; independent propagation flags; conflict handling; model vs user provenance
NormalizedXMPChangePlanTests   flat/hierarchical export rules; direct-apply outcomes; same-base-name groups; pair scope; output-dir mirroring; collision propagation; dry-run completeness
OutputArtifactPolicyTests      normalize default; dry-run; session-only; session-only + dry-run; apply-session; apply-session --dry-run; --write-report placement
NormalizationReportTests       JSON report; Markdown summary; progress JSONL; skip reasons; privacy redaction; affinity explanations; Lightroom/Capture One instructions; engine/writer identity
ApplySessionPipelineTests      model-free execution; stale identity fail; --allow-stale override; current sidecar merge; target recomputation; malformed XMP fail-closed; no affinity recomputation
AnalyzeAndNormalizePipelineTests mocked analyze path; --no-write-ai-json; partial failures; model prepare fail-fast; GPS context not exported
NoXMPRegressionTests           analyze, benchmark, purge, export-model-inputs, normalize --session-only, dry-run paths, and apply-session --dry-run remain XMP-silent where required
```

Fixture policy:

1. Commit only synthetic, public-domain, or rights-cleared image fixtures.
2. Commit vocabulary fixtures for valid starter vocabulary, synonym collision, orphan parent, cycle, rare/review-required species, broad auto-apply entries, mid-specific local entries, direct-only entries, user-only entries, global-only broad entries, mutually-exclusive siblings, flat-only entries, and direct-apply policy permutations.
3. Commit recorded `.ai.json` fixtures covering whole-only, subject-only, both-mode, species candidates, habitat/scene candidates, malformed model runs, failed model runs, unknown additive fields, GPS-context evidence, coordinate/GPS-only evidence guards, capture-time/GPS/filename/gear metadata combinations, missing GPS, distant GPS, same-gear different-scene cases, and RAW+JPEG same-base-name groups.
4. Commit XMP fixtures with existing flat keywords, hierarchical keywords, unknown namespaces, and representative Adobe/Capture One adjustment namespaces.
5. Required CI shall not need ExifTool, a live Ollama instance, Lightroom Classic, Capture One, network access, or proprietary image samples.

Exit criteria:

```text
swift test --filter VocabularyLoaderTests
swift test --filter VocabularyValidatorTests
swift test --filter DirectApplyPolicyTests
swift test --filter StarterVocabularyTests
swift test --filter CandidateCanonicalizerTests
swift test --filter AssetAffinityInputTests
swift test --filter AssetAffinityScorerTests
swift test --filter AffinityNeighborCandidateTests
swift test --filter AssetAffinityGraphTests
swift test --filter LocalWeightedConsensusTests
swift test --filter LocalConflictMassTests
swift test --filter GlobalBackstopConsensusTests
swift test --filter OutputArtifactPolicyTests
swift test --filter NormalizedXMPChangePlanTests
swift test --filter ApplySessionPipelineTests
swift test --filter AnalyzeAndNormalizePipelineTests
swift test
```

## 15. Milestone 11 - Compatibility Smoke and Release Evidence

Status: planned.

Manual or semi-manual checks:

1. Build a session from existing `.ai.json` sidecars using `normalize --from-json --session-only` and confirm no XMP files are created.
2. Build a dry-run normalized change plan with the bundled vocabulary and confirm propagated versus skipped tags are explained, including affinity basis and local weighted agreement for propagated or blocked tags.
3. Write normalized XMP sidecars beside a throwaway RAW/JPEG pair and confirm one sidecar per same-base-name group.
4. Run `apply-session` against that session after moving sources under `--source-root`, confirming target path recomputation and source identity verification.
5. Confirm stale source identity fails by default and writes only with explicit `--allow-stale`, with the override recorded.
6. Import or synchronize a small throwaway set in Lightroom Classic. For already-imported photos, invoke Metadata > Read Metadata from Files and verify flat keywords and expected Lightroom-style hierarchy behavior.
7. Open or synchronize a small throwaway set in Capture One with intended Metadata preferences and verify sidecar-loaded flat keywords.
8. Run analyze-and-normalize against at least one JPEG and one RAW sample using the default model on the target machine.
9. Run representative GPS-context quality comparison under `--gps-context off|coarse|exact` or record a deferral.
10. Run the no-XMP regression set after Phase 3 modules are linked.
11. Archive or link Phase 1 Milestone 9 evidence or explicitly document deferrals before Phase 3 release.

Recommended command set:

```bash
swift test
swift run aisidecar normalize --help
swift run aisidecar apply-session --help
swift run aisidecar normalize --from-json ./fixtures/ai-json --recursive --source-root ./fixtures/source-images --session-only
swift run aisidecar normalize --from-json ./fixtures/ai-json --recursive --source-root ./fixtures/source-images --dry-run
swift run aisidecar normalize --from-json ./fixtures/ai-json --recursive --source-root ./fixtures/source-images --affinity-profile conservative --session-only
swift run aisidecar normalize --from-json ./fixtures/ai-json --recursive --source-root ./fixtures/source-images --affinity-profile conservative --dry-run
swift run aisidecar normalize --from-json ./fixtures/ai-json --recursive --source-root ./fixtures/source-images --output-dir /tmp/aisidecar-normalized-xmp-stage
swift run aisidecar apply-session /tmp/aisidecar-normalized-xmp-stage/normalization-session-<ISO>.json --dry-run
swift run aisidecar apply-session /tmp/aisidecar-normalized-xmp-stage/normalization-session-<ISO>.json --output-dir /tmp/aisidecar-apply-stage
swift run aisidecar normalize ./fixtures/source-images --recursive --mode both --output-dir /tmp/aisidecar-normalize-live
swift run aisidecar benchmark --self-test
```

Exit criteria before Phase 3 release:

1. Record command output paths, session/report/progress artifacts, written sidecar paths, and app readback notes.
2. Confirm `swift test` still passes after any compatibility-smoke fixture or documentation updates.
3. Update `README.md`, `AGENTS.md`, and this plan with the final Phase 3 evidence location.
4. Document any Phase 1 Milestone 9 or GPS-context comparison deferrals by sample/check, reason, and residual risk.

## 16. Risks and Mitigations

Risk: vocabulary synonyms map sideways or downward to false specificity.
Mitigation: require unique synonym ownership, explicit canonical paths, no stemming, no diacritic folding, conservative defaults, and tests proving upward mapping is allowed while unsafe sideways/downward inference is blocked unless explicit vocabulary or user session evidence supports it.

Risk: flat batch consensus propagates a wrong tag across an unrelated part of a folder.
Mitigation: default to metadata-affinity local consensus, not flat folder voting. Propagate only entries with `auto_apply_allowed = true`, never `requires_review` model evidence, apply minimum confidence before counting, require local weighted agreement/support-mass/supporting-neighbor thresholds, block direct target conflicts, and report all propagated tags with affinity basis and governing rule.

Risk: camera/lens match falsely connects unrelated sequences.
Mitigation: gear is a boost only. Without primary evidence from time, GPS, filename sequence, or file-list adjacency, affinity is zero and propagation is blocked as `blocked_gear_only_affinity`.

Risk: specific species, people, named events, or exact locations are exported too aggressively.
Mitigation: conservative vocabulary defaults mark those entries `requires_review = true` and `auto_apply_allowed = false`; GPS and coordinate-only evidence remains non-exportable; user evidence is recorded separately.

Risk: `apply-session` writes stale decisions to changed files.
Mitigation: bind decisions to source identity hashes, fail changed assets as `E_SESSION_STALE` by default, make `--allow-stale` invocation-only, and report every override.

Risk: `apply-session` overwrites sidecar changes made after the session was created.
Mitigation: never store a stale XMP copy as writeback truth; read and merge the current sidecar at write time through `OwnedXMPSidecarEngine`.

Risk: Phase 3 forks the Phase 2 XMP pipeline.
Mitigation: implement only a normalized planning adapter. All write/merge/backup/restore/validation behavior remains in `MetadataWriteEngine`, `OwnedXMPSidecarEngine`, and the Phase 2 export stack.

Risk: the bundled starter vocabulary is mistaken for a complete taxonomy.
Mitigation: document it as a conservative starter vocabulary, not a species/location authority. Its job is to support safe broad normalization and test coverage; richer user vocabularies can replace it.

Risk: file-list path handling is ambiguous.
Mitigation: define UTF-8 format, comment handling, relative path base, duplicate handling, and invalid combinations; report every collapsed duplicate and unresolved source.

Risk: dry-run or session-only creates sidecars accidentally.
Mitigation: no-XMP regression tests cover dry-run, session-only, invalid invocations, and existing Phase 1 commands after Phase 3 modules are linked.

Risk: final Phase 1 model/profile calibration changes the distribution of candidate terms after Phase 3 starts.
Mitigation: normalize versioned candidate records and raw sidecar schema outputs rather than implicit model behavior; require Phase 1 evidence or explicit deferral before release.

Risk: session/report artifacts leak sensitive affinity metadata such as exact GPS coordinates or camera serials.
Mitigation: persist derived distances/scores and hashed serials by default; keep exact affinity input persistence behind explicit debug/audit configuration; test privacy redaction in the normal report path.

Risk: global backstop propagation fires in a tiny folder because a percentage threshold is technically met.
Mitigation: require both global agreement percentage and minimum eligible/supporting asset counts, with fixture tests for small-folder suppression.

## 17. Traceability Matrix

```text
Requirement family        Primary modules                                           Primary tests                                      Milestone
FR3-CLI / FR3-ERR         NormalizeCommand, ApplySessionCommand, configuration       NormalizeCommandTests, ApplySessionCommandTests    M0
FR3-001..008              VocabularyLoader, VocabularyEntry, DirectApplyPolicy       VocabularyLoaderTests, DirectApplyPolicyTests     M1
Appendix A / AC3-030      StarterVocabularyResource, StarterVocabularyFixtures       StarterVocabularyTests                            M1
FR3-ORD-001..005          NormalizationDecisionOrder, NormalizationDecisionEngine    NormalizationDecisionOrderTests                   M2-M5
FR3-009..020              NormalizedCandidate, NormalizationDecisionEngine           NormalizationDecisionEngineTests                  M3-M5
FR3-AFF-003a/b            AssetAffinityInputExtractor                               AssetAffinityInputExtractorTests                  M4
FR3-AFF-004..012          Affinity scorers, AssetAffinityProfile                    AssetAffinityScorerTests                          M4
FR3-AFF-013a/c            AffinityScoreFormatter, AssetAffinityGraph                AffinityScoreFormatterTests, GraphTests           M4
FR3-AFF-013b              CandidateNeighborGenerator                                CandidateNeighborGeneratorTests                   M4
FR3-AFF-014..016          LocalWeightedConsensus                                    LocalWeightedConsensusTests                       M4
FR3-AFF-017a/b            LocalConflictMass                                         LocalConflictMassTests                            M4
FR3-013e/f                GlobalBackstopConsensus                                   GlobalBackstopConsensusTests                      M4
FR3-AFF-020..022          AssetAffinityPrivacy                                      AssetAffinityPrivacyTests, ReportTests            M4/M6
FR3-021..026f             SessionContextNormalizer, SessionContextPolicy            SessionContextNormalizerTests                     M4
FR3-027..030k             NormalizationSessionReader/Writer                         NormalizationSessionTests                         M2/M7
FR3-031..039              NormalizedXMPPlanAdapter, XMPExportPipeline reuse         PlanAdapterTests, NormalizePipelineTests          M5-M8
FR3-040..042              NormalizationArtifactPlanner                              NormalizationArtifactPlannerTests                 M6-M7
AC3-AFF-001..018          Affinity graph, consensus, conflict, privacy modules      Affinity and consensus fixture suite              M4/M10
Compatibility evidence    OwnedXMPSidecarEngine through Phase 2 writer path         Smoke checklist and release evidence              M11
```

Traceability maintenance rule: when a requirement ID is added or renamed after v0.7, this matrix shall be updated in the same commit as the requirement change.

## 18. Definition of Done

Phase 3 implementation is done when:

1. `aisidecar normalize --help` and `aisidecar apply-session --help` are implemented with valid command-specific flag surfaces.
2. Invalid flag combinations fail as `E_CONFIG_INVALID`, especially normalization-decision and affinity flags passed to `apply-session`.
3. The bundled starter vocabulary loads when `--vocabulary` is omitted and is validated through the same path as explicit vocabulary files.
4. Vocabulary integrity checks reject duplicated canonical paths, duplicated synonyms, canonical/synonym collisions, orphan parents, cycles, empty hierarchy levels, and pipe-bearing flat keywords.
5. `--file-list` accepts newline-delimited source paths, resolves relative paths predictably, collapses duplicates with warnings, and rejects invalid combinations.
6. `normalize --from-json` can build a valid normalization session without model runs.
7. `normalize <image-file-or-folder>` can call `AnalyzePipeline`, preserve `.ai.json` by default, and normalize successful outputs.
8. `--normalization-mode off`, `single-image`, and `batch-conservative` have distinct tested behavior.
9. Synonyms map to canonical paths and canonical spelling/casing is preserved.
10. Hierarchy-aware counting supports ancestors from descendant observations.
11. The metadata-affinity graph computes deterministic time/GPS/filename/list-adjacency primary scores and gear reinforcement scores under the named profile.
12. Same-base-name RAW/JPEG groups become one normalization node and do not double-count support.
13. Broad auto-apply tags propagate only through local weighted consensus at or above threshold and only without conflicts.
14. Low-affinity same-folder files do not receive propagated tags.
15. Camera/lens match alone never creates propagation eligibility.
16. Missing GPS does not fail normalization, while present-but-distant GPS lowers affinity.
17. `requires_review` tags never propagate from model evidence alone.
18. Session subject, habitat, and event propagation occur only when the corresponding `--allow-session-*-propagation` flag is supplied, and all such decisions are recorded as user evidence.
19. Unmatched session context values are rejected by default and write only flat unnormalized user keywords under `write-unnormalized`.
20. Normalized hierarchical output uses vocabulary `canonical_path` values and never raw model text containing `|`.
21. Same-base-name RAW/JPEG groups produce exactly one normalized XMP write plan per target sidecar, respecting `--pair-scope` during session creation.
22. `--session-only` and `--dry-run` create no `.xmp` files, backups, restores, or sidecar validation attempts.
23. Folder runs produce normalization session JSON, normalization report JSON, normalization summary Markdown, and progress JSONL artifacts.
24. Reports explain canonicalization, local/global propagation, skipped terms, conflicts, weak support, affinity basis/block reasons, target paths, validation results, and application instructions.
25. `apply-session` writes from a session without model runs, rendering, subject isolation, candidate extraction, vocabulary re-normalization, affinity recomputation, or consensus recomputation.
26. `apply-session` verifies source identities, fails stale assets by default, and records explicit `--allow-stale` overrides.
27. `apply-session` reads current sidecars at write time and merges through the owned XMP engine.
28. Existing XMP metadata remains semantically preserved, validated by owned parser snapshots and unmanaged-content fingerprints.
29. Malformed XMP fails as `E_XMP_PARSE_FAILED`; unsupported RDF/XMP shapes fail as `E_XMP_UNSUPPORTED_RDF`; neither modifies source files or existing sidecars.
30. Source image hashes remain unchanged after normalized export.
31. Phase 3 has no required ExifTool or external metadata executable dependency.
32. Phase 1 commands remain XMP-silent after Phase 3 code is linked.
33. Automated tests cover vocabulary, direct-apply policy, session context, canonicalization, confidence filtering, `--allow-specific-tags` boundaries, affinity metadata source/privacy, deterministic graph construction, neighbor pruning, local weighted consensus, local conflict mass, global backstop, reports, artifact truth table, apply-session, analyze-and-normalize, and no-XMP regression paths without a live model or network dependency.
34. Lightroom Classic and Capture One can read normalized sidecars written by the owned XMP engine in release smoke checks.
35. Phase 3 release has archived Phase 1 final signoff evidence or an explicit release note listing deferred Phase 1 evidence and residual risk.
36. GPS/capture time/camera/lens/filename affinity inputs are not exported as inferred XMP keywords.
37. Exact GPS coordinates and camera serials are redacted or hashed from default session/report affinity audit records according to the default privacy policy.
38. The traceability matrix maps each requirement family to implementation modules, milestones, and test families, and no requirement family is orphaned at release signoff.
## Reference Basis

This plan uses the same reference basis as the Phase 3 v0.7 requirements, Phase 2 v0.5 requirements, and Phase 2 v0.4 implementation plan. The implementation decisions depend directly on:

- Adobe XMP specifications: https://developer.adobe.com/xmp/docs/xmp-specifications/
- ISO 16684-1 / XMP data model and serialization overview: https://www.iso.org/obp/ui/
- W3C RDF/XML syntax and RDF container vocabulary: https://www.w3.org/TR/rdf-syntax-grammar/
- Apple Foundation XML document processing: https://developer.apple.com/documentation/foundation/xmldocument
- IPTC Photo Metadata Standard 2025.1 Keywords / `dc:subject`: https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata
- Adobe Lightroom Classic sidecar creation and metadata read actions: https://helpx.adobe.com/lightroom-classic/help/create-xmp-acr-files.html and https://helpx.adobe.com/lightroom-classic/help/advanced-metadata-actions.html
- Capture One XMP sidecar behavior and Auto Sync Sidecar XMP settings: https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files
