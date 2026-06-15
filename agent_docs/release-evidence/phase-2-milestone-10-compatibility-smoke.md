# Phase 2 Milestone 10 Compatibility Smoke Evidence

Date recorded: 2026-06-15

## Scope

This note records the Phase 2 Milestone 10 application-compatibility result for the owned XMP sidecar writer.

The checked artifact class is an `.xmp` sidecar written by `OwnedXMPSidecarEngine` using writer recipe `owned-xmp-sidecar-writer/1.0`. The sidecar contains Phase 2 managed keyword fields:

- `dc:subject` flat keywords
- `lr:HierarchicalSubject` Lightroom-style hierarchical keywords

## Result

Manual smoke checks confirmed that sidecars written by the owned XMP writer are readable by both target applications:

- Lightroom Classic can read the written sidecar keywords.
- Capture One can read the written sidecar keywords.

This satisfies the Phase 2 Milestone 10 compatibility-readback requirement for the XMP writer and clears the Phase 2 portion of the Phase 3 entry gate.

## Boundaries

The compatibility result does not broaden Phase 2 write scope:

- The project still writes sidecar `.xmp` files only.
- Source image files remain unmodified.
- GPS coordinates and GPS-only evidence remain non-exportable.
- Lightroom, Adobe Camera Raw, and Capture One adjustment/develop settings remain unmanaged and are preserved semantically when parseable.
- The application checks are release smoke evidence, not runtime dependencies.

Phase 1 Milestone 9 calibration and quality review evidence remains a separate release-readiness item unless explicitly deferred in release notes.
