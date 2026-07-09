## Summary

<!-- What does this change do, and why? Reference the milestone / work item. -->

## Related

<!-- Milestone or work item (e.g. plan 08 §1.1 item), issue links. -->

## Verification

- [ ] `swift test` passes locally
- [ ] `swift build --build-tests` succeeds
- [ ] Added or updated focused tests for the behavior change
  (`Tests/AISidecarCoreTests` and/or `Tests/CupricAspectAppTests`)

## Invariant checklist

<!-- See AGENTS.md and agent_docs/invariants.md. Confirm each item this PR could touch. -->

- [ ] **XMP-write invariant:** `analyze` and all raw-sidecar paths still never
      create or modify XMP. XMP writes happen only in `write-xmp` and Phase 3
      normalized export paths.
- [ ] Reusable behavior lives in `AISidecarCore`; `AISidecarCLI` stays argument
      parsing / wiring / presentation only.
- [ ] Swift 6 strict concurrency and the macOS 15 minimum are preserved
      (no cross-platform annotations).
- [ ] Scope is a single milestone / work item unless the reviewer expanded it.
- [ ] Relevant `agent_docs/` (requirements, plans, invariants, release evidence)
      are updated where this change affects them.

## Notes for reviewer

<!-- Anything worth calling out: trade-offs, follow-ups, deferred items. -->
