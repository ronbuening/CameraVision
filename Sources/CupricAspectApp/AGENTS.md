# CupricAspectApp — agent notes

This is the Phase 4 GUI target (`swift run CupricAspect`). Before changing anything here, read:

1. `agent_docs/07-cupricaspect-gui-design.md` — the binding visual design spec (tokens, aperture component, per-screen layouts). The design handoff bundle it was extracted from lives in `agent_docs/gui-wrapper-for-cameravision/`.
2. `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md` (v0.4) — functional requirements (FR4-*, AC4-*).
3. `agent_docs/phase-4-gui-implementation-plan.md` (v0.2) — milestone order. Implement one milestone at a time; M0 (this scaffold) is done.

Rules specific to this target:

- Presentation, state orchestration, and user interaction only (FR4-002). All processing belongs in `AISidecarCore`; anything two features share and any non-presentation logic moves there too.
- Design tokens live in `DesignSystem/Theme.swift` and come from design doc Section 3 — never hardcode palette hex values in views.
- Option controls map to Core enums (`AnalysisMode`, `ExistingPolicy`, `GPSContextMode`, `XMPPairScope`) — do not invent option values (FR4-044).
- No sample/placeholder data in shipped screens (FR4-045).
- Shells (`Shells/`) are chrome only; feature views and state live in `Features/` and are embedded by both shells so switching shells never loses state (FR4-041).
