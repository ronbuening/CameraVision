# Project Invariants

Binding rules for any change, by any agent, at any level. If a task appears to require breaking one of these, stop and ask instead of proceeding. Each rule states the required behavior and the preferred path.

## Safety invariants (violations corrupt user data or trust)

1. **Analyze never touches XMP.** `aisidecar analyze` and every raw-sidecar path write only `.ai.json` artifacts. XMP creation/modification happens exclusively in `aisidecar write-xmp` and Phase 3 normalized export paths that reuse the Phase 2 export pipeline. There is a regression test for this; keep it passing and keep it meaningful.
2. **Source images are never modified.** All output is sidecars and run artifacts. This includes RAW, JPEG, TIFF, HEIC, PNG, and DNG.
3. **GPS is model-input context only.** `--gps-context` may influence prompts and raw-sidecar provenance. Coordinates and GPS-only evidence must never become XMP keywords or embedded metadata — guards exist in candidate extraction; extend them, don't bypass them.
4. **XMP writes are guarded.** Every XMP write path goes through the owned engine with deterministic backups, source-hash rechecks, post-write validation, and restore-on-validation-failure. New export features plug into that chain, never around it.
5. **`--export-model-inputs` is diagnostic-only.** It writes rendered inputs and a manifest — no model calls, no sidecars, no progress logs, no summaries, no XMP.
6. **`cleanup` removes only owned artifacts.** Never source images, `.xmp` sidecars, XMP backups, model-input exports, debug derivatives, derivative-cache files, or normalization session JSON.

## Compatibility invariants (violations silently break downstream consumers)

7. **Stable raw strings.** Public enum raw values, error codes (`SidecarError`), schema identifiers, and artifact-name patterns are load-bearing: existing sidecars, logs, and sessions reference them. Add new values; never rename or reuse existing ones.
8. **Additive schemas.** Sidecar/session/report schema changes follow the established schema-evolution rewrite support. A document written by an older version must remain readable.
9. **Config precedence is fixed:** CLI flag > `AISIDECAR_*` environment > JSON config file > built-in default. `aisidecar purge` resolves only derivative-cache settings and must not depend on model/runtime config validity.
10. **Exact-first vocabulary matching.** Punctuation, possessive, ampersand, and final-token singular/plural fallbacks are ambiguity-guarded and must never override exact canonical, flat-keyword, or synonym matches.

## Platform and process invariants

11. **macOS 15 minimum, Swift 6 strict concurrency, macOS-only.** No cross-platform availability annotations or platform docs unless a requirement broadens support.
12. **Tests are deterministic and offline.** Unit tests must not require Ollama, model downloads, real images, or network. Use the mock runners and recorded fixtures in `ModelRuntime` and `Tests/AISidecarCoreTests/Fixtures/`.
13. **Core/CLI split.** Reusable behavior goes in `Sources/AISidecarCore`; `Sources/AISidecarCLI` is argument parsing, command wiring, and presentation only. A future GUI target follows the same rule.
14. **Two executables, fixed shapes.** The CLI is one `aisidecar` binary with phase-specific subcommands — never split it into multiple CLI tools. The GUI is the separate `CupricAspect` executable (Phase 4, added at its M0). Do not add further executable products without an explicit requirement.
15. **Ollama capability preflight stays serial.** A parallel version was deliberately reverted (commit `a1366b6`). Do not re-parallelize it.
16. **Behavior changes ship with tests.** Prefer focused unit tests in `AISidecarCoreTests`. Follow `agent_docs/commenting_guide.md` for any substantive comments or public API docs.
17. **One milestone / one work item at a time** unless the user explicitly expands scope. Phase 1 Milestones 0-9a, Phase 2 Milestones 0-10, and Phase 3 Milestones 0-11 are complete — do not reopen released milestone work without new acceptance criteria.
