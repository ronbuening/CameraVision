# AGENTS.md

## Project Context

CameraVision is a Swift 6 macOS 15 SwiftPM project for local AI-assisted photo metadata workflows. The current implemented state includes Phase 1 Milestones 0-8 plus the Milestone 9a benchmark harness and Phase 2 Milestones 0-9: package scaffold, CLI surface, config resolution, structured errors, logging, scanner/source identity, `--dry-scan`, sidecar naming, output tree mirroring, raw JSON sidecar writes, JSONL progress logs, batch summaries, interruption handling, model input profiles, whole-image rendering, full-resolution render retention, derivative cache with configurable lifecycle and `aisidecar purge`, subject isolation with the two-resolution Apple Vision/Core Image chain, diagnostic model-input export, Ollama vision model runtime client, v1.3 prompts and response schemas with conditional `species` candidates for biological target genres, schema-constrained model response repair, full analyze pipeline model execution, `model_runs` sidecar records with optional response-attempt provenance, configurable `stage_concurrency`, schema-evolution sidecar document rewrite support, golden sidecar fixtures, no-XMP Phase 1/Phase 2 regression guards, `aisidecar benchmark`, `aisidecar write-xmp` from-json and analyze-and-write export, Phase 2 export configuration defaults, raw sidecar reader/source resolution, candidate extraction and keyword policy, XMP target naming, same-base-name group resolution, dry-run change-plan output, the owned XMP sidecar parser/writer engine seam, merge conflict policy, deterministic backups, restore-on-validation-failure, post-write validation, source hash rechecks, export progress/report/summary artifacts, and offline tests including synthetic malformed-response fixtures.

Phase 1 produces raw `.ai.json` sidecars. It must not create or modify XMP files. XMP creation or modification is restricted to `aisidecar write-xmp` and the reusable Phase 2 export pipeline in `AISidecarCore`.

## Architecture Rules

- Put reusable behavior in `Sources/AISidecarCore`.
- Keep `Sources/AISidecarCLI` limited to argument parsing, command wiring, and user-facing presentation.
- Preserve the single executable shape: `aisidecar` with phase-specific subcommands.
- Preserve Swift 6 strict concurrency and macOS 15 minimum deployment.
- Keep tests deterministic and offline. Unit tests must not require Ollama, model downloads, images, or network access.

## Current Layout

- `Package.swift` defines `AISidecarCore`, `AISidecarCLI`, and `AISidecarCoreTests`.
- `Sources/AISidecarCore/Configuration` owns Phase 1 run config, Phase 2 XMP export config, defaults, and precedence.
- `Sources/AISidecarCore/Benchmarking` owns the Phase 1 Milestone 9a benchmark harness, result documents, aggregation, and self-test.
- `Sources/AISidecarCore/Errors` owns the additive project-wide error code set.
- `Sources/AISidecarCore/FileScanning` owns scanner/source image records.
- `Sources/AISidecarCore/Identity` owns source content identity hashing.
- `Sources/AISidecarCore/ModelRuntime` owns Ollama runtime preparation, model-run records, request/response handling, JSON schema validation, schema-constrained response repair, mock runners, and recorded-fixture replay.
- `Sources/AISidecarCore/Metadata` owns Phase 2 candidate extraction, keyword text normalization, specific-tag policy, XMP target naming, same-base-name group resolution, dry-run change planning, the owned XMP sidecar engine/parser/writer seam, backup management, and merge validation.
- `Sources/AISidecarCore/Rendering` owns model input profiles, render recipes, whole-image rendering, and the derivative cache.
- `Sources/AISidecarCore/SubjectIsolation` owns foreground mask generation, instance selection/merge policy, two-resolution subject crops, and subject-isolation provenance.
- `Sources/AISidecarCore/Sidecars` owns raw `.ai.json` sidecar naming, schema records, schema-evolution document rewrites, and atomic writes.
- `Sources/AISidecarCore/Reporting` owns text/JSON logging, JSONL progress logs, batch summaries, Phase 2 export schema identifiers, XMP export reports, progress logs, and summaries.
- `Sources/AISidecarCore/Pipeline` owns the full analyze pipeline, the earlier analyze shell pipeline test seam, the diagnostic model-input export pipeline, XMP export pipeline, analyze-and-write adapter, and interruption handling.
- `Sources/AISidecarCLI` owns `aisidecar analyze`, `aisidecar write-xmp`, `aisidecar benchmark`, `aisidecar purge`, and shared CLI option bindings.
- `Tests/AISidecarCoreTests` contains offline XCTest coverage, synthetic model-response fixtures, and normalized golden sidecar fixtures.

## Commands

- Build and test: `swift test`.
- CLI help checks: `swift run aisidecar --help`, `swift run aisidecar analyze --help`, `swift run aisidecar write-xmp --help`, `swift run aisidecar benchmark --help`, and `swift run aisidecar purge --help`.
- Manual full analyze smoke check: `swift run aisidecar analyze <image-or-folder> --mode both --output-dir <tmp-output>`.
- Manual diagnostic export check: `swift run aisidecar analyze <image-or-folder> --mode both --export-model-inputs <tmp-output>`.
- Benchmark self-test: `swift run aisidecar benchmark --self-test`.
- Small offline benchmark smoke check: `swift run aisidecar benchmark --spec source-identity-fast --max-hash-copies 1 --output-dir <tmp-output>`.
- Phase 2 dry-run planning smoke check: `swift run aisidecar write-xmp --from-json <json-file-or-folder> --recursive --source-root <image-root> --dry-run`.
- Phase 2 write smoke check: `swift run aisidecar write-xmp --from-json <json-file-or-folder> --recursive --source-root <image-root> --output-dir <tmp-output>`.
- If XCTest is missing because `xcode-select` points at Command Line Tools, run the same commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Documentation Index

- `agent_docs/01-cli-raw-json-sidecar-requirements.md`: read before Phase 1 work.
- `agent_docs/phase-1-cli-implementation-plan.md`: read before implementing any Phase 1 milestone.
- `agent_docs/02-cli-xmp-sidecar-requirements-updated.md`: read before Phase 2/XMP work.
- `agent_docs/phase-2-cli-implementation-plan(1).md`: read before implementing any Phase 2 milestone.
- `agent_docs/03-cli-normalized-batch-tagger-requirements.md`: read before Phase 3 normalization work.
- `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md`: read before GUI work.
- `agent_docs/commenting_guide.md`: read before adding or revising substantive code comments.
- `agent_docs/agent-md-best-practices.md`: read before changing this file.

## Implementation Guidance

- Implement one milestone at a time unless the user explicitly expands scope.
- The next planned implementation unit is Phase 2 Milestone 10 compatibility smoke and release evidence. Phase 1 Milestone 9 calibration and quality review remain required before release signoff.
- Do not start Phase 3 implementation until Phase 2 Milestone 10 smoke evidence is recorded and Phase 1 Milestone 9 evidence is either archived or explicitly deferred in release notes. After that gate, Phase 3 begins with `aisidecar normalize` / `aisidecar apply-session` scaffolding from `agent_docs/03-cli-normalized-batch-tagger-requirements.md`.
- Do not jump ahead to XMP writing while implementing Phase 1 work.
- Do not add XMP writing outside `aisidecar write-xmp` or the Phase 2 export pipeline it invokes.
- Keep the project macOS-only. Do not add cross-platform availability annotations or platform documentation unless a future requirement explicitly broadens the supported platforms.
- Keep `--export-model-inputs` as a diagnostic pre-model path: it must not write raw `.ai.json` sidecars, progress logs, batch summaries, XMP, or model output.
- Keep config precedence as CLI flag > `AISIDECAR_*` environment > JSON config file > built-in default. `aisidecar purge` resolves only derivative-cache settings and must not depend on model/runtime config validity.
- Preserve stable raw string values for public enums and error codes because later sidecars and logs depend on them.
- Follow `agent_docs/commenting_guide.md` whenever creating or updating types, methods, or substantive logic: add `///` documentation for reusable public API and inline comments for intent, constraints, requirement ties, and non-obvious domain behavior rather than restating code.
- Add or update tests with each behavior change. Prefer focused unit tests in `AISidecarCoreTests`.
- `Package.resolved` is tracked to keep dependency resolution reproducible.
- `.vscode/` is ignored; do not include editor-local launch settings in commits.

## Compaction Instructions

When compacting or summarizing active work, preserve:

- The current milestone and acceptance criteria.
- The modified file list.
- The latest build and test command results.
- Any relevant `agent_docs/` files already consulted.
