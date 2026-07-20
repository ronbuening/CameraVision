# Changelog

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
