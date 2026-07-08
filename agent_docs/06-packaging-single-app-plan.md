# Packaging Plan — Single Distributable Application

Version: 0.2
Date: 2026-07-07 (status pass after B0-1; original 2026-07-06)

> **Status (2026-07-07, B0-1):** WI-2 ✅, WI-1 ✅ (except Developer ID signing/notarization — the script ad-hoc signs by default and takes `--sign <identity>`; `spctl` acceptance pending the certificate), WI-4 ✅, WI-5 ✅ (B0-3 `RuntimeGuidanceModel`), WI-6 ✅, Section 6 version single-sourcing ✅ (`AISidecarVersion.current` = 0.1.0-beta.1). Outstanding: Developer ID signing/notarization/stapling, WI-3 (post-beta), WI-7 (`agent_docs/release-checklist.md` does not exist yet), Section 7 CI. Per-item notes inline below.
Depends on: `agent_docs/phase-4-gui-implementation-plan.md` (app target exists after its M0)
Audience: junior engineer or Sonnet-level coding agent.

Goal: ship **one artifact** — `CupricAspect.app` — that contains the GUI, the `aisidecar` CLI, and all resources (prompts, schemas, the 5.8 MB default vocabulary), signed and notarized, delivered as a DMG. Ollama remains an external dependency handled by a first-run experience, not by bundling.

> **Naming and build-system update (2026-07-06, requirements v0.4 / phase-4 plan v0.2):** the app is named **CupricAspect** — read every `SidecarTagger` below as `CupricAspect` (bundle id `com.ronbuening.cupricaspect`, GUI state dir `~/Library/Application Support/CupricAspect/`, WI-4 category unchanged). The GUI is a SwiftPM executable target, not an Xcode project, so WI-1 step 2 becomes: `swift build -c release --product CupricAspect`, then script-assemble the `.app` bundle (`Contents/MacOS/CupricAspect`, `Info.plist`, icon, resource bundles) before the existing codesign/notarize steps. WI-2's resource-bundle relocation test now covers the GUI executable too. This plan gets a full-text revision when packaging work starts.

## 1. Decisions (with rationale)

**D1 — Distribution channel: Developer ID + notarization, outside the Mac App Store.**
The app writes sidecar files next to user photos across arbitrary folders and ships an embedded CLI meant to be run from a terminal. Both are painful under App Store review and full sandboxing. Revisit MAS after the MVP proves out.

**D2 — App Sandbox: OFF for the MVP; Hardened Runtime: ON.**
Hardened runtime is required for notarization and costs nothing here (no JIT, no unsigned memory). Sandboxing would work for the GUI itself (`files.user-selected.read-write` + security-scoped bookmarks + `network.client` for localhost Ollama) but complicates persistent multi-folder access and does not extend to the embedded CLI when a user runs it directly. If MAS is pursued later, sandboxing becomes its own milestone.

**D3 — CLI ships inside the app bundle** at `Contents/Helpers/aisidecar`, with a user-invokable "Install Command Line Tool" menu action that symlinks it into `/usr/local/bin` (or prints the `PATH` line for `~/.zshrc` if not writable). One bundle, one signature, one notarization — no separate CLI installer.

**D4 — Ollama is not bundled.** It has its own installer, updater, and model storage (tens of GB). Bundling would bloat the app and create licensing/update burdens. The app detects and guides instead (Section 5).

**D5 — One version number for everything.** App `CFBundleShortVersionString`, CLI `--version`, and a `AISidecarCore` version constant come from a single source (Section 6).

## 2. Bundle Layout

```
SidecarTagger.app/
└── Contents/
    ├── MacOS/SidecarTagger              GUI executable
    ├── Helpers/aisidecar                CLI executable (release build)
    ├── Frameworks/                      (empty today — Core is statically linked into both)
    ├── Resources/
    │   ├── CameraVision_AISidecarCore.bundle    SwiftPM resource bundle (prompts, schemas, vocabulary)
    │   ├── Assets.car, app icon, etc.
    │   └── (GUI-only resources)
    ├── Info.plist
    └── embedded.provisionprofile        (not needed for Developer ID)
```

Notes:
- `AISidecarCore` is a static SwiftPM library; both executables link it. That duplicates ~ a few MB of code in exchange for zero dylib/rpath complexity — acceptable. Only revisit (dynamic framework in `Contents/Frameworks`) if bundle size becomes a real complaint.
- The SwiftPM resource bundle must be locatable by **both** executables. *As implemented (B0-1):* the SwiftPM resource bundle is flat, so codesign rejects a copy under `Helpers/` — the app carries **one** copy in `Contents/Resources`, shared by both executables through `AISidecarResourceBundle` (invariant 18). WI-2 confirmed this was indeed the most likely packaging bug: `Bundle.module`'s generated accessor checks only the main-bundle root and the absolute build-machine path.

## 3. Work Items

**WI-1 — Release build script (`Scripts/build-release.sh`).** *Status: implemented except Developer ID signing/notarization (steps 4–5 run with `--sign <identity>` once the certificate exists; ad-hoc signing otherwise).*
As implemented: `swift build -c release` for both products (`--universal` flag for arm64+x86_64 via `--arch`); script-assembles `dist/CupricAspect.app` — `Contents/MacOS/CupricAspect`, `Info.plist` from `Scripts/packaging/Info.plist.template` with `CFBundleShortVersionString` injected from `AISidecarVersion` and cross-checked against the embedded CLI's `--version`, committed `AppIcon.icns` (`Scripts/generate-app-icon.sh`), embedded CLI at `Contents/Helpers/aisidecar` by default (`--no-cli` to skip), one shared resource bundle in `Contents/Resources` — then packs the DMG (`--no-dmg` to skip). Codesign is inside-out with `--options runtime`.
*Remaining acceptance:* Developer ID sign + `xcrun notarytool submit --wait` + `stapler staple`; `spctl --assess --type execute` passes on the app; script run from a tagged checkout on a clean machine profile.

**WI-2 — Resource-bundle relocation test (do first).** *Status: done.*
`Bundle.module` does fail when relocated (its generated accessor checks only the main-bundle root and the absolute build-machine path). Fixed with `AISidecarResourceBundle` in Core — implemented search order: app `Contents/Resources` → executable-adjacent → `../Resources` (Helpers CLI) → `Bundle.module` (dev/test fallback). Prompts, schemas, and vocabulary all resolve through it (invariant 18). `Scripts/wi2-relocation-check.sh` proves both relocated layouts with the build tree hidden, plus a negative control.

**WI-3 — "Install Command Line Tool" action (GUI).** *Status: not implemented (post-beta by B0 decision; the CLI ships embedded at `Contents/Helpers/aisidecar` only).*
Menu item that symlinks `Contents/Helpers/aisidecar` to `/usr/local/bin/aisidecar` (create dir if missing; on permission failure, show the manual `ln -s` / `PATH` instructions instead of escalating privileges). Detect and repair a stale symlink after the app moves.
*Acceptance:* fresh macOS user account → install action → `aisidecar --help` works in a new terminal.

**WI-4 — Info.plist and identity.**
Bundle id (e.g. `com.ronbuening.sidecartagger`), category `public.app-category.photography`, minimum system version 15.0, `NSHumanReadableCopyright`, and — important for the GUI — `LSApplicationCategoryType` and a proper app icon. No camera/mic/photo-library usage descriptions are needed (the app reads files, not the Photos library); add `NSPhotoLibraryUsageDescription` only if a Photos importer is ever built.

**WI-4 status: done** — `Scripts/packaging/Info.plist.template` (bundle id `com.ronbuening.cupricaspect`, `public.app-category.photography`, minimum 15.0) plus the committed `AppIcon.icns`.

**WI-5 — First-run / dependency experience.** See Section 5; ship it in the same release as WI-1. *Status: done (B0-3) — `RuntimeGuidanceModel` implements the Section 5 state machine: one launch-time check + manual re-check, install/start guidance with a Download Ollama action, and a copyable `ollama pull <resolved tag>` starter command when no vision model exists.*

**WI-6 — Config and cache path policy.**
Keep the existing shared paths so CLI and GUI see the same world:
- Config: `~/Library/Application Support/aisidecar/config.json` (existing precedence chain unchanged).
- Derivative cache: `~/Library/Caches/aisidecar/derivatives` (shared with CLI — cache hits carry over).
- GUI-only state (window state; the SQLite DB when the experimental database mode is enabled — requirements FR4-046/047): `~/Library/Application Support/CupricAspect/`. Nothing is ever written inside the app bundle — it is read-only and code-signed.
Document this in the README and in the app's settings screen. *Status: done — paths confirmed as implemented; the GUI diagnostic log lives at `~/Library/Application Support/CupricAspect/logs/` (B0-4).*

**WI-7 — Release checklist doc (`agent_docs/release-checklist.md`).** *Status: outstanding — the doc does not exist yet.*
Tag → build script → smoke checks (app launch, CLI `--help`, one analyze run against fixtures with Ollama, one export verified in Lightroom/C1 per existing release-evidence pattern) → notarize → staple → DMG → GitHub release with checksums.

## 4. Signing & Notarization Details

- Requires an Apple Developer Program membership; create a **Developer ID Application** certificate.
- Sign order matters: `codesign` the CLI helper first, then the `.app`; both with `--timestamp --options runtime`. Any file added after signing invalidates the seal — the DMG step must come last.
- Store notarization credentials in the keychain (`notarytool store-credentials`); never in the repo.
- No entitlements file is needed for the MVP (no sandbox, no restricted capabilities). Localhost HTTP to Ollama needs nothing extra outside the sandbox. `NSAllowsArbitraryLoads` is also unnecessary: `http://localhost` is exempt from ATS.

## 5. Ollama Dependency Handling (first-run experience)

State machine on launch and in Settings:
1. **Reachable?** `GET {endpoint}/api/version` (the same call `OllamaVisionRunner.prepare()` uses). Unreachable → guidance panel: download link (https://ollama.com/download), "launch the Ollama app", re-check button.
2. **Model present?** Query tags; if the configured/default model is missing, offer the `ollama pull <tag>` command with a copy button (do not shell out to run it — keep NFR4-009's spirit: no external process orchestration).
3. **Vision-capable?** Reuse the existing capability check; explain and suggest known-good tags if it fails.
All analysis entry points stay disabled (with the reason shown) until checks pass; everything else (review, vocabulary, export of already-analyzed data) works offline by design.

## 6. Version Single-Sourcing

- Add `AISidecarVersion.swift` in Core: `public enum AISidecarVersion { public static let current = "X.Y.Z" }`.
- CLI `--version` prints it (ArgumentParser `CommandConfiguration(version:)`).
- The build script injects the same string into the app's `MARKETING_VERSION` (or asserts they match and fails the build otherwise).
- Sidecar/report provenance already records engine/recipe versions; do not conflate those schema versions with the product version.

## 7. CI (optional but recommended once WI-1 lands)

GitHub Actions on macOS runner: `swift test` + `xcodebuild test` on every PR; the release workflow runs `Scripts/build-release.sh` on tags (signing/notarization secrets via repo secrets). Keep unit tests offline (AGENTS.md rule) so CI needs no Ollama.

## 8. Explicitly Out of Scope

- Bundling Ollama or any model weights.
- Mac App Store submission and App Sandbox (revisit post-MVP; would need security-scoped bookmark plumbing and a sandbox-safe CLI story).
- Sparkle/auto-update (a follow-up; DMG + GitHub releases first).
- Windows/Linux anything (project is macOS-only per AGENTS.md).
