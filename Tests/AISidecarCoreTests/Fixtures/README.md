# AISidecarCore Test Fixtures

Fixtures in this directory are committed test data for deterministic, offline
Phase 1 coverage and shared regression checks. They must not require Ollama,
model downloads, image downloads, private photographs, or network access.

Phase 3 Milestone 10 baseline tests use synthetic in-memory fixtures from
`../Phase3NormalizationTestSupport.swift` for vocabulary, affinity, consensus,
session-context, planning, artifact, and reporting coverage. No proprietary
image or application fixture files are required for that baseline.

## Directories

- `model-responses/`: synthetic or recorded model-response text used by runtime
  and pipeline tests, including malformed responses that exercise repair.
- `golden-sidecars/`: normalized raw `.ai.json` sidecar fixtures. Golden tests
  normalize volatile paths, timestamps, durations, and derivative hashes before
  comparison.

Do not add XMP fixtures for Phase 1 writeback. Phase 1 tests may assert that
`.xmp` files are not created or modified, but XMP writing begins in Phase 2.
