# CupricAspectApp — agent notes

This is the Phase 4 GUI target (`swift run CupricAspect`). Before changing anything here, read:

1. `agent_docs/07-cupricaspect-gui-design.md` — the binding visual design spec (tokens, aperture component, per-screen layouts). The design handoff bundle it was extracted from lives in `agent_docs/gui-wrapper-for-cameravision/`.
2. `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md` — functional requirements (FR4-*, AC4-*).
3. `agent_docs/phase-4-gui-implementation-plan.md` — milestone status and remaining work (M9–M11); execution order is owned by `agent_docs/08-post-review-hardening-plan.md` §1.1. Implement one milestone or work item at a time.

Rules specific to this target:

- Presentation, state orchestration, and user interaction only (FR4-002). All processing belongs in `AISidecarCore`; anything two features share and any non-presentation logic moves there too.
- Design tokens live in `DesignSystem/Theme.swift` and come from design doc Section 3 — never hardcode palette hex values in views.
- Option controls map to Core enums (`AnalysisMode`, `ExistingPolicy`, `GPSContextMode`, `XMPPairScope`, `QualityScanMode`) — do not invent option values (FR4-044).
- Review keyword edits must be validated through Core `SessionReview.sanitizedEdit`; do not duplicate or weaken hierarchy and coordinate/GPS metadata safety in the GUI. The final normalized planner remains the independent export guard.
- No sample/placeholder data in shipped screens (FR4-045).
- Shells (`Shells/`) are chrome only; feature views and state live in `Features/` and are embedded by both shells so switching shells never loses state (FR4-041).
- UI for a not-yet-shipped feature is gated behind a hidden, off-by-default flag in `Support/FeatureFlags.swift` (a `CUPRIC_*` env var, following the existing dev-hook convention). Gates are presentation-only: the default (flag off) must preserve today's behavior exactly. Current gates: `CUPRIC_VOCABULARY_UI` (controlled-vocabulary UI) and `CUPRIC_STUDIO_UI` (Studio shell). Document new flags in `agent_docs/testing-and-verification.md`.
