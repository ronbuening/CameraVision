# Archived Documents

Historical planning documents for completed work. Nothing here is normative: requirements live in `agent_docs/01/02/03/04-*.md`, binding rules in `agent_docs/invariants.md`, and the durable implementation details extracted from these plans in `agent_docs/cli-implementation-notes.md`.

- `phase-1-cli-implementation-plan.md` — Phase 1 (analyze/raw sidecars) milestone plan; Milestones 0–9a complete. The still-open Milestone 9 calibration/quality evidence item and its benchmark plan were extracted to `cli-implementation-notes.md`.
- `phase-2-cli-implementation-plan.md` — Phase 2 (XMP export) milestone plan; Milestones 0–10 complete. (Formerly `phase-2-cli-implementation-plan(1).md`.)
- `phase-3-cli-implementation-plan.md` — Phase 3 (normalization) milestone plan; Milestones 0–11 complete. Its traceability matrix now lives, maintained, in `cli-implementation-notes.md`. (Formerly `phase-3-cli-implementation-plan-v0.3.md`.)
- `10-hardening-implementation-plan.md` — R1–R4 hardening execution companion; R1–R4 complete (audited 2026-07-11 and 2026-07-14). Plan 08 remains the live findings/scope/order authority. The still-open manual release step (B0-5 evidence, signing, tag) was extracted to `release-checklist.md`; the pre-M9 decision records it pointed at are recorded in `phase-4-gui-implementation-plan.md`.
- `14-quality-normalization-integration-plan.md` — QN1–QN8 quality × normalization integration; complete. Its QN7 GUI binding-point notes live, maintained, in `cli-implementation-notes.md` ("GUI binding points for quality-aware normalization"); design authority for the quality feature remains live doc 12.
- `15-quality-gui-integration-plan.md` — G1–G7 quality GUI integration; complete (including the 2026-07-18 audits). Its "where each concern lives" map is reflected in `architecture-map.md`'s GUI table; design authority remains live docs 12 and 07.
- `gui-wrapper-for-cameravision/` — the Claude Design HTML prototype handoff bundle the CupricAspect GUI was designed from. Superseded by `07-cupricaspect-gui-design.md`, which is the binding design spec; these prototypes sit at the bottom of the documented precedence order and must not be implemented from.

These files are kept verbatim as evidence of how the milestones were executed and verified (task breakdowns, implemented notes, test-count ledgers). Internal cross-references and status statements inside them reflect their writing date and are not maintained.
