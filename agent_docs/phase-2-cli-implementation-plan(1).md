# Implementation Plan - Phase 2 CLI XMP Sidecar Writer

Version: 0.2
Date: 2026-06-12
Supersedes: 0.1
Implements: Phase 2 Requirements v0.4 (`02-cli-xmp-sidecar-requirements-owned-xmp.md`)
Builds on: Phase 1 Requirements v0.4 (`01-cli-raw-json-sidecar-requirements.md`) and Phase 1 Implementation Plan v0.9 (`phase-1-cli-implementation-plan.md`)
Binary: `aisidecar` (adds subcommand: `write-xmp`)
Core library: `AISidecarCore`
Minimum deployment target: macOS 15, Swift 6 strict concurrency
Default model: `gemma4:26b-a4b-it-qat` for analyze-and-write mode
Metadata runtime: project-owned `OwnedXMPSidecarEngine`

Traceability in this plan points at Phase 2 v0.4 requirement IDs (`FR2-xxx`, `AC2-xxx`) and inherited project-wide IDs (`PW-xxx`, `FR1-xxx`).

## 0. Current Implementation Status

Phase 2 Milestone 0 is implemented. The repository now includes the `aisidecar write-xmp` validation-only scaffold, Phase 2 export configuration defaults and precedence resolution, Phase 2 policy enums, placeholder export report/change-plan schema identifiers, additive source-verification error codes, and no-XMP regression coverage around existing Phase 1 commands.

No Phase 2 XMP writing code exists yet. The `write-xmp` command intentionally resolves configuration and then fails with a not-implemented error until the later export pipeline and owned XMP engine milestones land.

The useful baseline remains Phase 1: Milestones 0-8 and the Milestone 9a benchmark harness are implemented. The repository has the reusable scanner, source identity, raw sidecar naming/writing, atomic file writer, progress log, batch summary, derivative renderer/cache, subject-isolation service, `VisionModelRunner` protocol, Ollama runner, mock and recorded-fixture runners, v1.3 prompt/schema resources, response parser/repair path, raw sidecar schema-evolution wrapper, diagnostic model-input export, no-XMP guards, and `aisidecar benchmark` / `aisidecar purge` commands.

The Phase 1 release signoff is not complete. The remaining evidence is Milestone 9 calibration and manual quality review: full benchmark matrix, final profile/`keep_alive`/`stage_concurrency` defaults, foreground-mask failure classification, tag-quality review, multi-subject instance-selection spot checks, rights-cleared format coverage or documented deferral, and final AC1-001 through AC1-015 acceptance evidence.

That state is good enough for Phase 2 implementation. It is not good enough for Phase 2 release without either archived Phase 1 signoff evidence or an explicit release note listing any deferred Phase 1 evidence.

Latest verification recorded after Phase 2 Milestone 0:

```text
swift test                                      156 tests, 1 skipped, 0 failures
swift run aisidecar write-xmp --help           passed
swift run aisidecar --help                     passed
swift run aisidecar analyze --help             passed
swift run aisidecar benchmark --help           passed
swift run aisidecar purge --help               passed
```

The next implementation unit is Milestone 1: raw sidecar reader, `.ai.json` scanning, and source resolution. This revision replaces the earlier ExifTool runtime plan with a narrow owned XMP sidecar engine. Do not reopen Phase 1 rendering, isolation, model runtime, or prompt/schema design unless Phase 2 exposes a concrete interface defect.

## 1. Implementation Position

Phase 2 is a metadata-write phase, not a second analysis phase. The safest path is to implement `write-from-json` first, using recorded Phase 1 sidecars and synthetic fixtures. That exercises candidate extraction, source verification, XMP naming, same-base-name grouping, change planning, merge, backup, restore, validation, dry-run, and reporting without invoking Ollama, Apple Vision, RAW decoding, or derivative rendering.

Analyze-and-write mode comes after the XMP layer is stable. It should call the existing `AnalyzePipeline` and then pass the resulting raw sidecar or in-memory equivalent to the same export planner used by `--from-json`. There must not be two extraction or write paths.

All new logic lives in `AISidecarCore`; `AISidecarCLI/WriteXMPCommand.swift` is argument handling and validation only (PW-002). XMP manipulation goes through `MetadataWriteEngine`. The required Phase 2 engine is `OwnedXMPSidecarEngine`, a project-owned sidecar reader/writer limited to `.xmp` files and the managed keyword fields. The engine protocol remains mandatory so Phase 4 or future packaging can swap implementations without touching policy code.

The owned engine is allowed to parse and rewrite XMP, but only within a narrow contract. It shall not become a general metadata library. It creates new XMP packets, parses existing XMP/RDF/XML sidecars, edits `dc:subject` and `lr:hierarchicalSubject` bags, preserves unmanaged content semantically, and fails closed on unsupported RDF shapes. ExifTool is not a runtime dependency.

## 2. Technical Stack

```text
Language:
  Swift 6, strict concurrency, async/await where file/process boundaries justify it

Project system:
  Swift Package Manager
  Existing targets: AISidecarCore, AISidecarCLI, AISidecarCoreTests

CLI parsing:
  Swift ArgumentParser; WriteXMPCommand composes only the shared options valid for its workflow

Raw sidecar input:
  Codable JSON; RawJSONSidecarReader; ai-sidecar-json/1.x schema-evolution acceptance

Candidate extraction:
  Codable/raw JSON traversal over parsed_response_json candidate arrays;
  confidence-band filtering; role/source provenance retention

Keyword policy:
  Foundation Unicode normalization; whitespace collapse; case-insensitive de-duplication;
  heuristic SpecificTagPolicy for Phase 2 exclusions

XMP metadata engine:
  OwnedXMPSidecarEngine; Foundation XMLDocument/XMLNode tree editing;
  XMPDocumentParser and XMPDocumentWriter;
  XMPKeywordReader and XMPKeywordMerger for dc:subject and lr:hierarchicalSubject;
  XMPMetadataSnapshot and XMPUnmanagedContentFingerprint for validation

File safety:
  AtomicFileWriter pattern; temporary files in destination directory;
  deterministic backups; restore on validation failure

Hashing:
  SourceIdentity verification using the Phase 1 identity policy;
  source-file hash recheck after write for AC2-007

Reporting:
  JSONL progress log, JSON export report, Markdown summary;
  dry-run change-plan JSON

Testing:
  XCTest; MockMetadataWriteEngine for pipeline seams; owned-engine fixture tests;
  recorded .ai.json fixtures; XMP fixtures with existing keywords, unknown namespaces, and develop settings;
  optional external-tool comparison scripts outside the required CI path
```

## 3. Repository Layout

Planned additions are shown only where Phase 2 creates or changes files.

```text
CameraVision/
  Sources/
    AISidecarCore/
      Configuration/
        XMPExportConfiguration.swift           // implemented M0 config, enums, invocation validation
      Metadata/
        MetadataWriteEngine.swift              // protocol and common result types
        OwnedXMPSidecarEngine.swift            // FR2-029 live owned engine
        XMPDocumentParser.swift                // XML/RDF parse, unsupported-shape detection
        XMPDocumentWriter.swift                // canonical new-sidecar serialization and existing-document serialization
        XMPKeywordReader.swift                 // dc:subject and lr:hierarchicalSubject reads
        XMPKeywordMerger.swift                 // normalized bag merge and de-duplication
        XMPMetadataSnapshot.swift              // pre/post field snapshots for validation
        XMPUnmanagedContentFingerprint.swift   // semantic preservation fingerprint
        XMPChangePlan.swift                    // ai-sidecar-xmp-change-plan/1.0
        XMPMergeValidator.swift                // FR2-028 snapshot/fingerprint validation
        XMPBackupManager.swift                 // deterministic backup/restore
        XMPNaming.swift                        // <base>.xmp and --output-dir mirroring
        SameBaseNameGroupResolver.swift        // RAW+JPEG/shared-sidecar planning
        CandidateExtractor.swift               // Phase 1 JSON -> extraction candidates
        KeywordTextNormalizer.swift            // NFC, trim, whitespace collapse, pipe rejection
        SpecificTagPolicy.swift                // Phase 2 conservative specific-tag heuristic
        ExportPlanner.swift                    // extraction/grouping -> XMPChangePlan
      Sidecars/
        RawJSONSidecarReader.swift         // ai-sidecar-json/1.x read path
        RawJSONSidecarDocument.swift       // unknown-field wrapper if not already public
      Pipeline/
        XMPExportPipeline.swift            // from-json/change-plan/write/report path
        AnalyzeAndXMPPipeline.swift        // thin adapter over AnalyzePipeline + export path
      Reporting/
        XMPExportSchemaIdentifiers.swift       // implemented M0 schema constants
        XMPExportProgressLog.swift         // one record per XMP target
        XMPExportReport.swift              // ai-sidecar-xmp-export/1.0
        XMPExportSummary.swift             // Markdown human summary
    AISidecarCLI/
      WriteXMPCommand.swift                // argument handling only
      AISidecarCommand.swift               // registers write-xmp subcommand
  Tests/
    AISidecarCoreTests/
      XMPExportInvocationTests.swift       // implemented M0 CLI-shape validation seam
      NoXMPRegressionTests.swift           // implemented M0 AC2-018 guard
      Fixtures/
        ai-json/
        xmp/
        source-images/
      MetadataTests/
      XMPExportPipelineTests/
```

Do not put XML/RDF implementation details into candidate extraction, grouping, or policy modules. The engine boundary should allow tests to prove policy behavior with a mock engine and XMP preservation behavior with focused owned-engine fixtures. Do not introduce a required external metadata executable.

## 4. Milestone 0 - Phase 2 Scaffold and Regression Guard

Status: implemented.

Implemented:

1. Add `write-xmp` to `AISidecarCommand` and create `WriteXMPCommand` with help text and option validation.
2. Add Phase 2 config fields with the existing precedence rule: CLI flag > `AISIDECAR_*` environment variable > JSON config > built-in default (PW-007).
3. Add Phase 2 error codes to the additive taxonomy: `E_SOURCE_MISSING` and `E_SOURCE_IDENTITY_MISMATCH`.
4. Add no-XMP regression tests around existing Phase 1 commands after the new XMP modules are linked: `analyze`, `benchmark`, `purge`, and `analyze --export-model-inputs` must remain XMP-silent (AC2-018).
5. Add placeholder export report/change-plan schema constants: `ai-sidecar-xmp-export/1.0` and `ai-sidecar-xmp-change-plan/1.0`.
6. Keep non-help `write-xmp` execution validation-only: it resolves configuration, then fails with a not-implemented `E_CONFIG_INVALID` until later milestones add export execution.

Exit criteria, latest result:

```text
swift run aisidecar write-xmp --help     passed
swift test                               156 tests, 1 skipped, 0 failures
```

No XMP-writing code exists yet at this milestone.

## 5. Milestone 1 - Raw Sidecar Reader, JSON Scan, Source Resolution

Tasks:

1. Implement `RawJSONSidecarReader` for `ai-sidecar-json/1.x` with `E_SCHEMA_UNSUPPORTED` for unsupported major versions (FR2-000a).
2. Implement `--from-json <file-or-folder>` scanning. Folder scans include `.ai.json` files only and recurse only under `--recursive` (FR2-000).
3. Implement source resolution for `--from-json`: `--source-root + relativePath`, recorded absolute source path, sibling source beside the JSON, then `E_SOURCE_MISSING` (FR2-000b).
4. Implement `--source-verification <fail|warn|skip>` with default `fail` (FR2-000c/d).
5. Reject model/render/derivative flags with `--from-json` as `E_CONFIG_INVALID` (FR2-CLI-002/003).

Data shape:

```swift
struct ResolvedRawSidecarInput: Sendable {
    let sidecarPath: URL
    let sidecar: RawJSONSidecar
    let sourcePath: URL?
    let sourceIdentityStatus: SourceIdentityStatus
    let relativePath: String?
    let warnings: [SidecarError]
}
```

Exit criteria: fixture `.ai.json` files can be scanned from a flat folder and a mirrored output tree; `--source-root` resolves originals; stale hashes fail by default and continue under `warn`; unsupported schema versions fail without crashing a batch.

## 6. Milestone 2 - Candidate Extraction and Keyword Policy

Tasks:

1. Implement `CandidateExtractor` over `model_runs[*].parsed_response_json` for Phase 1 v1.3 candidate-bearing fields: `genre_or_photography_type`, `species`, `main_subjects`, `secondary_subjects`, `scene_context`, `habitat_or_setting`, `behavior_or_action`, and `proposed_keywords` (FR2-013a).
2. Preserve role, source field, source image, source sidecar, model-run index, confidence, and evidence where present (FR2-013b/014).
3. Implement confidence-band filtering using `low < medium < high`, default `medium` (FR2-018).
4. Implement `KeywordTextNormalizer`: NFC, trim, whitespace collapse, empty-term handling, `|` rejection, case-insensitive de-duplication with first casing preserved (FR2-006a-d).
5. Implement `SpecificTagPolicy`: exclude species field terms, binomials, proper-place/person/event patterns, and exact-ID evidence by default; allow them under `--allow-specific-tags` (FR2-019/019a).
6. Record every skipped term with a reason code (FR2-019c).

Exit criteria: recorded sidecar fixtures produce deterministic extraction records and exportable term sets. Tests must include malformed candidate arrays, missing evidence for scene/habitat fields, duplicate terms across roles, a pipe-containing term, an empty/whitespace term, a species candidate, a binomial, and a generic subject term that must not be over-filtered.

## 7. Milestone 3 - XMP Naming, Group Resolution, and Change Planning

Tasks:

1. Implement `XMPNaming`: every source image maps to `<base>.xmp`; no embedded writing (FR2-001/001a).
2. Implement default beside-source output and `--output-dir` mirrored staging output (FR2-001b/c).
3. Implement target collision detection, including case-insensitive filesystem collisions (FR2-001d).
4. Implement `SameBaseNameGroupResolver`: group by relative directory plus basename, not by raw `.ai.json` filename (FR2-002).
5. Implement `--pair-scope union|raw-only|jpeg-only` (FR2-002a/b).
6. Produce one `XMPChangePlan` per XMP target, not per source member (FR2-002c).
7. Implement dry-run output using the same change plan that write mode will execute (FR2-033).

Core model:

```swift
struct XMPChangePlan: Codable, Sendable {
    let schemaVersion: String              // ai-sidecar-xmp-change-plan/1.0
    let targetXMPPath: String
    let sourceMembers: [SourceMemberPlan]
    let flatKeywordsToAdd: [PlannedKeyword]
    let hierarchicalKeywordsToAdd: [PlannedKeyword]
    let skippedCandidates: [SkippedCandidate]
    let existingPolicy: XMPConflictPolicy
    let backupPlan: BackupPlan
    let validationPlan: ValidationPlan
    let warnings: [SidecarError]
}
```

Exit criteria: dry-run over a RAW+JPEG fixture group produces exactly one target plan with unioned, de-duplicated terms and source provenance; restrictive pair scopes select only the intended member; `--output-dir` mirrors the tree and collision cases fail before write.

## 8. Milestone 4 - Owned XMP Sidecar Engine

Tasks:

1. Define `MetadataWriteEngine` with methods for `prepare`, `readSnapshot`, `apply`, `validateReadable`, and `shutdown`. `shutdown` may be a no-op for the owned engine but remains part of the protocol seam.
2. Implement `MockMetadataWriteEngine` first so the export pipeline can be tested without XML fixture complexity.
3. Implement `XMPDocumentParser` using Foundation XML document/tree APIs. It shall parse XMP packets, locate `x:xmpmeta`, `rdf:RDF`, and suitable `rdf:Description` nodes, and classify malformed XML as `E_XMP_PARSE_FAILED`.
4. Implement unsupported-RDF detection. If the parser encounters a well-formed sidecar shape that cannot be safely merged without risking data loss, fail closed as `E_XMP_UNSUPPORTED_RDF`.
5. Implement `XMPKeywordReader` for `dc:subject/rdf:Bag/rdf:li` and `lr:hierarchicalSubject/rdf:Bag/rdf:li`.
6. Implement `XMPKeywordMerger` to merge normalized planned keywords into those bags while preserving existing values and de-duplicating case-insensitively.
7. Implement `XMPDocumentWriter` for new sidecars. New files use a canonical XMP packet with `rdf:RDF`, `rdf:Description rdf:about=""`, and only the needed namespaces and keyword bags.
8. Implement existing-sidecar serialization. Semantic preservation is required; byte-for-byte XML preservation is not.
9. Implement `XMPMetadataSnapshot` and `XMPUnmanagedContentFingerprint` for pre/post validation.
10. Implement write application to a temporary sidecar file, not directly to the final target (FR2-026).
11. Map parse, unsupported-RDF, merge, write, and validation failures to structured errors with bounded diagnostic excerpts (FR2-029f/h).

Exit criteria: a new XMP sidecar can be generated and read back by the owned parser; a fixture XMP file can be copied to a temp path, updated with flat and one-level hierarchical keywords, re-read by the owned parser, and validated for semantic preservation. Tests prove malformed XML and unsupported RDF shapes fail without replacing the original file.

## 9. Milestone 5 - Merge, Backup, Restore, and Validation

Tasks:

1. Implement `XMPBackupManager` with deterministic `.xmp.bak-<ISO-8601-timestamp>` backups (FR2-027).
2. Implement `--xmp-conflict-policy fail|merge|backup-and-merge` exactly as specified (FR2-027a-c).
3. Reject `backup-and-merge` combined with `--no-backup-sidecars` as `E_CONFIG_INVALID`.
4. Implement pre/post `XMPMetadataSnapshot` diffing. Exclude only target keyword fields intentionally updated; compare bag/list fields as sets where order is not meaningful (FR2-028a).
5. Validate that new expected flat and hierarchical terms are present after write (FR2-028).
6. Compare `XMPUnmanagedContentFingerprint` values to prove unmanaged XML/RDF content survived semantically (FR2-028b).
7. Restore backup on validation failure and record `E_VALIDATION_FAILED` without making batch state ambiguous (FR2-028c).
8. Recompute source file hashes after write for AC2-007.

Exit criteria: tests cover existing keyword preservation, unknown namespace semantic preservation, develop namespace semantic preservation, conflict-policy fail, merge without backup, backup-and-merge, invalid backup flag combination, simulated validation failure with restore, malformed/unsupported XMP failure, and source hash non-modification.

## 10. Milestone 6 - Write-from-JSON End-to-End Pipeline

Tasks:

1. Implement `XMPExportPipeline` for `--from-json`: JSON scan -> source resolution -> source verification -> extraction -> grouping -> change planning -> optional dry-run -> engine write -> validation -> report.
2. Folder runs write one progress record per XMP target, not per source member (FR2-032c).
3. Folder runs produce `xmp-export-progress-<ISO>.jsonl`, `xmp-export-report-<ISO>.json`, and `xmp-export-summary-<ISO>.md` (FR2-032).
4. Single-file runs print essential summary to stdout; dry-run emits the full change plan (FR2-034b).
5. Reports include source verification status, owned XMP engine name/version, writer recipe version, group membership, tags added, tags skipped, backups, validation, errors, and application instructions (FR2-034/034a).

Exit criteria:

```text
swift run aisidecar write-xmp --from-json Tests/.../ai-json/single.ai.json --dry-run
swift run aisidecar write-xmp --from-json Tests/.../ai-json/folder --recursive --source-root Tests/.../source-images --dry-run
swift test --filter XMPExportPipelineTests
```

The dry-run output must be complete enough to explain exactly why every candidate was written or skipped.

## 11. Milestone 7 - Analyze-and-Write Integration

Tasks:

1. Implement `AnalyzeAndXMPPipeline` as a thin adapter: call the existing `AnalyzePipeline`, collect successful raw sidecars or in-memory model outputs, and pass them into the same export planner used by `--from-json`.
2. Preserve `.ai.json` sidecars by default (FR2-031). `--no-write-ai-json` may use in-memory raw sidecar records for extraction, but reports must still include model/prompt/schema/runtime provenance.
3. Ensure `--existing` controls raw `.ai.json` behavior only; existing XMP behavior remains governed by `--xmp-conflict-policy` (FR2-CLI-004).
4. Preserve Phase 1 model-prepare fail-fast behavior. If model preparation fails, no XMP planning or writing starts.
5. If analysis succeeds for some files and fails for others, export XMP only for the successful sidecars unless a group target requires failed members under the selected `--pair-scope`; report skipped/failed members explicitly.
6. Keep model calls serialized through the existing Phase 1 model stage. XMP writing starts only after the write plans are resolved; no interleaved per-member writes to the same XMP target.

Exit criteria: analyze-and-write creates an `.ai.json` and `.xmp` for a mocked model fixture; `--no-write-ai-json` creates only XMP and report artifacts; model prepare failure leaves no XMP; partial analysis failure does not corrupt a grouped XMP target.

## 12. Milestone 8 - Batch Interruption, Resume, and Operational Semantics

Tasks:

1. Reuse `InterruptionMonitor` and atomic write helpers for XMP/report artifacts.
2. Define interruption behavior for an in-flight XMP target: the target is either unchanged, fully written and validated, or restored from backup. It is never partially replaced.
3. Flush progress JSONL after each completed XMP target.
4. On rerun, `--xmp-conflict-policy` governs existing XMP behavior. There is no separate XMP checkpoint format.
5. Verify that backups from interrupted or failed runs are listed in the report when a report can be written.
6. Confirm that derivative-cache clear-after-success still depends only on analyze success when analyze-and-write mode uses the Phase 1 pipeline; XMP failure shall not delete derivatives prematurely if the overall invocation failed.

Exit criteria: an interruption test using the mock engine leaves no partial target and rerun completes deterministically. A simulated interruption after backup but before replacement restores or leaves the original sidecar unmodified.

## 13. Milestone 9 - Tests and Fixtures

Automated tests:

```text
WriteXMPCommandTests        CLI validation; invalid --from-json flag combinations;
                            backup policy conflicts; help output
RawJSONSidecarReaderTests   ai-sidecar-json/1.x acceptance; higher-major rejection;
                            unknown field preservation when rewriting
SourceResolutionTests       --source-root mapping; recorded path fallback;
                            sibling fallback; missing source; identity mismatch
CandidateExtractorTests     all Phase 1 v1.3 candidate fields; role provenance;
                            confidence thresholds; malformed/missing fields
KeywordTextNormalizerTests  NFC; trim; whitespace collapse; pipe rejection;
                            empty terms; case-insensitive de-duplication
SpecificTagPolicyTests      species field exclusion; binomials; named places;
                            generic taxonomy allowed; --allow-specific-tags
XMPNamingTests              <base>.xmp; --output-dir mirroring;
                            case-insensitive collisions
SameBaseNameGroupTests      RAW+JPEG grouping; union/raw-only/jpeg-only scopes;
                            one target per group; contribution counts
XMPChangePlanTests          dry-run completeness; skipped reasons; backup plan;
                            validation plan
MetadataWriteEngineTests    mock engine behavior; protocol result mapping;
                            write failure and validation failure capture
OwnedXMPSidecarEngineTests  new sidecar generation; existing sidecar merge; malformed XML;
                            unsupported RDF fail-closed behavior
XMPDocumentParserTests      dc:subject reads; lr:hierarchicalSubject reads; namespace handling
XMPMergeValidatorTests      new keyword presence; existing keyword preservation;
                            unknown namespace semantic preservation; develop namespace preservation
XMPBackupManagerTests       deterministic backups; restore on validation failure;
                            missing backup failure behavior
XMPExportReportTests        JSON schema id; Markdown summary; application instructions;
                            per-target progress records
XMPExportPipelineTests      from-json end-to-end; dry-run; source verification;
                            RAW+JPEG union; validation failure continuation
AnalyzeAndXMPPipelineTests  mocked analyze-and-write; --no-write-ai-json;
                            model prepare fail-fast; partial analysis failure
NoXMPRegressionTests        analyze, benchmark, purge, export-model-inputs remain XMP-silent
```

Fixture policy:

1. Commit only synthetic, public-domain, or rights-cleared image fixtures.
2. Commit recorded `.ai.json` fixtures covering whole-only, subject-only, both-mode, biological species candidates, malformed/failed model runs, and unknown additive fields.
3. Commit XMP fixtures with existing flat keywords, hierarchical keywords, unknown namespaces, and representative Adobe/Capture One adjustment namespaces.
4. Optional external-tool comparison tests may exist outside the required CI path, but the required CI baseline shall use the owned parser/writer and shall not require ExifTool, a live Ollama instance, or network access.

## 14. Milestone 10 - Compatibility Smoke and Release Evidence

Manual or semi-manual checks:

1. Write a new XMP sidecar beside a throwaway proprietary RAW file and verify the owned parser reads `XMP-dc:Subject` and `XMP-lr:HierarchicalSubject`.
2. Update an existing XMP sidecar containing keywords and non-target XMP fields; verify preservation by report and by owned snapshot/fingerprint diff. Optional external-tool readback may be used for developer confidence but is not required for acceptance.
3. Import or synchronize a small throwaway set in Lightroom Classic. For already-imported photos, invoke Metadata > Read Metadata from Files and verify the keywords appear.
4. Open or synchronize a small throwaway set in Capture One with the intended Metadata preferences and verify sidecar-loaded keywords.
5. Run from-json against a mirrored AI JSON output tree with `--source-root`.
6. Run analyze-and-write against at least one JPEG and one RAW sample using the default model on the target machine.
7. Run the Phase 1 no-XMP regression set after Phase 2 is merged.
8. Archive or link final Phase 1 Milestone 9 evidence, or explicitly document any deferrals before Phase 2 release.

Recommended command set:

```bash
swift test
swift run aisidecar write-xmp --help
swift run aisidecar write-xmp --from-json ./fixtures/ai-json --recursive --source-root ./fixtures/source-images --dry-run
swift run aisidecar write-xmp --from-json ./fixtures/ai-json --recursive --source-root ./fixtures/source-images --output-dir /tmp/aisidecar-xmp-stage
swift run aisidecar analyze ./fixtures/source-images --recursive --mode both --output-dir /tmp/aisidecar-ai-json --existing overwrite
swift run aisidecar write-xmp ./fixtures/source-images --recursive --mode both --output-dir /tmp/aisidecar-xmp-stage
swift run aisidecar benchmark --self-test
```

## 15. Risks and Mitigations

Risk: the owned XMP writer corrupts or drops existing metadata.
Mitigation: keep the engine narrow, edit only `dc:subject` and `lr:hierarchicalSubject`, update temporary copies, snapshot pre/post XMP fields, compare unmanaged-content fingerprints, fail closed on unsupported RDF shapes, validate preservation, and restore backups on failure.

Risk: Phase 2 writes species or exact-place tags too aggressively.
Mitigation: default `--allow-specific-tags` is false; the heuristic errs toward exclusion; reports show skipped terms and reasons; Phase 3 replaces the heuristic with vocabulary policy.

Risk: `--from-json` writes tags for an image that changed after analysis.
Mitigation: source identity verification defaults to `fail`; `warn` and `skip` require explicit user choice and are recorded in reports.

Risk: RAW+JPEG pairs overwrite each other's XMP sidecar.
Mitigation: group resolution happens before writing; one change plan and one write per target XMP path; contribution counts are reported.

Risk: hierarchical keywords pollute the user's Lightroom hierarchy.
Mitigation: Phase 2 writes one-level hierarchical mirrors only; it does not invent parent paths or use `|`. Controlled hierarchy construction waits for Phase 3.

Risk: owned XML serialization changes formatting, prefix order, or attribute order.
Mitigation: define preservation semantically rather than byte-for-byte; tests compare parsed metadata meaning and unmanaged fingerprints instead of textual equality.

Risk: the owned engine grows into a general metadata library.
Mitigation: keep Phase 2 scope limited to sidecar-only XMP and two managed keyword fields. Embedded metadata and broader XMP authoring require later-phase requirements.

Risk: Phase 2 breaks Phase 1's no-XMP guarantee.
Mitigation: keep all XMP writing behind `write-xmp`; add no-XMP regression tests around `analyze`, `benchmark`, `purge`, and model-input export.

Risk: final Phase 1 model/profile calibration changes analysis outputs after Phase 2 starts.
Mitigation: Phase 2 extraction consumes the versioned raw sidecar schema, not implicit model behavior. Phase 2 implementation can proceed from fixtures; Phase 2 release waits for Phase 1 signoff or documents remaining evidence.

## 16. Definition of Done

Phase 2 implementation is done when:

1. `aisidecar write-xmp --from-json` reads Phase 1 `.ai.json` files or folders and writes safe XMP sidecars.
2. `aisidecar write-xmp <image-file-or-folder>` reuses `AnalyzePipeline`, preserves `.ai.json` by default, and writes XMP from the same export planner.
3. Source resolution and identity verification work for beside-source sidecars and mirrored `--output-dir` raw-sidecar trees.
4. Candidate extraction handles all Phase 1 v1.3 candidate fields, confidence bands, evidence, roles, and source provenance.
5. Flat keywords write to `XMP-dc:Subject`; hierarchical export writes one-level entries to `XMP-lr:HierarchicalSubject` when enabled.
6. Specific tags are excluded by default and exported only when `--allow-specific-tags` is supplied.
7. RAW+JPEG same-base-name groups produce exactly one XMP write plan and one write per target sidecar.
8. Existing XMP sidecars are merged safely; existing keywords, unknown namespaces, and develop/edit namespaces are preserved and validated.
9. Backups are deterministic, referenced in reports, and restored on validation failure.
10. Dry-run produces a complete change plan without modifying source images or sidecars.
11. Folder runs produce progress JSONL, JSON export reports, and Markdown summaries with Lightroom Classic and Capture One post-export instructions.
12. Source image hashes remain unchanged after export.
13. The owned XMP engine name/version and writer recipe version are recorded; owned parser/merge/write failures are structured.
14. Phase 2 has no required external metadata executable dependency.
15. Phase 1 commands remain XMP-silent after the Phase 2 code is merged.
16. Automated tests cover the policy and pipeline paths without a live model or network dependency.
17. Phase 2 release has archived Phase 1 final signoff evidence or an explicit release note listing deferred Phase 1 evidence.

## Reference Basis

This plan uses the same reference basis as the Phase 2 v0.4 requirements. The implementation decisions depend directly on:

- Adobe XMP specifications: https://developer.adobe.com/xmp/docs/xmp-specifications/
- ISO 16684-1 / XMP data model and serialization overview: https://www.iso.org/obp/ui/
- W3C RDF/XML syntax and RDF container vocabulary: https://www.w3.org/TR/rdf-syntax-grammar/
- Apple Foundation XML document processing: https://developer.apple.com/documentation/foundation/xmldocument
- IPTC Photo Metadata Standard 2025.1 Keywords / `dc:subject`: https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata
- Adobe Lightroom Classic sidecar creation and metadata read actions: https://helpx.adobe.com/lightroom-classic/help/create-xmp-acr-files.html and https://helpx.adobe.com/lightroom-classic/help/advanced-metadata-actions.html
- Capture One XMP sidecar grouping and Auto Sync Sidecar XMP behavior: https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files
