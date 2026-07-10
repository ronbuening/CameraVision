# Testing and Verification Guide

How to build, test, and smoke-check CameraVision. Run the relevant checks before claiming any change is done.

## Build and Unit Tests

```bash
swift test
```

All tests must pass. They are deterministic and offline — no Ollama, no network, no real photos (see invariant 12 in `agent_docs/invariants.md`).

If XCTest is missing because `xcode-select` points at Command Line Tools:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Test Conventions

- Core/CLI tests live in `Tests/AISidecarCoreTests`; GUI model tests live in `Tests/CupricAspectAppTests` (same offline/deterministic rules; `swift test` runs both). One file per subject (`FooTests.swift` for `Foo.swift`). Shared helpers use the `*TestSupport.swift` / `*Assertions.swift` pattern (`XMPAssertions`, `VocabularyTestSupport`, `TestImageFixtures`, `Phase3NormalizationTestSupport`).
- Fixtures live in `Tests/AISidecarCoreTests/Fixtures/` (vocabularies, golden sidecars, recorded model responses) and load via `Bundle.module`.
- **Golden tests** (`GoldenSidecarTests`, report/summary tests) assert serialized artifact output. If your change diffs a golden fixture, that is a deliberate schema/behavior decision — update the fixture explicitly and say so in the PR, never regenerate blindly.
- **Model behavior** is tested with mock runners and recorded-fixture replay from `ModelRuntime` — never a live model.
- Every behavior change adds or updates a focused unit test (AGENTS.md rule).

Artifact-filename tests inject a fixed four-hex suffix. New files must use the portable
`yyyy-MM-dd'T'HHmmssZ-<4hex>` token, paired files from one run must share it, and cleanup/scanning tests must retain
coverage for legacy colon-bearing, suffix-free names. ISO-8601 provenance fields inside JSON remain unchanged.

## CLI Help Checks (fast wiring smoke)

```bash
swift run aisidecar --help
swift run aisidecar analyze --help
swift run aisidecar write-xmp --help
swift run aisidecar normalize --help
swift run aisidecar apply-session --help
swift run aisidecar explain-session --help
swift run aisidecar benchmark --help
swift run aisidecar purge --help
swift run aisidecar cleanup --help
```

The batch-command help for `analyze`, `write-xmp`, `normalize`, `apply-session`,
and `cleanup` documents the stable process statuses: `0` for success, `1` for one
or more item failures, and `130` for interruption.
The `analyze`, `write-xmp`, and `normalize` help must also list `--model-timeout`
and `--model-retry-limit`; the latter two commands accept them only in their analyze modes.

## CLI Exit Status Checks

Use a disposable input/output location for these checks. A completed diagnostic
scan remains exit `0` even when its JSON contains unsupported-file records; a real
batch with a failed item exits `1`; and an interrupted batch exits `130`.

```bash
swift run aisidecar analyze <unsupported-file> --dry-scan; echo $?   # 0
swift run aisidecar analyze <unsupported-file> --dry-run; echo $?    # 1
swift run aisidecar analyze <image-or-folder> --output-dir <tmp-output>
# First Ctrl+C requests a graceful stop and cancels the live model request.
# A second Ctrl+C arms default SIGINT handling; a third force-terminates.
# After a graceful stop, run: echo $?                                # 130
```

## Offline Smoke Checks (no Ollama required)

```bash
swift run aisidecar benchmark --self-test
swift run aisidecar benchmark --spec source-identity-fast --max-hash-copies 1 --output-dir <tmp-output>
swift run aisidecar analyze <image-or-folder> --recursive --dry-scan
swift run aisidecar cleanup <folder> --recursive --dry-run
```

## Manual End-to-End Smoke Checks (need Ollama + a vision model)

Always use `--output-dir` pointing at a temp folder so artifacts stay out of real photo folders.

```bash
# Phase 1 analyze
swift run aisidecar analyze <image-or-folder> --mode both --output-dir <tmp-output>
# Diagnostic model-input export (no model calls)
swift run aisidecar analyze <image-or-folder> --mode both --export-model-inputs <tmp-output>
# Phase 2 dry-run plan, then write
swift run aisidecar write-xmp --from-json <json-file-or-folder> --recursive --source-root <image-root> --dry-run
swift run aisidecar write-xmp --from-json <json-file-or-folder> --recursive --source-root <image-root> --output-dir <tmp-output>
# Phase 3 session-only, dry-run, write, file-list, and analyze-and-normalize
swift run aisidecar normalize --from-json <json-folder> --recursive --source-root <image-root> --session-only --output-dir <tmp-output>
swift run aisidecar normalize --from-json <json-folder> --recursive --source-root <image-root> --dry-run --output-dir <tmp-output>
swift run aisidecar normalize --from-json <json-folder> --recursive --source-root <image-root> --output-dir <tmp-output>
swift run aisidecar normalize --file-list <image-list.txt> --session-only --output-dir <tmp-output>
swift run aisidecar normalize <image-or-folder> --mode both --output-dir <tmp-output>
```

### Phase 4 GUI hardening (M8 / AC4-025)

```bash
# Kill mid-analyze, resume, CLI parity, no-database check (repeatable):
Scripts/m8-kill-relaunch-check.sh [count] [model]
# Synthetic scale fixture for grid/queue checks (M3/M11); --sidecar-template patches a
# real pipeline sidecar per image so full review sessions can be fabricated (B0-6):
swift Scripts/generate-synthetic-fixture.swift <dir> [count]
# Env-gated review scale test (B0-6; needs a generated fixture dir):
CUPRIC_SCALE_TESTS=1 CUPRIC_SCALE_DIR=<fixture-dir> swift test
# GUI dev hooks: CUPRIC_IMPORT_PATH=<folder> auto-imports on launch;
# CUPRIC_DEBUG_AUTORUN=1 [CUPRIC_DEBUG_ACTION=analyze|write|normalize] runs the wizard flow.
# Hidden feature-flag previews (off by default; see Support/FeatureFlags.swift):
# CUPRIC_VOCABULARY_UI=1 reveals the controlled-vocabulary UI (custom vocab picker,
#   "if not in vocabulary" policy, stale banner, and "vocabulary" copy in normalize/export);
# CUPRIC_STUDIO_UI=1 activates the in-progress Studio shell (makes "Nonlinear UI" live).
```

### Packaging checks (B0-1)

```bash
# Resource-bundle relocation proof (both relocated layouts + negative control):
Scripts/wi2-relocation-check.sh
# Assemble dist/CupricAspect.app + DMG (ad-hoc signs by default; --sign <identity> for Developer ID):
Scripts/build-release.sh
```

## Performance Verification

For performance-affecting changes, capture before/after numbers (see the Verification Baseline section of `agent_docs/05-efficiency-improvement-plan.md`): release-build benchmark runs, wall-clock on a fixed image set, and Instruments (Time Profiler, Allocations, System Trace lock contention) where relevant. Report numbers in the PR description.

## Release Evidence

Compatibility smoke evidence (Lightroom Classic / Capture One import of written XMP) follows the recorded pattern in `agent_docs/release-evidence/`. Release-gating rules live in AGENTS.md and `agent_docs/08-post-review-hardening-plan.md` §1.1; the open Phase 1 Milestone 9 calibration item is detailed in `agent_docs/cli-implementation-notes.md`.
