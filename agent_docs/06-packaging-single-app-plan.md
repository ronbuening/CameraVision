# Packaging — Single Distributable Application

Version: 0.3
Date: 2026-07-08 (as-built revision; original plan 2026-07-06, status pass 2026-07-07)
Audience: junior engineer or Sonnet-level coding agent.

The app ships as **one artifact** — `CupricAspect.app` — containing the GUI, the `aisidecar` CLI, and all resources (prompts, schemas, the 5.8 MB default vocabulary), delivered as a DMG. Ollama remains an external dependency handled by a first-run experience, not by bundling.

**Status ledger.** Done and as-built below: build script (WI-1, minus Developer ID signing), relocation-safe resources (WI-2), Info.plist/identity (WI-4), first-run guidance (WI-5, B0-3), path policy (WI-6), version single-sourcing (§6). Remaining work and its owners:

- **Developer ID signing / notarization / stapling** — the only pre-tag packaging work; runs as plan 08 §1.1 step 3, using the §4 runbook below.
- **Release checklist (`agent_docs/release-checklist.md`)** — written during the first beta-tag run (plan 08 §1.1 step 3), then extended by roadmap 09 F4-R4.
- **CLI install action (WI-3), CI, Sparkle auto-update** — owned by roadmap `agent_docs/09-post-m11-feature-roadmap.md` F4 (F4-R1, F4-R3, F4-R2 respectively). Their requirements live there now, not here.

## 1. Decisions (with rationale)

**D1 — Distribution channel: Developer ID + notarization, outside the Mac App Store.**
The app writes sidecar files next to user photos across arbitrary folders and ships an embedded CLI meant to be run from a terminal. Both are painful under App Store review and full sandboxing. Revisit MAS after the MVP proves out.

**D2 — App Sandbox: OFF for the MVP; Hardened Runtime: ON.**
Hardened runtime is required for notarization and costs nothing here (no JIT, no unsigned memory). Sandboxing would work for the GUI itself (`files.user-selected.read-write` + security-scoped bookmarks + `network.client` for localhost Ollama) but complicates persistent multi-folder access and does not extend to the embedded CLI when a user runs it directly. If MAS is pursued later, sandboxing becomes its own milestone.

**D3 — CLI ships inside the app bundle** at `Contents/Helpers/aisidecar`. A user-invokable "Install Command Line Tool" action (roadmap F4-R1) will symlink it into `/usr/local/bin`; until then the CLI is reachable only inside the bundle. One bundle, one signature, one notarization — no separate CLI installer.

**D4 — Ollama is not bundled.** It has its own installer, updater, and model storage (tens of GB). Bundling would bloat the app and create licensing/update burdens. The app detects and guides instead (§5).

**D5 — One version number for everything.** App `CFBundleShortVersionString`, CLI `--version`, and the `AISidecarCore` version constant come from a single source (§6, invariant 19).

## 2. Bundle Layout (as built by `Scripts/build-release.sh`)

```
CupricAspect.app/
└── Contents/
    ├── MacOS/CupricAspect                       GUI executable
    ├── Helpers/aisidecar                        CLI executable (release build; --no-cli to skip)
    ├── Resources/
    │   ├── CameraVision_AISidecarCore.bundle    ONE shared SwiftPM resource bundle (prompts, schemas, vocabulary)
    │   └── AppIcon.icns
    └── Info.plist                               from Scripts/packaging/Info.plist.template
```

- `AISidecarCore` is a static SwiftPM library; both executables link it. That duplicates a few MB of code in exchange for zero dylib/rpath complexity — acceptable. Only revisit (dynamic framework in `Contents/Frameworks`) if bundle size becomes a real complaint.
- The SwiftPM resource bundle is flat, so codesign rejects a second copy under `Helpers/` — the app carries **one** copy in `Contents/Resources`, shared by both executables through `AISidecarResourceBundle` (invariant 18; search order: app `Contents/Resources` → executable-adjacent → `../Resources` → `Bundle.module`). `Bundle.module`'s generated accessor checks only the main-bundle root and the absolute build-machine path, which is exactly the relocation bug WI-2 predicted. `Scripts/wi2-relocation-check.sh` proves both relocated layouts with the build tree hidden, plus a negative control.
- Identity: bundle id `com.ronbuening.cupricaspect`, category `public.app-category.photography`, minimum system 15.0. No camera/mic/photo-library usage descriptions are needed (the app reads files, not the Photos library); add `NSPhotoLibraryUsageDescription` only if a Photos importer is ever built.

## 3. Build Script (as built)

`Scripts/build-release.sh`: `swift build -c release` for both products (`--universal` for arm64+x86_64 via `--arch`); assembles `dist/CupricAspect.app` — `Info.plist` from the template with `CFBundleShortVersionString` injected from `AISidecarVersion` and cross-checked against the embedded CLI's `--version`, committed `AppIcon.icns` (regenerate with `Scripts/generate-app-icon.sh`), embedded CLI by default, one shared resource bundle — then packs the DMG (`--no-dmg` to skip). Codesign is inside-out with `--options runtime`; ad-hoc by default, `--sign <identity>` for Developer ID.

**Remaining acceptance (plan 08 §1.1 step 3):** Developer ID sign + `xcrun notarytool submit --wait` + `stapler staple`; `spctl --assess --type execute` passes on the app; script run from a tagged checkout on a clean machine profile.

## 4. Signing & Notarization Runbook

- Requires an Apple Developer Program membership; create a **Developer ID Application** certificate.
- Sign order matters: `codesign` the CLI helper first, then the `.app`; both with `--timestamp --options runtime`. Any file added after signing invalidates the seal — the DMG step must come last.
- Store notarization credentials in the keychain (`notarytool store-credentials`); never in the repo.
- No entitlements file is needed for the MVP (no sandbox, no restricted capabilities). Localhost HTTP to Ollama needs nothing extra outside the sandbox. `NSAllowsArbitraryLoads` is also unnecessary: `http://localhost` is exempt from ATS.

## 5. Ollama Dependency Handling (as built, B0-3: `RuntimeGuidanceModel`)

State machine on launch and in Settings:
1. **Reachable?** `GET {endpoint}/api/version` (the same call `OllamaVisionRunner.prepare()` uses). Unreachable → guidance panel: download link (https://ollama.com/download), "launch the Ollama app", re-check button.
2. **Model present?** Query tags; if the configured/default model is missing, offer the `ollama pull <tag>` command with a copy button (do not shell out to run it — NFR4-009's spirit: no external process orchestration).
3. **Vision-capable?** Reuse the existing capability check; explain and suggest known-good tags if it fails.

All analysis entry points stay disabled (with the reason shown) until checks pass; everything else (review, normalization inspection, export of already-analyzed data) works offline by design.

## 6. Version Single-Sourcing (as built, invariant 19)

`AISidecarVersion.current` (Core) feeds CLI `--version` (ArgumentParser `CommandConfiguration(version:)`), the GUI About/Settings cards, and the build script's `CFBundleShortVersionString` injection, which is cross-checked at assembly. Sidecar/report provenance records engine/recipe schema versions — distinct from the product version; never conflate them.

## 7. Config and Cache Path Policy (as built)

CLI and GUI see the same world:
- Config: `~/Library/Application Support/aisidecar/config.json` (existing precedence chain unchanged; the GUI Settings sheet writes through to it).
- Derivative cache: `~/Library/Caches/aisidecar/derivatives` (shared with the CLI — cache hits carry over).
- GUI-only state: `~/Library/Application Support/CupricAspect/` — recovery session, per-run artifacts, diagnostic log in `logs/` (B0-4). Nothing is ever written inside the app bundle — it is read-only and code-signed (invariant 20).

## 8. Explicitly Out of Scope

- Bundling Ollama or any model weights.
- Mac App Store submission and App Sandbox (revisit post-MVP; would need security-scoped bookmark plumbing and a sandbox-safe CLI story).
- Windows/Linux anything (project is macOS-only per invariant 11).
- CLI install action, CI, and Sparkle auto-update are in scope for the project but owned by roadmap 09 F4, not this document.
