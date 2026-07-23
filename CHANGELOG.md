# Changelog

## 0.2.1 — 2026-07-23

`0.2.1` improves throughput and maintainability across the analyze, normalize, XMP, and GUI paths, and introduces the
backend-selection architecture needed for future local vision runtimes. Ollama remains the only usable inference
backend in this release.

### Highlights

- Added first-class `model_backend` selection through CLI flags, environment variables, `config.json`, and the
  CupricAspect Settings and run-options interfaces. Supported values are `ollama`, `apple`, and `auto`; `auto`
  resolves one backend for the whole run and records the concrete backend in provenance.
- Added backend-aware availability, model discovery, setup guidance, preflight reporting, and tuning-control
  presentation. Model-discovery results are cached and isolated by backend and endpoint.
- Added a compile-gated Apple FoundationModels descriptor and defensive runner stub. It is intentionally shown as
  unavailable because current public FoundationModels APIs do not accept image input; no live Apple inference is
  included.
- Updated the Wizard so enabling **Assess image quality** in Step 2 selects **Quality grading** by default in Step 3
  for write-capable runs. Grading remains independently switchable and remains ineffective when assessment is off.

### Performance and reliability

- Shared render and subject-isolation services across each analysis pass, parallelized source-identity hashing with
  the configured concurrency bound, indexed normalization consensus lookups, reused XMP parses within an export, and
  passed freshly written raw sidecars directly into combined pipelines.
- Cached GUI review rows and decision indexes so ordinary verdict changes update only the affected item.
- Reduced avoidable disk work by writing analysis sidecars once, skipping unchanged debug-derivative copies, and
  batching progress-log synchronization while still flushing explicitly on interruption and close.
- Extended `stage_concurrency` to positional normalization scans, including CLI, environment, config, and GUI
  plumbing, while preserving deterministic result and error ordering.
- Hardened concurrent lookup caching, symlink-aware file-kind checks, resolved-backend availability probing, and
  timeout propagation without changing the existing Ollama error behavior.

### Architecture and maintainability

- Split configuration resolution, XMP safeguards, model-input export, raw-sidecar pairing, quality extraction, and
  shared change-plan assembly into focused Core components while preserving artifact bytes and ordering.
- Moved sidecar interpretation out of the GUI and into Core, introduced a shell-independent wizard flow coordinator,
  shared model discovery across GUI surfaces, and split oversized Settings, options, review, and export views.
- Consolidated path, timing, collection, callback, decision-ID, display-ranking, forward-compatible enum, CLI output,
  subject-isolation, and report-writing helpers.

### Compatibility and release boundary

- Default Ollama runs keep the existing sidecar and artifact bytes: `model_backend` is omitted for the default, and
  `auto` resolving to Ollama is byte-identical to an explicitly selected Ollama run.
- Existing raw sidecars, normalization sessions, error codes, command shapes, and XMP safety guarantees remain
  compatible. Analyze and quality-only paths remain XMP-silent, and source images are never modified.
- Live Apple inference remains explicitly deferred until Apple ships a public vision-capable FoundationModels API
  and suitable test hardware is available.
- Distribution remains ad-hoc signed and not notarized under the current release policy.

## 0.2.0 — 2026-07-20

`0.2.0` is the first full, non-prerelease CupricAspect release.

### Highlights

- Added opt-in, experimental AI image-quality assessment and deterministic grading across the CLI and CupricAspect.
- Added quality-only and sequential scan modes; sequential scans keep tagging output byte-identical to a run without
  assessment while writing quality results to a paired sidecar.
- Added quality-aware normalization and guarded XMP export for quality keywords, color labels, Capture One urgency,
  and Lightroom pick/reject flags. Rating export remains opt-in.
- Added GUI controls, progress presentation, review details, Settings defaults, and export summaries for the quality
  workflow.
- Refined the application icon and corrected wizard alignment and option-card layout issues found during the beta.

### Release signoff

- Phase 1 Milestone 9 calibration and quality review is complete by maintainer acceptance of the accumulated benchmark,
  reference-run, automated-test, and acceptance evidence. See
  `agent_docs/release-evidence/phase-1-milestone-9-calibration-signoff.md`.
- The experimental quality feature's application read-back and evidence-driven default review remain tracked as
  stages S5.1–S5.3. The feature remains visibly labeled experimental and is off by default.
- This release is ad-hoc signed and not notarized by Apple. Developer ID signing and notarization are deliberately
  deferred; users should follow the documented first-launch Gatekeeper steps after verifying the published checksum.

### Compatibility and safety

- `analyze`, `assess-quality`, and all raw-sidecar paths remain XMP-silent.
- Source images are never modified; XMP writes continue through the guarded project-owned export engine.
- Existing raw sidecars, normalization sessions, and default tagging-only output remain backward compatible.
