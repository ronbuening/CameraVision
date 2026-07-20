# Capture One Color-Label Urgency Mapping

Date recorded: 2026-07-16
Capture One version: 16.8.4

## Scope

This note records the color-label metadata written by Capture One 16.8.4 in the sample sidecars under
`agent_docs/XMP_Samples/CaptureOne_ColorLabels/`. Each supplied sidecar contains matching
`xmp:Label` and `photoshop:Urgency` child elements.

## Observed Mapping

| Capture One color tag | `xmp:Label` | `photoshop:Urgency` | Sample |
|---|---|---:|---|
| Red | `Red` | 1 | `260716_FilmSeminar3864.xmp` |
| Orange | `Orange` | 6 | `260716_FilmSeminar3865.xmp` |
| Yellow | `Yellow` | 7 | `260716_FilmSeminar3866.xmp` |
| Green | `Green` | 2 | `260716_FilmSeminar3867.xmp` |
| Blue | `Blue` | 3 | `260716_FilmSeminar3869.xmp` |
| Pink | `Pink` | 4 | `260716_FilmSeminar3870.xmp` |
| Purple | `Purple` | 5 | `260716_FilmSeminar3871.xmp` |

No `None` sample was supplied. The Phase-4 defaults do not map any quality tier to `None`, so this does not block
the required defaults: `reject` maps through Red to urgency `1`, and `excellent` maps through Green to urgency `2`.
An absent quality label produces no `photoshop:Urgency` write.

## Boundary

This capture establishes what Capture One wrote; it is not the Phase-5 application read-back test for sidecars
written by CameraVision. That compatibility evidence remains a separate manual stage.
