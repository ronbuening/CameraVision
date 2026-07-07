# Packaging Plan — Single Distributable Application

Version: 0.1
Date: 2026-07-06
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
    │   ├── AISidecarCore_AISidecarCore.bundle   SwiftPM resource bundle (prompts, schemas, vocabulary)
    │   ├── Assets.car, app icon, etc.
    │   └── (GUI-only resources)
    ├── Info.plist
    └── embedded.provisionprofile        (not needed for Developer ID)
```

Notes:
- `AISidecarCore` is a static SwiftPM library; both executables link it. That duplicates ~ a few MB of code in exchange for zero dylib/rpath complexity — acceptable. Only revisit (dynamic framework in `Contents/Frameworks`) if bundle size becomes a real complaint.
- The SwiftPM resource bundle must be locatable by **both** executables. `Bundle.module` works per-target; verify the CLI built via `swift build` finds its copied resource bundle when relocated into `Contents/Helpers/` (SwiftPM places `AISidecarCore_AISidecarCore.bundle` beside the executable — copy it into `Helpers/` too, or teach the app's build phase to place one copy where both lookups resolve). This is the single most likely packaging bug; test it first (WI-2).

## 3. Work Items

**WI-1 — Release build script (`Scripts/build-release.sh`).**
Inputs: version string. Steps:
1. `swift build -c release --product aisidecar` (arm64 + x86_64 via `--arch` flags, `lipo` into a universal binary — or arm64-only if the project decides to drop Intel; make it a flag).
2. `xcodebuild -scheme SidecarTagger -configuration Release archive`.
3. Copy the CLI (and its resource bundle if needed per WI-2) into `Contents/Helpers/`.
4. Codesign **inside-out**: helpers first, then the app, with `--options runtime` (hardened runtime) and the Developer ID Application identity.
5. `xcrun notarytool submit --wait`, then `xcrun stapler staple`.
6. Build a DMG (`hdiutil` or `create-dmg`), sign and staple the DMG too.
*Acceptance:* script runs on a clean machine profile from a tagged checkout; `spctl --assess --type execute` passes on the app; the CLI runs from inside the bundle on a machine that never had Xcode.

**WI-2 — Resource-bundle relocation test (do first).**
Write a small integration test/script: build the CLI, move the binary + resource bundle into a `Helpers/`-like layout, run `aisidecar analyze --help` and one prompt-registry-touching command (e.g. `benchmark --self-test`), confirm resources resolve. If `Bundle.module` fails when relocated, fix by adding a resource-resolution fallback in Core (search order: `Bundle.module` → main bundle → executable-adjacent) — a small, testable change.

**WI-3 — "Install Command Line Tool" action (GUI).**
Menu item that symlinks `Contents/Helpers/aisidecar` to `/usr/local/bin/aisidecar` (create dir if missing; on permission failure, show the manual `ln -s` / `PATH` instructions instead of escalating privileges). Detect and repair a stale symlink after the app moves.
*Acceptance:* fresh macOS user account → install action → `aisidecar --help` works in a new terminal.

**WI-4 — Info.plist and identity.**
Bundle id (e.g. `com.ronbuening.sidecartagger`), category `public.app-category.photography`, minimum system version 15.0, `NSHumanReadableCopyright`, and — important for the GUI — `LSApplicationCategoryType` and a proper app icon. No camera/mic/photo-library usage descriptions are needed (the app reads files, not the Photos library); add `NSPhotoLibraryUsageDescription` only if a Photos importer is ever built.

**WI-5 — First-run / dependency experience.** See Section 5; ship it in the same release as WI-1.

**WI-6 — Config and cache path policy.**
Keep the existing shared paths so CLI and GUI see the same world:
- Config: `~/Library/Application Support/aisidecar/config.json` (existing precedence chain unchanged).
- Derivative cache: `~/Library/Caches/aisidecar/derivatives` (shared with CLI — cache hits carry over).
- GUI-only state (SQLite DB, window state): `~/Library/Application Support/SidecarTagger/`.
Document this in the README and in the app's settings screen.

**WI-7 — Release checklist doc (`agent_docs/release-checklist.md`).**
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
