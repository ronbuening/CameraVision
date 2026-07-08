# AGENTS.md

## Project Context

CameraVision is a Swift 6, macOS 15, SwiftPM project for local-first AI-assisted photo metadata. The single CLI executable `aisidecar` scans image folders, renders model inputs, runs a local Ollama vision model, writes auditable raw `.ai.json` sidecars (Phase 1), exports accepted keywords to XMP sidecars through a project-owned XMP engine (Phase 2), and performs vocabulary-normalized batch tagging with durable, replayable sessions (Phase 3). The SwiftUI GUI (Phase 4) is the app `CupricAspect` (`Sources/CupricAspectApp`, run via `swift run CupricAspect`): milestones M0–M8a and beta-readiness items B0-1–B0-4 and B0-6 are done (v0.1.0-beta.1, packaged via `Scripts/build-release.sh`). Outstanding: B0-5 release evidence, Developer ID signing/notarization, and the beta tag. M9–M11 (Studio shell, database mode, scale) are post-beta.

**Status:** Phase 1 Milestones 0-9a, Phase 2 Milestones 0-10, the GPS-context milestone, Phase 3 Milestones 0-11, and Phase 4 GUI milestones M0–M8a plus B0 (minus B0-5 and signing) are implemented. Overall release signoff still requires Phase 1 Milestone 9 calibration evidence or an explicit deferral. Do not reopen completed milestone work without new acceptance criteria.

**The one rule to never forget:** `analyze` and all raw-sidecar paths never create or modify XMP. XMP writes happen only in `aisidecar write-xmp` and Phase 3 normalized export paths that reuse the Phase 2 export pipeline.

## Before You Change Code

1. Read `agent_docs/invariants.md` — the binding safety, compatibility, and process rules. All of them apply to every change.
   - **Precedence when documents conflict:** `invariants.md` > phase requirements docs > implementation plans > design doc 07 > design prototypes in `agent_docs/gui-wrapper-for-cameravision/`. Resolve using the higher document and note the conflict for the maintainer; don't average.
2. Read `agent_docs/architecture-map.md` if you are unsure where code lives or which type is the entry point.
3. Read the phase requirements doc for the area you are changing (index below).
4. Verify with `agent_docs/testing-and-verification.md`; at minimum `swift test` must pass.

## Architecture Rules

- Reusable behavior goes in `Sources/AISidecarCore`; `Sources/AISidecarCLI` is argument parsing, command wiring, and presentation only.
- Preserve the two fixed executable shapes — the single `aisidecar` CLI (+ subcommands) and the `CupricAspect` app — plus Swift 6 strict concurrency and the macOS 15 minimum. macOS-only — no cross-platform annotations.
- Keep tests deterministic and offline (no Ollama, network, model downloads, or real images).
- Add or update focused unit tests in `Tests/AISidecarCoreTests` (Core/CLI) or `Tests/CupricAspectAppTests` (GUI) with every behavior change.
- Follow `agent_docs/commenting_guide.md` for substantive comments and public API docs.
- Implement one milestone or work item at a time unless the user explicitly expands scope.

## Commands

```bash
swift test                          # build + full offline test suite (must pass)
swift run aisidecar --help          # CLI wiring check
swift run CupricAspect              # GUI launch check
```

If XCTest is unavailable (Command Line Tools only), prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Full smoke-check commands (dry runs, benchmark self-test, per-phase manual checks) are in `agent_docs/testing-and-verification.md`.

## Documentation Index

Read only what your task touches.

**Always-relevant references**
- `agent_docs/invariants.md`: binding rules for every change.
- `agent_docs/architecture-map.md`: module map, key types, pipeline entry points, artifact locations.
- `agent_docs/testing-and-verification.md`: build, test, smoke-check, and release-evidence procedures.
- `agent_docs/commenting_guide.md`: before adding or revising substantive comments.
- `agent_docs/agent-md-best-practices.md`: before changing this file.

**Phase requirements (read before changing that area)**
- `agent_docs/01-cli-raw-json-sidecar-requirements.md`: analyze, raw sidecars, benchmark, rendering, model runtime, GPS context.
- `agent_docs/02-cli-xmp-sidecar-requirements-updated.md`: XMP export pipeline.
- `agent_docs/03-cli-normalized-batch-tagger-requirements.md`: normalization.
- `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md` + `agent_docs/phase-4-gui-implementation-plan.md` + `agent_docs/07-cupricaspect-gui-design.md`: GUI work (the CupricAspect app — requirements, milestone ledger + remaining M9–M11, and the binding visual design spec; the design handoff bundle in `agent_docs/gui-wrapper-for-cameravision/` is historical source only).
- `agent_docs/cli-implementation-notes.md`: durable Phase 1–3 implementation details — open Milestone 9 benchmark plan, shipped defaults, boundary rules, interruption invariants, live Phase 3 traceability matrix.

**Plans (execution order for everything: plan 08 §1.1)**
- `agent_docs/08-post-review-hardening-plan.md`: **the active plan** — beta ship-blockers (R1, gates the `v0.1.0-beta.1` tag) and post-review hardening milestones R2–R4; §1.1 is the single authoritative execution order across all plans.
- `agent_docs/10-hardening-implementation-plan.md`: execution-level companion to plan 08 — work R1–R4 items from here (code excerpts verified 2026-07-08, proposed changes, test skeletons, commit subjects); plan 08 wins on scope/acceptance conflicts.
- `agent_docs/05-efficiency-improvement-plan.md`: efficiency backlog — scheduled in plan 08 §1.1 (after R4, before M9), not a parallel active track.
- `agent_docs/06-packaging-single-app-plan.md`: as-built packaging reference; signing/notarization runbook for the beta tag.
- `agent_docs/09-post-m11-feature-roadmap.md`: post-M11 feature outlines (requirements, approaches, acceptance criteria, tests) — nothing there starts before M11 closes.
- `agent_docs/release-evidence/`: recorded compatibility smoke evidence.
- `agent_docs/archive/`: completed Phase 1–3 implementation plans — historical, not maintained; do not take instructions from them.

## Housekeeping

- `Package.resolved` is tracked for reproducible dependency resolution.
- `.vscode/` is ignored; do not commit editor-local launch settings.

## Compaction Instructions

When compacting or summarizing active work, preserve:

- The current milestone or work item and its acceptance criteria.
- The modified file list.
- The latest build and test command results.
- Any relevant `agent_docs/` files already consulted.
