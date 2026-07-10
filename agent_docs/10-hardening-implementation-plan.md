# Hardening Implementation Plan — R1–R4 Execution Detail

Version: 0.1
Date: 2026-07-08
Implements: `agent_docs/08-post-review-hardening-plan.md` v1.0 (findings, acceptance criteria, and the §1.1 execution order — that section remains the single authoritative order; this document adds execution-level detail only)
Audience: junior engineer or Sonnet-level coding agent executing one work item at a time.

Each work item below carries: the goal, the verified current code, the concrete change (with proposed code), test skeletons, acceptance checkboxes, and a suggested commit subject. Plan 08 remains the source of truth for *what* and *why*; where this document and plan 08 disagree on scope or acceptance, plan 08 wins.

## 0. Ground rules (read first)

1. Read `agent_docs/invariants.md` before starting — all rules bind every item. The ones this plan trips over most: 1 (analyze never touches XMP), 3 (GPS never becomes keywords), 7 (stable raw strings — error codes and exit codes are load-bearing; add, never rename), 10 (exact-first vocabulary matching), 12 (tests offline/deterministic), 13 (GUI is presentation/state orchestration only), 16 (behavior changes ship with tests), 17 (one work item at a time).
2. **Code snippets in this plan are guidance, not gospel.** They were verified against source on 2026-07-08; line numbers drift as earlier items land. Re-read the cited file before editing. If the actual code no longer matches an item's "Current behavior" block, stop and re-derive the fix from the item's Goal + plan 08's finding — do not force the snippet in.
3. One item per branch/commit sequence; `swift test` green before and after every item; commit at each passing breakpoint, docs and code in separate commits. If XCTest is missing, prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
4. Golden-fixture diffs (`GoldenSidecarTests`, report/summary tests) are deliberate decisions: update fixtures explicitly and say so in the PR, never regenerate blindly.
5. Items marked **STOP: maintainer decision** present options with a recommendation; get Ron's sign-off before implementing that item (the rest of the wave can proceed).
6. Work strictly in plan 08 §1.1 order: R1 → exit gate → manual release step → R2 → R3 → R4 (R3/R4 may swap wholesale, never interleave). Efficiency-plan P2/P3 execute inside R4-6; the rest of plan 05 runs after R4 per §1.1 step 7.

## 1. Milestone sequence and gates

| Step | Gate | Detail |
|---|---|---|
| R1-1 → R1-14 | gates the `v0.1.0-beta.1` tag | §Milestone R1 below |
| R1 exit gate | manual + `swift test` | end of R1 section |
| B0-5 + signing + tag | manual (Ron) | §2 below |
| R2-1 → R2-7 | first post-beta code milestone | §Milestone R2 below |
| R3-1 → R3-11 | after R2 | §Milestone R3 below |
| R4-1 → R4-6 (+P2/P3) | after R3 | §Milestone R4 below |

## 2. Manual release step — B0-5, signing, tag (Ron)

Not agent work, but recorded here so the whole sequence lives in one document. Prerequisite: R1 exit gate passed. While executing this step, capture the exact sequence as `agent_docs/release-checklist.md` (plan 08 §1.1 step 3).

1. **B0-5 evidence.** From the GUI, write real XMP for a small real batch; import in Lightroom Classic and Capture One; record results following the pattern in `agent_docs/release-evidence/` (new file, current writer recipe). Record Phase 1 M9 calibration evidence or write the explicit deferral note (see `agent_docs/cli-implementation-notes.md`, "Open item").
2. **Developer ID signing** (runbook: `agent_docs/06-packaging-single-app-plan.md` §4). One-time: create the Developer ID Application certificate; `xcrun notarytool store-credentials` (keychain, never the repo). Then from a tagged checkout:

   ```bash
   Scripts/build-release.sh --sign "Developer ID Application: <name> (<team>)"
   xcrun notarytool submit dist/CupricAspect-*.dmg --keychain-profile <profile> --wait
   xcrun stapler staple dist/CupricAspect.app   # and the DMG
   spctl --assess --type execute dist/CupricAspect.app && echo OK
   ```

   Sign order is handled by the script (CLI helper first, inside-out, `--timestamp --options runtime`); the DMG is packed last — anything added after signing invalidates the seal.
3. **Tag and hand out.** `git tag v0.1.0-beta.1 && git push --tags`; distribute the stapled DMG. Write `agent_docs/release-checklist.md` from what you actually did.

## Milestone R1 — Beta ship-blockers

R1 is the fourteen-item wave that gates the `v0.1.0-beta.1` tag (plan 08 §1.1/§2): four GUI dead-states or silent failures a beta tester will hit in the first hour, one Core crash bug, two review-semantics bugs, three Options/write alpha fixes (R1-8 per-run model override, R1-9 visible XMP conflict policy, R1-10 opt-in post-write cleanup), and four further alpha fixes (R1-11 Settings default for concurrency, R1-12 Settings default for XMP treatment, R1-13 relabel the program's `.ai.json` sidecar control, R1-14 seconds-per-image rate under skips). Entry criteria: `swift test` green at the current baseline. Execute **in order R1-1 → R1-14**: R1-1, R1-2, R1-4, and R1-5 all edit `Sources/CupricAspectApp/Shells/WizardShellView.swift`, and R1-2's recovery landing depends on R1-1's `WizardNavigation` helper. R1-3 (Core, `JSONLWriter`) is independent and may land at any point inside the wave. R1-8 and R1-9 both edit `Features/Run/Step3OptionsView.swift` and in that order (R1-8 → R1-9) keep the Options-view edits in a single line — R1-8 also touches `AnalysisOptions`/`AnalysisRunModel`, R1-9 also touches `ExportModel`. R1-10 follows R1-9 (both touch `ExportModel`) and adds `Features/Export/ChangePlanSheet.swift`. R1-11 and R1-12 both add a control to the Settings `CONFIGURATION` section (`Features/Settings/SettingsSheet.swift`) plus a write-through to `Features/Settings/SettingsModel.swift`; do R1-11 → R1-12 to keep the Settings-view edits in one line (R1-12 also adds one seeding line to `AnalysisOptions.loadResolvedDefaults`). R1-13 follows R1-12 (it also edits `SettingsSheet.swift`, plus `Step3OptionsView.swift`). R1-14 (`AnalysisRunModel.swift` rate math) is independent and may land anywhere inside the wave. All items respect invariant 13 (GUI is presentation/state only — no processing moves out of Core) and invariant 16 (each behavior change lands with tests).

### R1-1 — Wizard "Back" from Step 5 lands on a dead Working screen; re-run silently discards analysis (HIGH)

**Goal.** Back from Step 5 after a completed (or never-started) run lands on Step 3 with a live primary button; Step 4 is unreachable without an in-flight run. Returning to Options is non-destructive; re-running from Step 3 when a completed analysis/review (or a built normalization session) already exists asks for confirmation before it discards that data. Applies to both the analyze/write flow and the normalize flow (Step 5 → Step 3 is one code path).

**Files.**
- `Sources/CupricAspectApp/Shells/WizardShellView.swift:341` (`backEnabled`), `:429-431` (Back button `step -= 1`), `:247-248` (`Step4WorkingView` rendered unconditionally for `case 4`), `:395-425` (`primaryAction()` — `case 3` re-runs via `runModel.start(...)`)
- New: `Sources/CupricAspectApp/Shells/WizardNavigation.swift`
- `Sources/CupricAspectApp/Features/Run/AnalysisRunModel.swift:171-175` (`cancel()` guards `phase == .running` — verified)

**Current behavior (verified 2026-07-08).** `backEnabled` allows Back on Step 5; the button blindly decrements to Step 4, which renders the Working view even though `runModel.phase` is `.finished` (or `.idle` on the recovery path). The `onChange` transitions that exit Step 4 have already fired; `cancel()` no-ops, the primary is disabled (`case 4: false`, `:349`), Back is disabled (`step != 4`). Only relaunch escapes.

```swift
// WizardShellView.swift:341
private var backEnabled: Bool { step > 1 && step != 4 }
// WizardShellView.swift:429-431
Button {
    if backEnabled { step -= 1 }
}
```

**Change.**
1. Add `Sources/CupricAspectApp/Shells/WizardNavigation.swift` — a pure, stateless decision helper (presentation logic only; invariant 13 safe):

```swift
/// Pure wizard step-graph decisions (R1-1), kept out of the view so they
/// are unit-testable. Step 4 (Working) is only a valid destination while
/// a run is in flight; Back from Step 5 skips it otherwise.
enum WizardNavigation {
    static func isInFlight(_ phase: AnalysisRunModel.Phase) -> Bool {
        phase == .running || phase == .cancelling
    }

    /// Where Back lands from `step`; nil means Back is unavailable.
    static func backTarget(from step: Int, phase: AnalysisRunModel.Phase) -> Int? {
        switch step {
        case ...1: nil
        case 4: nil                          // Working: Cancel, never Back
        case 5 where !isInFlight(phase): 3   // skip the dead Working screen
        default: step - 1
        }
    }

    /// Whether re-running from Step 3 would discard already-produced data
    /// (a completed run's review verdicts, or a built normalization session)
    /// and therefore must confirm first. A fresh Step 3 never prompts.
    static func needsRerunConfirmation(phase: AnalysisRunModel.Phase, hasReview: Bool) -> Bool {
        switch phase {
        case .finished, .cancelling: true
        default: hasReview   // covers the recovery/imported-session path where phase is .idle
        }
    }
}
```

2. In `WizardShellView`, replace the decrement and the enable predicate:

```swift
private var backEnabled: Bool {
    WizardNavigation.backTarget(from: step, phase: runModel.phase) != nil
}
// Back button action:
if let target = WizardNavigation.backTarget(from: step, phase: runModel.phase) {
    step = target
}
```

3. No change to the render switch (`content`) — Step 4 stays render-if-`step == 4`, but no navigation path reaches it without a live run.

4. Guard the destructive re-run. In `primaryAction()` `case 3` (the analyze/write/normalize re-run branch), when `WizardNavigation.needsRerunConfirmation(phase:hasReview:)` is true, set a `@State private var confirmRerun = false` instead of starting the run; the confirmation's primary calls the same start logic. `hasReview` derives from the model already in the shell (e.g. `!reviewModel.assetRows.isEmpty` / a non-nil normalization session), never from view-only state. Wire a `.confirmationDialog` on the shell:

```swift
// @State private var confirmRerun = false
.confirmationDialog(
    "Re-run the analysis?",
    isPresented: $confirmRerun,
    titleVisibility: .visible
) {
    Button("Re-run", role: .destructive) { startRun() }   // the extracted case-3 start
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This discards the current results and \(reviewModel.decisionCount) review decisions.")
}
```

Extract the `case 3` non-apply body (the `runModel.start(...)` + `step = 4`) into a `startRun()` method so both the guarded path and the confirmation button call it. The apply-session `case 3` branch (`selectedAction == .apply`) is unaffected — it never analyzes. Use the real count expression the review model exposes; if none exists, add a trivial `decisionCount` derived from existing verdict state (presentation-only, invariant 13 safe).

**Tests.** `Tests/CupricAspectAppTests/WizardNavigationTests.swift` (new file):

```swift
import XCTest
@testable import CupricAspectApp

/// R1-1: the Back step graph — Step 4 is only valid while a run is in flight.
@MainActor
final class WizardNavigationTests: XCTestCase {
    func testBackFromStep5SkipsWorkingWhenRunIsNotInFlight() {
        XCTAssertEqual(WizardNavigation.backTarget(from: 5, phase: .finished(RunOutcome())), 3)
        XCTAssertEqual(WizardNavigation.backTarget(from: 5, phase: .idle), 3)
        XCTAssertEqual(WizardNavigation.backTarget(from: 5, phase: .failed(message: "x")), 3)
    }

    func testBackFromStep5DuringLiveRunStaysConventional() {
        XCTAssertEqual(WizardNavigation.backTarget(from: 5, phase: .running), 4)
        XCTAssertEqual(WizardNavigation.backTarget(from: 5, phase: .cancelling), 4)
    }

    func testBackIsUnavailableOnStep1AndStep4AndDecrementsElsewhere() {
        XCTAssertNil(WizardNavigation.backTarget(from: 1, phase: .idle))
        XCTAssertNil(WizardNavigation.backTarget(from: 4, phase: .running))
        XCTAssertNil(WizardNavigation.backTarget(from: 4, phase: .finished(RunOutcome())))
        XCTAssertEqual(WizardNavigation.backTarget(from: 3, phase: .idle), 2)
        XCTAssertEqual(WizardNavigation.backTarget(from: 2, phase: .idle), 1)
    }

    func testRerunConfirmationRequiredOnlyWhenDataWouldBeLost() {
        // Completed run → prompt regardless of review contents.
        XCTAssertTrue(WizardNavigation.needsRerunConfirmation(phase: .finished(RunOutcome()), hasReview: false))
        // Recovery/imported path: phase .idle but a restored review present → prompt.
        XCTAssertTrue(WizardNavigation.needsRerunConfirmation(phase: .idle, hasReview: true))
        // Fresh Step 3, no prior run and nothing restored → no prompt.
        XCTAssertFalse(WizardNavigation.needsRerunConfirmation(phase: .idle, hasReview: false))
    }
}
```

(Adjust `RunOutcome()` to the real initializer; the phase's payload is irrelevant to the decision.)

**Acceptance.**
- [ ] From a completed analyze, write, and normalize flow: press Back on Step 5 → land on Step 3 with options intact and the primary button enabled; navigating Step 5 → 3 → 5 without re-running shows the same review (data retained).
- [ ] Pressing Start again on Step 3 with a completed run/review prompts "Re-run the analysis? This discards the current results and N review decisions." — Cancel keeps the data; Re-run proceeds. A first Start with no prior run does not prompt.
- [ ] No reachable state renders Step 4 without a live run.
- [ ] `WizardNavigationTests` cover `(5, .finished) → 3`, `(5, .idle) → 3`, `(3, *) → 2`, Step-4 in-flight unchanged, and the `needsRerunConfirmation` cases above.

**Commit.** `GUI R1-1: Back from Step 5 skips the dead Working step and re-run confirms before discarding, via testable WizardNavigation`

### R1-2 — Recovery launch can't export and its primary action deletes the recovery (HIGH)

**Goal.** After kill-and-relaunch, Restore yields a review that can actually write XMP, and "Done" asks before destroying restored-but-unsaved verdicts.

**Files.**
- `Sources/CupricAspectApp/Shells/WizardShellView.swift:64-68` (recovery launch → `selectedAction = .analyze`, `step = 5`), `:280-293` (`startExport` silent guards), `:355-363` (`step5WriteAvailable`), `:413-421` ("Done" branch calling `completeCleanly()`)
- `Sources/CupricAspectApp/Features/Review/ReviewModel.swift:198-204` (`completeCleanly()` deletes `review-recovery.json` and clears verdicts), `:287-289` (`restoreFromRecovery()`)
- `Sources/CupricAspectApp/Features/Import/FolderImportModel.swift:72-77` (`chooseSource`)
- `Sources/AISidecarCore/Normalization/NormalizationSessionDocument.swift:72` (`public var sourceRoot: String?` — the recovery document already carries the source context)

**Current behavior (verified 2026-07-08).** All plan-08 claims hold. On recovery launch the shell jumps to Step 5 as `.analyze` with no imported folder; `step5WriteAvailable` returns `false` for anything but `.write`/`.normalize`, `startExport()` returns silently on nil `sourceFolder`, and the prominent Done deletes the recovery with only the 12-pt footer hint (`:391`, "Done clears the review") as warning. **Discrepancy (minor, line refs only):** the plan cites `:411-421` for the Done branch; the Done case is `:413-421` (`:411-412` is the write case). `step5WriteAvailable`'s body is `:356-363` (`:355` is its doc comment).

**Change.** One concrete design (option 1+2 from plan 08; option 3 not taken):

1. **Recovery launch selects `.write`** (the review flow), not `.analyze` — `WizardShellView.task`:

```swift
// FR4-046a: offer recovery of an interrupted review on launch.
if reviewModel.recoveryAvailable {
    selectedAction = .write
    step = 5
}
```

2. **Restore rehydrates the import context.** The recovery document is a full session and already records `sourceRoot` (and `outputDir`). `ReviewModel.buildSession` must set it — verify `NormalizePipeline.runSessionOnly` stamps `configuration.sourceRoot` into the session (it does; `ReviewModel.buildSession:143` sets `configuration.sourceRoot`). In the shell, react to a session appearing while no folder is imported:

```swift
.onChange(of: reviewModel.session?.sessionID) { _, _ in
    // R1-2: a restored/imported review re-establishes its source folder so
    // step5WriteAvailable and startExport work (FR4-046a).
    guard importModel.sourceFolder == nil,
          let root = reviewModel.session?.sourceRoot,
          FileManager.default.fileExists(atPath: root) else { return }
    importModel.chooseSource(URL(fileURLWithPath: root, isDirectory: true))
}
```

   If the folder no longer exists, the review stays visible and save-session still works; Write remains unavailable (correct — there is nothing to write against).

3. **Done confirms before discarding.** Add the decision to `WizardNavigation` (testable); in `primaryAction()` the Done branch shows a `confirmationDialog` (new `@State private var showDiscardConfirm`) when it returns true, else calls the existing reset block (extracted as `finishCleanly()`):

```swift
// WizardNavigation.swift
/// R1-2: Done is destructive when a live review with an on-disk recovery
/// would be deleted without having been exported or saved.
static func doneNeedsConfirmation(hasSession: Bool, recoveryOnDisk: Bool, exported: Bool) -> Bool {
    hasSession && recoveryOnDisk && !exported
}
// Shell call: hasSession: reviewModel.session != nil,
//   recoveryOnDisk: reviewModel.recoveryAvailable,
//   exported: exportModel.phase == .written
```

   Dialog message: `"Discard the restored review? \(reviewModel.verdicts.count) decisions will be lost."` Buttons: **Save session first…** (reuses Step 5's `NSSavePanel` routine — extract `Step5ReviewView.saveSession()` into a shared helper — then `finishCleanly()` on success), **Discard review** (destructive role → `finishCleanly()`), **Cancel**.

4. **Maintainer sign-off needed:** this predicate confirms on *every* unexported Done (any autosaved review), not only recovery launches — safer, but one extra click in the normal path. If Ron prefers recovery-launch-only confirmation, feed a `restoredFromRecovery` flag (set in `restoreFromRecovery()`, cleared in `completeCleanly()`) instead of `recoveryAvailable`.

**Tests.** Extend `Tests/CupricAspectAppTests/ReviewModelTests.swift` (round-trip source context) and `Tests/CupricAspectAppTests/WizardNavigationTests.swift` (confirmation decision):

```swift
// ReviewModelTests.swift
@MainActor
func testRecoveryRoundTripPreservesSourceRootForExport() throws {
    let model = makeModel(decisionLimit: 1)
    model.adopt(session: try makeBaseSession(terms: ["bird"]))
    let chip = try XCTUnwrap(model.assetRows.first?.chips.first)
    model.setVerdict(.rejected, for: chip.decisionID)   // triggers autosave

    let relaunched = makeModel()
    try relaunched.restoreFromRecovery()
    XCTAssertEqual(relaunched.session?.sourceRoot,
                   root.appendingPathComponent("source").path,
                   "restored session must carry the source folder for startExport")
}

// WizardNavigationTests.swift
func testDoneConfirmsOnlyForUnsavedRecoverableReviews() {
    XCTAssertTrue(WizardNavigation.doneNeedsConfirmation(hasSession: true, recoveryOnDisk: true, exported: false))
    XCTAssertFalse(WizardNavigation.doneNeedsConfirmation(hasSession: true, recoveryOnDisk: true, exported: true))
    XCTAssertFalse(WizardNavigation.doneNeedsConfirmation(hasSession: false, recoveryOnDisk: true, exported: false))
}
```

**Acceptance.**
- [ ] Kill the app mid-review (the `m8-kill-relaunch-check.sh` pattern, or manually) → relaunch → restore → the review is visible **and** "Write XMP" is available and works end-to-end.
- [ ] Pressing Done with unsaved restored verdicts asks before deleting.
- [ ] `FolderImportReopenTests`-style unit tests cover the restored source/action; a `ReviewModel`/shell test covers the confirm-before-discard decision.
- [ ] Added: restore with a since-deleted source folder does not crash; save-session still works.

**Commit.** `GUI R1-2: recovery restore rehydrates source context; Done confirms before discarding`

### R1-3 — Progress-log append crashes the process on I/O failure (HIGH, Core)

**Goal.** A failed JSONL append throws a structured `SidecarError` instead of killing the process.

**Files.**
- `Sources/AISidecarCore/Reporting/JSONLWriter.swift:37-38`

**Current behavior (verified 2026-07-08).** Exactly as plan 08 states: both writes use the legacy exception-raising `FileHandle.write(_:)`; the `do/catch` at `:35-49` only catches Swift errors from `encoder.encode` and `synchronize()`. Disk-full or an ejected volume raises an uncatchable ObjC exception mid-batch. The rest of the file is already on throwing APIs (`seekToEnd()` at `:26`, `close()` at `:55` — no `seekToEndOfFile` remains, so the plan's audit finds nothing further).

```swift
// JSONLWriter.swift:34-39
func append(_ record: Record) throws {
    do {
        let data = try encoder.encode(record)
        fileHandle.write(data)
        fileHandle.write(Data("\n".utf8))
        try fileHandle.synchronize()
```

**Change.** Diff-level, two lines:

```swift
            let data = try encoder.encode(record)
            try fileHandle.write(contentsOf: data)
            try fileHandle.write(contentsOf: Data("\n".utf8))
            try fileHandle.synchronize()
```

The existing `catch` then wraps the failure as `SidecarError(code: .writeFailed, stage: .write, …)` with the stable label wording (invariant 7 untouched — no message format change for the success path). **Note:** efficiency-plan P4 later changes the `synchronize()` cadence on these same lines — land R1-3 first and do **not** implement P4 here.

**Tests.** New file `Tests/AISidecarCoreTests/JSONLWriterTests.swift` (internal type → `@testable`; before the fix this test crashes the runner, after it passes):

```swift
import XCTest
@testable import AISidecarCore

/// R1-3: appends surface I/O failures as SidecarError instead of raising
/// an uncatchable ObjC exception (disk-full / ejected-volume hardening).
final class JSONLWriterTests: XCTestCase {
    func testAppendAfterCloseThrowsWriteFailedInsteadOfCrashing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jsonl-writer-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("progress.jsonl").path

        let writer = try JSONLWriter<ProgressRecord>(path: path, label: "progress log")
        try writer.close()

        let record = ProgressRecord(sourcePath: "/photos/A.NEF", relativePath: "A.NEF",
                                    sidecarPath: "/out/A.NEF.ai.json", status: .written, durationMs: 1)
        XCTAssertThrowsError(try writer.append(record)) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .writeFailed)
            XCTAssertTrue((error as? SidecarError)?.message.contains("progress log") ?? false)
        }
    }
}
```

**Acceptance.**
- [ ] Unit test with a `FileHandle` over a closed/invalid descriptor asserting a thrown error, not a crash.
- [ ] Existing progress-log tests (`ProgressLogTests`, `XMPExportReportTests`, `NormalizationReportTests`) stay green.

**Commit.** `Core R1-3: JSONLWriter uses throwing FileHandle writes; append failures become SidecarError`

### R1-4 — Normalize-stage failure is invisible; user bounces in a silent loop (MEDIUM)

**Goal.** A failed normalization run shows its error message on Step 3, same styling as run/export failures.

**Files.**
- `Sources/CupricAspectApp/Shells/WizardShellView.swift:112-123` (`onChange(of: normalizationModel.phase)` — `.failed where step == 4` → `step = 3`), `:228-234` (Step 3 banners check only `runModel.phase` and `exportModel.phase`)
- `Sources/CupricAspectApp/Features/Normalize/NormalizationModel.swift:113-115` (`phase = .failed(message:)` carries the `SidecarError` message)

**Current behavior (verified 2026-07-08).** Confirmed: the failed normalize run returns the user to Step 3, whose banner block renders nothing for `normalizationModel.phase`. Retrying loops silently.

```swift
// WizardShellView.swift:229-234
if case .failed(let message) = runModel.phase {
    failureBanner(message)
}
if case .failed(let message) = exportModel.phase {
    failureBanner(message)
}
```

**Change.**
1. Add the third case to the Step 3 banner block, after the two existing ones:

```swift
if case .failed(let message) = normalizationModel.phase {
    failureBanner(message)
}
```

2. Clear the stale banner on retry: `NormalizationModel.run` already sets `phase = .running` on entry (`:98`), so a new Start replaces the banner — no further change needed. (The B0-4 log-file pointer is already inside the `SidecarError` message produced by Core where applicable; the banner shows it verbatim.)

**Tests.** Extend `Tests/CupricAspectAppTests/NormalizationModelTests.swift` (uses its existing `waitUntil` helper; offline, no Ollama — normalize is model-free):

```swift
@MainActor
func testRunFailureCarriesThrownErrorMessageInPhase() async throws {
    let model = makeModel()                       // existing fixture helper
    model.vocabularyPath = "/nonexistent/vocabulary.json"
    model.run(jsonRoot: jsonRoot, sourceRoot: sourceRoot)
    try await waitUntil("normalization failure") {
        if case .failed = model.phase { return true }
        return false
    }
    guard case .failed(let message) = model.phase else { return XCTFail("expected .failed") }
    XCTAssertFalse(message.isEmpty)
    XCTAssertTrue(message.localizedCaseInsensitiveContains("vocabulary"),
                  "message should name the failing input: \(message)")
}
```

**Acceptance.**
- [ ] Force `NormalizationModel.run` to throw (nonexistent vocabulary path is easiest) → Step 3 shows the message.
- [ ] Model-level test asserts `.failed(message:)` carries the thrown error text.
- [ ] Added: starting a new run clears the previous failure banner.

**Commit.** `GUI R1-4: surface normalization failures in the Step 3 banner`

### R1-5 — Export success banner lies when targets failed (MEDIUM)

**Goal.** The Step 5 written banner reports real written/failed counts and switches to a warning tone when any target failed.

**Files.**
- `Sources/CupricAspectApp/Shells/WizardShellView.swift:257-258` (banner fed `targetReports.count`), `:295-312` (`writtenBanner(targets:)` — unconditional green "written · backups saved · validated")
- `Sources/CupricAspectApp/Features/Export/ExportModel.swift:116-117` (`phase = .written` whenever the pipeline returns)
- `Sources/AISidecarCore/Reporting/XMPExportReport.swift:136-142` (`writtenCount` / `failedCount` — already exist in Core)

**Current behavior (verified 2026-07-08).** Confirmed. `XMPExportPipeline` records per-target `.failed` statuses without throwing (`XMPExportTargetStatus` includes `.failed`), yet the banner counts every target as written. **Note (fix is smaller than plan implies):** Core already exposes exactly the needed counts — `XMPExportReport.writtenCount` (`.written` + `.created`) and `failedCount` (failed targets + input failures). The GUI only has to consume them (invariant 13: no counting logic re-implemented in the GUI).

```swift
// WizardShellView.swift:257-258
if exportModel.phase == .written {
    writtenBanner(targets: exportModel.exportReport?.targetReports.count ?? 0)
```

**Change.**
1. Add a pure banner-composition helper (testable) next to the navigation helper:

```swift
// WizardNavigation.swift
struct WrittenBannerContent: Equatable {
    var message: String
    var isWarning: Bool
}

/// R1-5: the written banner reflects real per-target outcomes.
static func writtenBanner(written: Int, failed: Int) -> WrittenBannerContent {
    if failed == 0 {
        return .init(
            message: "\(written) XMP sidecar\(written == 1 ? "" : "s") written · backups saved · validated — ready to import in Lightroom / Capture One",
            isWarning: false
        )
    }
    return .init(
        message: "\(written) of \(written + failed) written — \(failed) failed; see the report below.",
        isWarning: true
    )
}
```

2. In `WizardShellView`, feed it from the report and restyle: `writtenBanner(targets:)` becomes `writtenBanner(_ content: WrittenBannerContent)`; when `isWarning`, swap `theme.green`/`theme.greenSoft` for `theme.danger`-tinted styling (mirror `failureBanner`'s palette) and the "✓" for "!". Call site: `writtenBanner(WizardNavigation.writtenBanner(written: report.writtenCount, failed: report.failedCount))` inside the existing `if exportModel.phase == .written, let report = exportModel.exportReport` block at `:257-263`.

**Tests.** Extend `Tests/CupricAspectAppTests/WizardNavigationTests.swift`:

```swift
func testWrittenBannerCountsOnlySuccessfulTargets() {
    let clean = WizardNavigation.writtenBanner(written: 4, failed: 0)
    XCTAssertFalse(clean.isWarning)
    XCTAssertTrue(clean.message.hasPrefix("4 XMP sidecars written"))

    let mixed = WizardNavigation.writtenBanner(written: 3, failed: 2)
    XCTAssertTrue(mixed.isWarning)
    XCTAssertEqual(mixed.message, "3 of 5 written — 2 failed; see the report below.")
    XCTAssertTrue(WizardNavigation.writtenBanner(written: 0, failed: 5).isWarning)
}
```

**Acceptance.**
- [ ] Unit test on the banner-composition function with mixed target statuses.
- [ ] Manual check against a read-only output dir (all targets fail → warning banner, zero written).
- [ ] Added: singular/plural wording covered.

**Commit.** `GUI R1-5: written banner counts real target outcomes and warns on failures`

### R1-6 — "Save session only" can silently write nothing (MEDIUM)

**Goal.** Save/import/write buttons are disabled without a session, and any residual nil-session save throws instead of no-oping.

**Files.**
- `Sources/CupricAspectApp/Features/Review/ReviewModel.swift:192-195` (`saveSession` — `guard let reviewedSession else { return }`)
- `Sources/CupricAspectApp/Features/Normalize/NormalizationModel.swift:172-175` (same pattern)
- `Sources/CupricAspectApp/Features/Review/Step5ReviewView.swift:94-97` (header buttons unconditionally enabled)
- `Sources/CupricAspectApp/Features/Normalize/NormalizationInspectorView.swift:64-66` (same)
- `Sources/CupricAspectApp/Shells/WizardShellView.swift:280-293` (`startExport()` silent guards)

**Current behavior (verified 2026-07-08).** Confirmed. The user completes a full `NSSavePanel` and nothing is written, no error raised — the exact silent-failure class B0-4 targeted. `startExport()` is doubly guarded silent; after R1-2 its `sourceFolder` guard becomes near-unreachable, but the nil-session guard remains.

```swift
// ReviewModel.swift:192-195
func saveSession(to url: URL) throws {
    guard let reviewedSession else { return }
    try NormalizationSessionWriter().write(reviewedSession, to: url.path)
}
```

**Change.**
1. In both models, turn the guard-return into a thrown, user-visible error (the views' existing `do/catch → reportFileError` path then surfaces it — FR4-059 machinery already in place):

```swift
func saveSession(to url: URL) throws {
    guard let reviewedSession else {
        throw SidecarError(
            code: .validationFailed,
            stage: .write,
            message: "No review session is loaded; nothing to save.",
            recoverable: true
        )
    }
    try NormalizationSessionWriter().write(reviewedSession, to: url.path)
}
```

   Same in `NormalizationModel.saveSession` ("No normalization session is loaded; nothing to save."). Existing `SidecarErrorCode.validationFailed` is reused — no new raw string (invariant 7).
2. Expose an enable predicate on each model — `var canSaveSession: Bool { session != nil }` — and bind the buttons:
   - `Step5ReviewView:97` → `headerButton("Save session only", …)` gains `.disabled(!review.canSaveSession)` + `.opacity(review.canSaveSession ? 1 : 0.4)` (match the footer's disabled styling). "Import session…" and "Reject/Approve all" stay enabled (import legitimately loads the first session).
   - `NormalizationInspectorView:65-66` → disable "Save session only" **and** "Write normalized XMP" when `model.session == nil`.
3. `WizardShellView.startExport()`: keep the guards but make the nil-session arm report instead of vanish (`reviewModel.reportFileError("Write XMP", …)` per active action, plus `assertionFailure`); the buttons that reach it are now disabled, so this is a tripwire for future regressions.

**Tests.** Extend `Tests/CupricAspectAppTests/ReviewModelTests.swift` and `Tests/CupricAspectAppTests/NormalizationModelTests.swift`:

```swift
// ReviewModelTests.swift
@MainActor
func testSaveWithNoSessionThrowsInsteadOfSilentlySucceeding() throws {
    let model = makeModel()
    XCTAssertFalse(model.canSaveSession)
    let url = root.appendingPathComponent("never-written.json")
    XCTAssertThrowsError(try model.saveSession(to: url)) { error in
        XCTAssertEqual((error as? SidecarError)?.code, .validationFailed)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

    model.adopt(session: try makeBaseSession(terms: ["bird"]))
    XCTAssertTrue(model.canSaveSession)
    model.completeCleanly()
    XCTAssertFalse(model.canSaveSession)
}
// NormalizationModelTests.swift: mirror the same test against NormalizationModel.
```

**Acceptance.**
- [ ] Button-enable state derives from session presence.
- [ ] `save` with nil session reports an error rather than returning silently.
- [ ] Added: no file is created by a nil-session save; `startExport` nil-session arm surfaces rather than no-ops.

**Commit.** `GUI R1-6: session save/write buttons gate on session presence; nil-session save throws`

### R1-7 — "Edit everywhere" resurrects engine-withheld decisions and misses non-flat chips (MEDIUM)

**Goal.** "Apply to all photos" edits exactly the chips the user can see — matching their displayed label — and reports how many it touched.

**Files.**
- `Sources/CupricAspectApp/Features/Review/ReviewModel.swift:247-259` (`editEverywhere`), `:82-84` (`assetRows` visibility predicate + display-keyword derivation)
- `Sources/CupricAspectApp/Features/Review/Step5ReviewView.swift:63-68` (count discarded: `_ = review.editEverywhere(…)`)

**Current behavior (verified 2026-07-08).** Confirmed on all three counts: (a) the loop has no status/verdict filter, so `.withheld` decisions (never rendered — `assetRows` filters `status == .accepted || verdicts[id] != nil`) get `edits` + `.approved` verdicts and are later exported by `SessionReview.applying`; (b) it matches `edits[id] ?? decision.flatKeyword ?? ""`, while chips display `edits[id] ?? flatKeyword ?? canonicalPath ?? sourceText ?? "?"` — chips labeled from `canonicalPath`/`sourceText` can never match; (c) the returned count is discarded at the call site (`Step5ReviewView.swift:65`).

```swift
// ReviewModel.swift:251-256
for decision in session.perAssetDecisions
where (edits[decision.decisionID] ?? decision.flatKeyword ?? "").lowercased() == folded {
    edits[decision.decisionID] = text
    verdicts[decision.decisionID] = .approved
    applied += 1
}
```

**Change.**
1. Extract the shared display-keyword derivation (single source of truth for chips and batch edits):

```swift
// ReviewModel.swift
/// The keyword text a chip displays for this decision — also the match
/// key for editEverywhere, so batch edits hit exactly what the user sees.
private func displayKeyword(for decision: PerAssetNormalizationDecision) -> String {
    edits[decision.decisionID] ?? decision.flatKeyword
        ?? decision.canonicalPath ?? decision.sourceText ?? "?"
}
```

   Replace the inline derivation at `:84` with `displayKeyword(for: decision)`.
2. Rewrite `editEverywhere` with the same visibility predicate `assetRows` uses:

```swift
func editEverywhere(keyword: String, to text: String) -> Int {
    guard let session else { return 0 }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return 0 }
    let folded = keyword.lowercased()
    var applied = 0
    for decision in session.perAssetDecisions
    where (decision.status == .accepted || verdicts[decision.decisionID] != nil)
        && displayKeyword(for: decision).lowercased() == folded {
        edits[decision.decisionID] = trimmed
        verdicts[decision.decisionID] = .approved
        applied += 1
    }
    if applied > 0 { recordChange() }
    return applied
}
```

3. Surface the count in `Step5ReviewView`: add `@State private var batchEditNotice: String?`; in the alert's "Apply to all photos" action set `batchEditNotice = "Applied to \(count) photo\(count == 1 ? "" : "s")"`; render it beside the `buildError ?? fileError` text (`:27-32`) in `theme.textDim`, cleared on the next edit/verdict interaction.

**Tests.** Extend `Tests/CupricAspectAppTests/ReviewModelTests.swift`. The fixture needs a withheld decision and a `canonicalPath`-labeled decision: build the base session, then mutate a copy of `perAssetDecisions` (set one decision's `status = .withheld`; clear another's `flatKeyword` leaving `canonicalPath`) and `adopt` the doctored document — offline and deterministic.

```swift
@MainActor
func testEditEverywhereSkipsEngineWithheldDecisions() throws {
    var session = try makeBaseSession(terms: ["bird", "tree"])
    let birdIndex = try XCTUnwrap(session.perAssetDecisions.firstIndex { $0.flatKeyword == "bird" })
    session.perAssetDecisions[birdIndex].status = .withheld
    let model = makeModel()
    model.adopt(session: session)

    XCTAssertEqual(model.editEverywhere(keyword: "bird", to: "Owl"), 0,
                   "withheld decisions were never shown; batch edit must not resurrect them")
    let withheldID = session.perAssetDecisions[birdIndex].decisionID
    XCTAssertNil(model.verdicts[withheldID])
    XCTAssertNil(model.edits[withheldID])
}

@MainActor
func testEditEverywhereMatchesCanonicalPathLabeledChips() throws {
    var session = try makeBaseSession(terms: ["bird"])
    let index = try XCTUnwrap(session.perAssetDecisions.firstIndex { $0.flatKeyword == "bird" })
    session.perAssetDecisions[index].flatKeyword = nil
    session.perAssetDecisions[index].canonicalPath = "Animals|Birds"
    let model = makeModel()
    model.adopt(session: session)

    XCTAssertEqual(model.editEverywhere(keyword: "Animals|Birds", to: "Owl"), 1)
    let chips = try XCTUnwrap(model.assetRows.first?.chips)
    XCTAssertTrue(chips.contains { $0.keyword == "Owl" })
    XCTAssertEqual(model.editEverywhere(keyword: "no-such-keyword", to: "x"), 0)
}
```

**Acceptance.**
- [ ] A session containing a withheld decision with the same keyword — `editEverywhere` must not change it.
- [ ] A decision whose chip label comes from `canonicalPath` — the edit must apply.
- [ ] Count is returned and correct; `testApplySessionWritesOnlyApprovedKeywords` stays green.
- [ ] Added: the UI shows "Applied to N photos" after a batch edit; existing `testEditEverywhereAppliesToMatchingKeywordsOnly` stays green.

**Commit.** `GUI R1-7: editEverywhere edits only visible chips, matches display labels, reports count`

### R1-8 — Options-page vision model is read-only; add a per-run override dropdown (MEDIUM)

**Goal.** The Step-3 "Vision model" card is a dropdown of installed vision-capable tags that overrides the model **for this run only** — it never writes `config.json`. Leaving it untouched uses the resolved config default exactly as today.

**Files.**
- `Sources/CupricAspectApp/Features/Run/Step3OptionsView.swift:102-122` (`modelCard`, currently static text)
- `Sources/CupricAspectApp/Features/Run/AnalysisRunModel.swift:10-45` (`AnalysisOptions`: add `modelOverride`; `buildConfiguration` threads it; `loadResolvedDefaults` must not clobber it)
- Reuse: `Sources/CupricAspectApp/Features/Settings/SettingsModel.swift` (installed-tag list via `listInstalledVisionTags`) and the `SettingsSheet.swift:171-215` `modelPicker` menu as the UI template — do not re-implement the probe.

**Current behavior (verified 2026-07-08).** `modelCard` shows `options.resolvedModel` as static mono text plus the preflight badge. The only model control is Settings, which persists through `config.json` (FR4-056). No per-run override exists.

**Change.**
1. `AnalysisOptions` gains `var modelOverride: String? = nil`. In `buildConfiguration(recursive:outputDir:)`, pass the override into `RunConfigurationOverrides` as the model (the same precedence slot the CLI `--model` flag occupies), leaving it nil = resolver picks the config model:

```swift
func buildConfiguration(recursive: Bool, outputDir: String?) throws -> ResolvedRunConfiguration {
    try ConfigurationResolver.resolve(
        cli: RunConfigurationOverrides(
            mode: mode,
            existing: existing,
            recursive: recursive,
            outputDir: outputDir,
            stageConcurrency: concurrency,
            gpsContext: gps,
            model: modelOverride            // nil ⇒ resolved config model (unchanged path)
        )
    )
}
```

(Confirm `RunConfigurationOverrides` has a `model` field and that the resolver treats a nil model as "fall through"; the CLI `--model` already flows this way — mirror it. If the initializer label differs, match it.) Ensure `loadResolvedDefaults()` does **not** reset `modelOverride` (it seeds display + option defaults only), so a chosen override survives navigation within the import session (and composes cleanly with R2-1's `defaultsLoaded` guard).

2. `modelCard` becomes a dropdown. Reuse the Settings `modelPicker` pattern: a `Menu` over the installed vision tags with the effective model in a mono well and a refresh affordance; a small caption "this run only — Settings sets the saved default" to distinguish it from a config change. Source the tag list from the same model the Settings sheet uses (installed vision tags); flag an override that isn't installed/vision-capable the same way Settings does. The preflight badge already reflects `options`-derived state — after a pick, re-run `runModel.checkPreflight(options:…)` so it validates the effective model.

**STOP: maintainer decision (small).** The tag list currently lives in `SettingsModel`. Either (a) lift the installed-tag fetch into a tiny shared source both Settings and Step 3 read, or (b) have Step 3 hold its own lightweight fetch. Recommend (a) — one probe, one cache; but (b) is acceptable for R1 if (a) balloons. Either way the override value lives on `AnalysisOptions`, not in Settings.

**Tests.** `Tests/CupricAspectAppTests` — assert `AnalysisOptions.buildConfiguration` resolves to the override model when `modelOverride` is set and to the resolved config model when nil (resolver-precedence style, matching the existing config-resolution tests). The menu itself is presentation; do not test SwiftUI. Optionally assert `loadResolvedDefaults()` leaves a set `modelOverride` intact.

**Acceptance.**
- [ ] Step 3 model card opens a dropdown of installed vision-capable tags; picking one changes the run's model and the preflight re-checks against it.
- [ ] `config.json` and the Settings default are unchanged after using the override (verify the file).
- [ ] Override does not persist across imports or relaunch; nil override behaves exactly as today.

**Commit.** `GUI R1-8: Step 3 vision-model dropdown as a per-run override (no config write)`

### R1-9 — Surface the XMP conflict policy in Options → Advanced, defaulting to backup-and-merge (MEDIUM)

**Goal.** The Step-3 Advanced disclosure exposes an EXISTING XMP control mapping onto Core `XMPConflictPolicy` (`fail` / `merge` / `backup-and-merge`), defaulting to `backup-and-merge` — the current Core built-in — so the always-on merge behavior is visible and adjustable at the point of decision, with the GUI default provably equal to the CLI/Core default.

**Files.**
- `Sources/CupricAspectApp/Features/Run/Step3OptionsView.swift:170-234` (`advancedCard` grid — add the control + hint string)
- `Sources/CupricAspectApp/Features/Run/AnalysisRunModel.swift:10-45` (`AnalysisOptions`: add `xmpConflictPolicy` with default `.backupAndMerge`)
- `Sources/CupricAspectApp/Features/Export/ExportModel.swift:75-114` (stop hardcoding `ResolvedApplySessionConfiguration.builtInDefaults`; take the policy in)
- Reference: `Sources/AISidecarCore/Configuration/XMPExportConfiguration.swift:11-15` (`XMPConflictPolicy`), `Sources/AISidecarCore/Configuration/NormalizationConfiguration.swift:414` (built-in `.backupAndMerge`)

**Current behavior (verified 2026-07-08).** `ExportModel.plan`/`confirmWrite` build with `ResolvedApplySessionConfiguration.builtInDefaults` (`xmpConflictPolicy = .backupAndMerge`, `backupSidecars = true`) — safe and always-merge, but invisible to the user; Step-3 Advanced exposes only GPS / existing-sidecars / concurrency. `XMPConflictPolicy` has three cases; `.backupAndMerge` writes a timestamped `.xmp.bak` then merges, `.merge` merges without a separate backup, `.fail` refuses when an `.xmp` exists.

**Change.**
1. `AnalysisOptions` gains `var xmpConflictPolicy: XMPConflictPolicy = .backupAndMerge`. Do not seed it from `loadResolvedDefaults` unless the resolver already carries a configured value — the built-in default is the required default; keep GUI and CLI identical.
2. In `advancedCard`, add an EXISTING XMP `advancedGroup` with a `CVSegmentedControl` over `XMPConflictPolicy.allCases`, labeled Fail / Merge / Backup & Merge, bound to `$options.xmpConflictPolicy`. Add a one-line caption at the bottom of the disclosure: "Merge keeps keywords already in your `.xmp`; Backup & Merge writes a `.xmp.bak` first." Update the disclosure hint from "gps · existing sidecars · concurrency" to include "existing xmp".
3. Thread the selection into `ExportModel`: give `plan`/`confirmWrite` (or the `ExportModel` init) an `xmpConflictPolicy` input and set `configuration.xmpConflictPolicy` from it instead of relying on `builtInDefaults`. The wizard passes `options.xmpConflictPolicy` at the Step-5 write. `backupSidecars` stays true.

**Invariant/consistency note.** FR4-044 forbids inventing option values — use `XMPConflictPolicy.allCases` verbatim. The default must equal `ResolvedApplySessionConfiguration.builtInDefaults.xmpConflictPolicy` (and `ResolvedXMPExportConfiguration.builtInDefaults.xmpConflictPolicy`); a test pins this equality so a future default change can't silently diverge GUI from CLI.

**Tests.** `Tests/CupricAspectAppTests` — assert the export configuration built by the wizard carries the selected `XMPConflictPolicy`, and that the `AnalysisOptions` default equals the Core built-in (`XCTAssertEqual(AnalysisOptions().xmpConflictPolicy, ResolvedApplySessionConfiguration.builtInDefaults.xmpConflictPolicy)`). Keep the Core merge-preservation tests green (they already assert foreign-keyword retention and `.xmp.bak` creation under backup-and-merge).

**Acceptance.**
- [ ] Step-3 Advanced shows EXISTING XMP defaulting to Backup & Merge, with the caption explaining merge/backup.
- [ ] The write path uses the selected policy: under merge/backup-and-merge a pre-existing foreign keyword in the `.xmp` is preserved; under backup-and-merge a `.xmp.bak` is written; under fail an existing `.xmp` refuses.
- [ ] The GUI default equals the CLI/Core built-in (pinned by test).

**Commit.** `GUI R1-9: surface XMP conflict policy in Options → Advanced (default backup-and-merge)`

### R1-10 — Opt-in post-write cleanup of intermediate sidecars and run artifacts (MEDIUM)

**Goal.** A checkbox beside the change-plan "Write" button, off by default, that after a fully successful write removes the run's `.ai.json` raw sidecars and batch/report/summary artifacts from the artifact directory — reusing the hardened Core `ArtifactCleanup`, preserving `.xmp`, `.xmp.bak`, the derivative cache, and reusable session JSON. GUI orchestration only.

**Files.**
- `Sources/CupricAspectApp/Features/Export/ChangePlanSheet.swift:47-74` (footer — add the checkbox next to the Write button)
- `Sources/CupricAspectApp/Features/Export/ExportModel.swift:97-135` (`confirmWrite` — run cleanup after `phase = .written` on a clean write; hold the flag and the removed count)
- Reuse: `Sources/AISidecarCore/Cleanup/ArtifactCleanup.swift` (`ArtifactCleanup().run(rootPath:recursive:dryRun:)`) — do not re-implement or widen it
- The wizard passes the import's `recursive` and the effective artifact root (`pendingOutputDir ?? pendingSourceRoot`) — `ExportModel` already retains `pendingSourceRoot`/`pendingOutputDir`

**Current behavior (verified 2026-07-08).** `confirmWrite()` sets `phase = .written` and stops; nothing cleans the folder. `ArtifactCleanup` exists and is exercised by `ArtifactCleanupTests`, but only the CLI `cleanup` command calls it. The change-plan footer has Cancel + "Write N sidecars" and no other controls.

**Change.**
1. `ExportModel` gains `var cleanupAfterWrite = false` (bound to the checkbox) and `private(set) var cleanupRemovedCount: Int?`. In `confirmWrite()`, after the write task completes with `phase = .written` **and** the export report shows no failed targets, and only when `cleanupAfterWrite`, run cleanup off the main actor over the artifact root:

```swift
// after: exportReport = result.exportReport; phase = .written
if cleanupAfterWrite, (result.exportReport?.failedCount ?? 0) == 0 {
    let root = pendingOutputDir ?? pendingSourceRoot
    if let root {
        let report = try? await Task.detached(priority: .utility) {
            try ArtifactCleanup().run(rootPath: root, recursive: recursive, dryRun: false)
        }.value
        cleanupRemovedCount = report?.removedCount
        // a cleanup failure is a non-fatal warning; the delivered XMP already succeeded
    }
}
```

(`XMPExportReport.failedCount` is the accessor; thread `recursive` in from the wizard the same way `sourceRoot`/`outputDir` are already threaded into `plan`/`confirmWrite`. If the artifacts can land in both the source and a separate output dir, clean both — but only roots the run actually wrote to.)

2. `ChangePlanSheet` footer: add a `Toggle` bound to `$export.cleanupAfterWrite` to the left of the Write button (or on the row above the summary), label "Remove intermediate sidecars & run files after writing", with a `.help(...)`/caption: "Deletes the `.ai.json` sidecars and batch logs this run created. Your photos, `.xmp` files, and backups are untouched. You'll need to re-analyze to review these images again." Default unchecked on every fresh plan (`ExportModel.reset()`/`cancelPlan()` clear it).

3. The written banner (R1-5's composition function) gains "· N intermediate files removed" when `cleanupRemovedCount` is set and > 0. Keep R1-5's failure-aware tone — cleanup text is additive, never replaces the write summary.

**Invariant/safety note.** Invariant 13: no deletion logic in the view — `ChangePlanSheet` only toggles a flag; `ExportModel` calls Core. `ArtifactCleanup` is already narrow (owned filename patterns only; never source images, `.xmp`, `.xmp.bak`, derivative cache, debug derivatives, or session JSON) — do **not** broaden it for the GUI. Cleanup runs **only** after a clean write (no failed targets) so provenance is never dropped for images that didn't export; it is non-fatal (a delivered XMP is never rolled back by a cleanup error). Off by default because deleting `.ai.json` drops the FR4-049 `xmp_export` provenance and the audit trail.

**Tests.** `Tests/CupricAspectAppTests` — with a stubbed/temp fixture, `confirmWrite` + `cleanupAfterWrite == true` on a clean write invokes `ArtifactCleanup` over the expected root and records the removed count; a report with failed targets performs no cleanup; `cleanupAfterWrite == false` performs no cleanup; a session JSON in the folder survives. Reuse `ArtifactCleanupTests` for the owned-only/session-preserving deletion semantics — do not duplicate.

**Acceptance.**
- [ ] Change-plan sheet shows an unchecked "Remove intermediate sidecars & run files after writing" box beside Write, with the consequence caption.
- [ ] Checked + successful write: `.ai.json` and batch/report/summary artifacts gone from the artifact dir; `.xmp`, `.xmp.bak`, and any normalization session JSON remain; banner reports the count.
- [ ] Any failed target ⇒ no cleanup. Unchecked ⇒ no cleanup. The box is unchecked on every new plan.

**Commit.** `GUI R1-10: opt-in post-write cleanup of intermediate sidecars via Core ArtifactCleanup`

### R1-11 — Settings: expose a default for concurrency (MEDIUM)

**Goal.** The Settings `CONFIGURATION` section gains a concurrency default that persists to `config.json` (shared with the CLI) and pre-populates the Options-page stepper on the next import. Leaving it unset keeps today's resolver default (the performance-core count).

**Files.**
- `Sources/CupricAspectApp/Features/Settings/SettingsSheet.swift:274-296` (the `CVSegmentedControl` rows for mode/gps/existing in `configurationSection` — add the concurrency row alongside)
- `Sources/CupricAspectApp/Features/Settings/SettingsModel.swift:31-44` (stored properties), `:57-77` (`reload()`), `:90-107` (write-through setters like `setMode`/`setExisting`), `:81-88` (`write(_:_:)`)
- Reference (no edit): `Sources/AISidecarCore/Configuration/AppConfig.swift:25/78` (`stageConcurrency` ⇄ `"stage_concurrency"`), `RunConfiguration.swift:184/268-275` (`ResolvedRunConfiguration.stageConcurrency`, default), `ConfigurationResolver.swift:712-713` (validation: `> 0`)
- No Options-page edit: `AnalysisOptions.loadResolvedDefaults` already seeds `concurrency` from `resolved.stageConcurrency` (`AnalysisRunModel.swift:34`).

**Current behavior (verified 2026-07-08).** `SettingsModel` reads `model`, `endpoint`, `mode`, `gps`, `existing`, `derivativeCachePath` in `reload()` but never `stageConcurrency`; the setters write `mode`/`gps_context`/`existing`/`model`/`model_endpoint` only. `SettingsSheet.configurationSection` renders "Default render mode", "Default GPS context", "Existing sidecars", and the derivative-cache row — no concurrency control.

**Change.**
1. `SettingsModel` gains `@Published var stageConcurrency: Int` (seed in `reload()` from the resolved config, clamped to the UI's 1–8 like the Options page: `stageConcurrency = min(8, max(1, resolved.stageConcurrency))`) and a setter mirroring `setExisting`:

```swift
func setConcurrency(_ value: Int) {
    let clamped = min(8, max(1, value))          // resolver rejects <= 0
    write("stage_concurrency", .number(Double(clamped)))   // match the JSON-value shape write() expects
}
```

(Confirm `write(_:_:)`'s value type — mirror how the existing numeric/string writes are shaped; if `write` takes a config-value enum, use its integer/number case. `ConfigFileEditor.merge` preserves unknown keys, `AtomicFileWriter`, then `reload()`.)

2. `SettingsSheet.configurationSection` gains a `CONCURRENCY` row after "Existing sidecars": a 1–8 stepper (`−` / value / `+`) bound through `settings.setConcurrency`, styled like the Options-page stepper (`Step3OptionsView` concurrency control) so the two read identically. Add a short caption consistent with the design doc ("Lower = less memory pressure.").

**Tests.** `Tests/CupricAspectAppTests` — a `SettingsModel` write-through test asserting `setConcurrency(n)` merges `stage_concurrency` into the config file and preserves a hand-added unknown key (mirror the existing `setMode`/`setExisting` write-through tests); a resolver round-trip asserting the written value re-resolves. Clamp behavior: `setConcurrency(0)` writes `1`, `setConcurrency(99)` writes `8`.

**Acceptance.**
- [ ] Settings shows a concurrency default control; changing it writes `stage_concurrency` to `config.json` with hand-added keys preserved, and a CLI resolve reflects it.
- [ ] A fresh import's Options page shows the saved value as its concurrency default (via the existing `loadResolvedDefaults` seeding — no Options-page code change).
- [ ] Unset behaves as today (resolver default = performance-core count).

**Commit.** `GUI R1-11: Settings default for stage concurrency (write-through to config.json)`

### R1-12 — Settings: expose a default for XMP treatment; seed the Options control from config (MEDIUM)

**Goal.** The Settings `CONFIGURATION` section gains an `EXISTING XMP` default (Fail / Merge / Backup & Merge) persisting `xmp_conflict_policy` to `config.json`, and the R1-9 Options control seeds from the resolved config so the saved default (or a hand-edited value) actually flows into a run. GUI and CLI defaults stay identical.

**Files.**
- `Sources/CupricAspectApp/Features/Settings/SettingsSheet.swift:274-296` (`configurationSection` — add the `EXISTING XMP` `CVSegmentedControl`)
- `Sources/CupricAspectApp/Features/Settings/SettingsModel.swift:31-44` (property), `:57-77` (`reload()`), `:90-107` (setter)
- `Sources/CupricAspectApp/Features/Run/AnalysisRunModel.swift:27-35` (`loadResolvedDefaults` — add the seeding line), `:17` (the hard-coded `xmpConflictPolicy` initializer stays as the *fallback* default)
- Reference (no edit): `AppConfig.swift:35/86` (`xmpConflictPolicy` ⇄ `"xmp_conflict_policy"`), `XMPExportConfiguration.swift:11-15` (`XMPConflictPolicy` cases), `NormalizationConfiguration.swift:414` / `XMPExportConfiguration.swift:185` (built-in `.backupAndMerge`), `ConfigurationResolver.swift:818-819` (cross-field: `backup-and-merge` requires `backup_sidecars == true`)

**Current behavior (verified 2026-07-08).** No Settings control and no `SettingsModel` property/setter for the policy. `AnalysisOptions.xmpConflictPolicy` is initialized to `ResolvedApplySessionConfiguration.builtInDefaults.xmpConflictPolicy` at `AnalysisRunModel.swift:17` and `loadResolvedDefaults()` (`:27-35`) never touches it — so a `config.json` value is ignored by the GUI (concurrency is seeded at `:34`, XMP is not: the asymmetry this item removes).

**Change.**
1. `SettingsModel` gains `@Published var xmpConflictPolicy: XMPConflictPolicy` (seed in `reload()` from the resolved config; the resolver returns `.backupAndMerge` when unset) and a setter:

```swift
func setXMPConflictPolicy(_ policy: XMPConflictPolicy) {
    // backup-and-merge requires backup_sidecars == true, which is the default and
    // not exposed here, so all three cases are valid to write.
    write("xmp_conflict_policy", .string(policy.rawValue))
}
```

2. `SettingsSheet.configurationSection` gains an `EXISTING XMP` row: a `CVSegmentedControl` over `XMPConflictPolicy.allCases` labeled Fail / Merge / Backup & Merge (reuse the Options-page `xmpPolicyLabel` mapping, `Step3OptionsView.swift:346-352`), bound through `settings.setXMPConflictPolicy`. Add the same point-of-decision caption the Options disclosure uses ("Merge keeps keywords already in your `.xmp`; Backup & Merge writes a `.xmp.bak` first.").

3. Seed the Options control from config — one line in `loadResolvedDefaults()`:

```swift
func loadResolvedDefaults() {
    guard let resolved = try? ConfigurationResolver.resolve() else { return }
    // …existing seeds (model, endpoint, mode, gps, existing, concurrency)…
    xmpConflictPolicy = resolved.xmpConflictPolicy      // R1-12: inherit the saved/hand-edited default
}
```

(Use the resolved run/apply configuration's actual policy accessor — confirm the field name on `ResolvedRunConfiguration`/the resolved apply config surfaced here; if the analyze resolve doesn't carry it, resolve the apply/export configuration the same way `ExportModel` does. The default (`.backupAndMerge`) is unchanged, so the R1-9 equality invariant holds.)

**Invariant/consistency note.** FR4-044 forbids invented values — use `XMPConflictPolicy.allCases`. The GUI default must equal the Core built-in: the R1-9 test `XCTAssertEqual(AnalysisOptions().xmpConflictPolicy, ResolvedApplySessionConfiguration.builtInDefaults.xmpConflictPolicy)` must stay green (it does — the initializer at `:17` is untouched; only `loadResolvedDefaults` now overlays a resolved value, which equals the built-in when unset).

**Tests.** `Tests/CupricAspectAppTests` — a `SettingsModel` write-through for `xmp_conflict_policy` (preserves unknown keys); a resolver-precedence test that after writing a policy, `AnalysisOptions.loadResolvedDefaults()` seeds `xmpConflictPolicy` to it, and falls back to `.backupAndMerge` when the key is absent; keep the R1-9 default-equality and merge-preservation Core tests green.

**Acceptance.**
- [ ] Settings `CONFIGURATION` shows `EXISTING XMP` defaulting to Backup & Merge; changing it writes `xmp_conflict_policy` to `config.json` (unknown keys preserved) and a CLI resolve reflects it.
- [ ] A fresh import's Options → Advanced `EXISTING XMP` shows the saved default; unset shows Backup & Merge in both Settings and Options.
- [ ] The R1-9 per-run override still overrides for one run without writing `config.json`.

**Commit.** `GUI R1-12: Settings default for XMP conflict policy; Options inherits it via loadResolvedDefaults`

### R1-13 — Relabel the `ExistingPolicy` control so it names the program's `.ai.json` sidecars, not XMP (MEDIUM)

**Goal.** The existing-`.ai.json` control reads unambiguously as the tool's own analysis files on both the Options → Advanced disclosure and the Settings `CONFIGURATION` section, so testers stop confusing it with XMP handling. Labels and caption only — no behavior change.

**Files.**
- `Sources/CupricAspectApp/Features/Run/Step3OptionsView.swift:290` (`advancedGroup("EXISTING SIDECARS")`), `:269` (disclosure hint string "gps · existing sidecars · existing xmp · concurrency")
- `Sources/CupricAspectApp/Features/Settings/SettingsSheet.swift:290` (`settingRow("Existing sidecars")`)
- Reference (no edit): `RunConfiguration.swift:12` (`ExistingPolicy` skip/overwrite/fail), `SharedOptions.swift:92-93` (`--existing`)

**Current behavior (verified 2026-07-08).** The `ExistingPolicy` control is labeled "EXISTING SIDECARS" (Options) / "Existing sidecars" (Settings) with no `.ai.json` qualifier, sitting beside the R1-9 `EXISTING XMP` control; the disclosure hint pairs "existing sidecars · existing xmp". The bare word "sidecar" also denotes `.xmp` in the change-plan sheet (`ChangePlanSheet.swift:75/133/136/138`), so the term is overloaded.

**Change.**
1. Options: `advancedGroup("EXISTING SIDECARS")` → an explicit label, recommended `advancedGroup("EXISTING .AI.JSON SIDECARS")` (or "EXISTING ANALYSIS SIDECARS"), and the disclosure hint (`:269`) → "gps · existing .ai.json · existing xmp · concurrency". Add a one-line caption in the disclosure distinguishing the two controls: "Existing `.ai.json`: the tool's own analysis files — not your `.xmp` (see Existing XMP)."
2. Settings: `settingRow("Existing sidecars")` → "Existing `.ai.json` sidecars" (matching the Options wording), optionally with the same short caption.

**STOP: maintainer wording decision (small).** The exact label strings are Ron's call; the only requirement is that the control stop reading as XMP handling and name `.ai.json` explicitly. Pick one wording and use it in both places for consistency.

**Optional (defer to R2 if it widens the diff).** Change the change-plan sheet's bare "sidecar" (which means `.xmp`) to "XMP sidecar" (`ChangePlanSheet.swift:75/133/136/138`) so the same word never denotes two things. Not required for R1-13's acceptance.

**Tests.** Presentation-only — no unit test asserts label strings. If a label/snapshot test exists, update it deliberately and note it in the commit; otherwise the R1 manual GUI pass covers it. `swift build --product CupricAspect` must stay clean.

**Acceptance.**
- [ ] On Options → Advanced and Settings `CONFIGURATION`, the existing-`.ai.json` control names the file type explicitly; `EXISTING XMP` remains the only XMP-facing control.
- [ ] No functional change: `ExistingPolicy` cases, the `--existing` mapping, and defaults are untouched; the write path is unchanged.

**Commit.** `GUI R1-13: relabel the existing-.ai.json-sidecar control (Options + Settings) to disambiguate from XMP`

### R1-14 — Seconds-per-image rate misreads on a skip-heavy re-run (MEDIUM)

**Goal.** The Working screen's "Rate" reflects real per-image processing time even when a re-run skips most images (the natural path after picking a non-default model via R1-8), instead of dividing total elapsed by only the written count.

**Files.**
- `Sources/CupricAspectApp/Features/Run/AnalysisRunModel.swift:110-114` (`secondsPerImage`), `:151-154` (the `done` / `writtenCount` increment split in `start()`)
- `Sources/CupricAspectApp/Features/Run/Step4WorkingView.swift:122` (the "Rate" stat display — no logic change needed if the computed value is fixed)

**Current behavior (verified 2026-07-08).**

```swift
// AnalysisRunModel.swift:110-114
var secondsPerImage: Double {
    guard let startedAt, writtenCount > 0 else { return 0 }
    let elapsed = Date().timeIntervalSince(startedAt)
    return elapsed > 0.5 ? elapsed / Double(writtenCount) : 0
}
// AnalysisRunModel.swift:151-154 — every record increments done; only .written increments writtenCount
for await record in stream {
    done += 1
    if record.status == .written { writtenCount += 1 }
    ...
}
```

`elapsed` is total wall-clock across **all** records, but the denominator is `writtenCount`. With the default `existing = .skip`, a re-run of an already-analyzed folder returns `.skippedExisting` for prior images: `done` climbs, `writtenCount` stays low or zero → the rate reads wildly inflated, or `guard` returns `0` (rendered "—") when everything is skipped. The value references no model variable, confirming the model isn't the cause — the denominator is.

**Change.** Divide by the images the run actually processed. Simplest correct form — use `done` (every record represents time spent reaching a decision), or `done` minus failures if failures should be excluded; pick one and note it in the commit:

```swift
var secondsPerImage: Double {
    guard let startedAt, done > 0 else { return 0 }
    let elapsed = Date().timeIntervalSince(startedAt)
    return elapsed > 0.5 ? elapsed / Double(done) : 0
}
```

If the intent is specifically "seconds of model work per newly-analyzed image", instead accumulate elapsed only across `.written` records (a separate timer) rather than dividing whole-run elapsed by `writtenCount`; that is more invasive — the `done`-denominator form above satisfies the acceptance and is preferred unless Ron wants written-only timing.

*(Secondary, note only — do not fix here unless trivial: the Step 4 "Model" stat, `Step4WorkingView.swift:130-133`, reads the cached `preflight` state rather than the live run config; fold into R2.)*

**Tests.** Extract the arithmetic into a pure, testable function so no `Date()`/timer is needed:

```swift
// AnalysisRunModel (or a small free function)
static func secondsPerImage(elapsed: Double, done: Int) -> Double {
    guard done > 0, elapsed > 0.5 else { return 0 }
    return elapsed / Double(done)
}
```

`Tests/CupricAspectAppTests` — `secondsPerImage(elapsed: 60, done: 0) == 0` (all skipped, nothing processed → "—", not a huge number); `secondsPerImage(elapsed: 60, done: 30)` ≈ 2.0 (mixed skip+write divides by processed count); a fresh all-written run (`done == writtenCount`) matches today's figure.

**Acceptance.**
- [ ] Re-running a mostly-skipped folder shows a sane per-image rate (or "—" only when zero images were processed), for both the default and an R1-8-overridden model.
- [ ] A fresh all-written run's rate is unchanged.
- [ ] The rate arithmetic is covered by a pure-function unit test.

**Commit.** `GUI R1-14: seconds-per-image divides by processed count so skip-heavy re-runs read correctly`

### R1 exit gate

All fourteen items landed, then in order:

1. **Automated:** `swift test` green (full suite). Then `swift run aisidecar --help` and `swift build --product CupricAspect` succeed (the standing R-milestone gate, plan 08 §7).
2. **Manual GUI pass — Settings defaults + analyze:** open **Settings → `CONFIGURATION`**: it now shows a **CONCURRENCY** default (R1-11) and an **EXISTING XMP** default reading Backup & Merge (R1-12); the existing-`.ai.json` control is labeled so it clearly names the tool's own analysis files, not XMP (R1-13). Change the concurrency and XMP defaults, confirm `config.json` updates (hand-added keys survive) and a `swift run aisidecar --help`-style resolve reflects them. Then launch/import → Step 2 "Analyze" → Step 3: the model card is a dropdown of installed vision tags ("this run only"); Advanced's `EXISTING XMP` and `CONCURRENCY` show the **Settings defaults just set** (R1-12 seeding / R1-11), and the existing-`.ai.json` control carries the disambiguated label (R1-13). Start → run completes → Step 5 review shows chips. **Back from Step 5 lands on Step 3, primary enabled, review retained (R1-1); pressing Start again prompts "Re-run the analysis? … N review decisions" — Cancel keeps the data, Re-run proceeds (R1-1).** Done with unsaved verdicts asks first (R1-2 sign-off variant permitting).
3. **Manual GUI pass — write:** same fixture, action "Write" → review → "Write XMP" → plan sheet → confirm → banner counts match the report. Confirm the write honored the Step-3 EXISTING XMP policy (a pre-existing foreign keyword survives; a `.xmp.bak` exists under Backup & Merge — R1-9). Run once more with the plan sheet's **"Remove intermediate sidecars & run files after writing"** box checked: after a clean write the `.ai.json` sidecars and batch/report artifacts are gone, the `.xmp`/`.xmp.bak` and any session JSON remain, and the banner reports "N intermediate files removed" (R1-10). Repeat once with a **read-only output dir**: banner shows the warning tone with 0 written (R1-5), and **no** cleanup runs even if the box was checked (R1-10); "Save session only" with no session is disabled (R1-6).
4. **Manual GUI pass — normalize + rate:** action "Normalize" → run → Inspector. **Back from the Inspector (Step 5) lands on Step 3, then a re-run prompts before discarding the normalization session (R1-1).** Then set a **nonexistent vocabulary path** in the Inspector context and re-run: Step 3 shows the failure banner with the message (R1-4). "Apply to all photos" on an edited chip reports "Applied to N photos" (R1-7). Pick a non-default vision model in the Step-3 dropdown and confirm `config.json` is untouched afterward (R1-8). **Re-run an already-analyzed folder against that non-default model with the default skip policy so most images are `.skippedExisting`; the Step 4 "Rate" shows a sane seconds-per-image (or "—" only when nothing was processed), not an inflated figure (R1-14).**
5. **Manual GUI pass — apply-session:** action "Apply" → Step 3 pick a saved session JSON → "Apply session" → plan sheet → confirm → written banner + report.
6. **Kill-relaunch-restore-export:** run `Scripts/m8-kill-relaunch-check.sh` (needs Ollama + a vision model) for the SIGKILL/no-temp-file/no-database invariants; then the R1-2-specific manual leg: start a review, record a few verdicts (≥ the autosave threshold or wait for it), `kill -9` CupricAspect, relaunch → recovery banner → Restore → verdicts present, **"Write XMP" available**, export end-to-end → Done (no data-loss prompt after export).
7. Only then proceed to B0-5 evidence, signing, and the `v0.1.0-beta.1` tag per the phase-4 plan.

## Milestone R2 — GUI hardening round 2

First post-beta code milestone (plan 08 §1.1 step 4: R2-1 → R2-7, in order). Entry criteria: `v0.1.0-beta.1` is tagged and `swift test` is green on `main`. All seven items are GUI-scope mediums/lows from the plan 08 review; each is independently landable and committable. Invariant 13 applies throughout: fixes stay in `Sources/CupricAspectApp` as presentation/state-orchestration changes — no processing moves out of Core. All new tests go in `Tests/CupricAspectAppTests` and must be offline and deterministic (no Ollama, no network).

### R2-1 — Options silently reset on re-entering Step 3

**Goal.** User-set run options (mode, gps, existing, concurrency) survive every return to Step 3 within an import session — including the automatic failed-run bounce — so "Existing: Redo" retries actually redo.

**Files.**
- `Sources/CupricAspectApp/Features/Run/Step3OptionsView.swift:44-51` (`onAppear`)
- `Sources/CupricAspectApp/Features/Run/AnalysisRunModel.swift:21-29` (`AnalysisOptions.loadResolvedDefaults`)
- `Sources/CupricAspectApp/Shells/WizardShellView.swift:10` (`@State private var options = AnalysisOptions()`)

**Current behavior (verified 2026-07-08).** `Step3OptionsView.onAppear` unconditionally re-runs `loadResolvedDefaults()`, which overwrites `mode`, `gps`, `existing`, and `concurrency` from the config chain every time the view appears. A failed run bounces back to Step 3 (`WizardShellView.swift:107` `step = 3`), so a user who set "Existing: Redo" gets silently reverted to the resolved default (typically `skip`), making the retry a no-op.

```swift
// Step3OptionsView.swift:44-46
.onAppear {
    options.loadResolvedDefaults()
    runModel.checkPreflight(
```

```swift
// AnalysisRunModel.swift:21-28 (AnalysisOptions)
func loadResolvedDefaults() {
    guard let resolved = try? ConfigurationResolver.resolve() else { return }
    resolvedModel = resolved.model
    resolvedEndpoint = resolved.modelEndpoint.absoluteString
    mode = resolved.mode
    gps = resolved.gpsContext
    existing = resolved.existing
    concurrency = min(8, max(1, resolved.stageConcurrency))
```

**Change.**
1. In `AnalysisOptions`, split display refresh from option seeding. Add a `private(set) var defaultsLoaded = false` flag; make `loadResolvedDefaults()` always refresh `resolvedModel`/`resolvedEndpoint` (cheap, display-only) but assign `mode`/`gps`/`existing`/`concurrency` only when `defaultsLoaded == false`, then set it `true`.
2. Add `func resetToResolvedDefaults()` that clears `defaultsLoaded` and calls `loadResolvedDefaults()` — the explicit "new import session" reseed.
3. In `WizardShellView`, call `options.resetToResolvedDefaults()` where a new import begins — inside the `.onChange`/call path where `importModel.chooseSource` runs from the UI (the Step 1 folder pick and the reopen-offer accept), not on step navigation.
4. Leave the `onAppear` call in `Step3OptionsView` as-is — with step 1 it becomes idempotent for the user-set fields.

```swift
// AnalysisOptions
private(set) var defaultsLoaded = false

func loadResolvedDefaults() {
    guard let resolved = try? ConfigurationResolver.resolve() else { return }
    resolvedModel = resolved.model
    resolvedEndpoint = resolved.modelEndpoint.absoluteString
    guard !defaultsLoaded else { return }
    defaultsLoaded = true
    mode = resolved.mode
    gps = resolved.gpsContext
    existing = resolved.existing
    concurrency = min(8, max(1, resolved.stageConcurrency))
}

func resetToResolvedDefaults() {
    defaultsLoaded = false
    loadResolvedDefaults()
}
```

**Tests.** `Tests/CupricAspectAppTests/AnalysisRunTests.swift` (existing file; follow `testOptionsOverridesLandInResolvedConfiguration` style).

```swift
@MainActor
func testUserEditedOptionsSurviveRepeatedDefaultLoadsAndResetReseeds() {
    let options = AnalysisOptions()
    options.loadResolvedDefaults()
    let seeded = options.existing
    options.existing = .redo
    options.concurrency = 4
    options.loadResolvedDefaults() // simulates re-entering Step 3
    XCTAssertEqual(options.existing, .redo, "failed-run bounce must not revert Existing")
    XCTAssertEqual(options.concurrency, 4)
    options.resetToResolvedDefaults() // simulates a new import session
    XCTAssertEqual(options.existing, seeded)
}
```

Note: `ConfigurationResolver.resolve()` reads the real config chain; assert relative to the seeded value (as above) rather than hard-coding `.skip`, so the test stays deterministic on machines with a local config.json.

**Acceptance.**
- [ ] Set option → navigate away/back → option persists (plan 08 verbatim).
- [ ] Failed-run bounce to Step 3 keeps "Existing: Redo".
- [ ] Choosing a new source folder reseeds options from resolved defaults.
- [ ] `resolvedModel`/`resolvedEndpoint` still refresh on every Step 3 entry.

**Commit.** `GUI: keep user-set run options across Step 3 re-entry (R2-1)`

### R2-2 — No terminate-time autosave

**Goal.** ⌘Q or closing the window flushes pending review verdicts through `ReviewModel.autosaveNow()` before the process exits, so at most zero (not 24) verdicts are lost.

**Files.**
- `Sources/CupricAspectApp/App/CupricAspectApp.swift:22-37` (`AppDelegate`; plan cites :34-36 — `applicationShouldTerminateAfterLastWindowClosed`)
- `Sources/CupricAspectApp/Features/Review/ReviewModel.swift:271-285` (`autosaveNow()` — synchronous, error-swallowing; safe to call at terminate)
- `Sources/CupricAspectApp/Shells/WizardShellView.swift:13` (`reviewModel` is `@State` inside the shell — the delegate has no reference to it)

**Current behavior (verified 2026-07-08).** `AppDelegate` implements only launch activation and last-window-closed termination; there is no `applicationShouldTerminate(_:)`, so the FR4-046a autosave cadence (every 25 decisions or 5 minutes, `ReviewModel.swift:263-269`) is the only persistence and up to 24 verdicts / 5 minutes of edits die with the process.

```swift
// CupricAspectApp.swift:34-36
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
}
```

**Change.** `ReviewModel` lives as `@State` in `WizardShellView`, so the delegate needs a registration seam — a tiny MainActor registry keeps the dependency arrow pointing shell → app, matching the existing `onRecord` closure-wiring style.
1. Add a registry to `CupricAspectApp.swift` (or a new `App/TerminationFlush.swift`):

```swift
/// Terminate-time flush hooks (FR4-046a): models with unsaved state register
/// a synchronous flush; AppDelegate runs them before allowing termination.
@MainActor
enum TerminationFlush {
    private(set) static var actions: [() -> Void] = []
    static func register(_ action: @escaping () -> Void) { actions.append(action) }
    static func runAll() { actions.forEach { $0() } }
}
```

2. In `AppDelegate`:

```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    TerminationFlush.runAll()
    return .terminateNow
}
```

3. In `WizardShellView`'s existing `.task` block (`WizardShellView.swift:45`), register once: `TerminationFlush.register { [weak reviewModel] in reviewModel?.autosaveNow() }` — note `@Observable` classes are reference types, so capture weakly. `autosaveNow()` is synchronous and never throws out (`ReviewModel.swift:282-284` swallows errors), so `.terminateNow` is always safe to return.
4. Do the same for `NormalizationModel` only if it gains unsaved state later — today its session is either on disk or reproducible, so ReviewModel is the only registrant.

**Tests.** `Tests/CupricAspectAppTests/ReviewModelTests.swift` (model-level, per plan 08 — the AppKit terminate path itself is manual-checklist territory).

```swift
@MainActor
func testAutosaveNowFlushesPendingVerdictsBelowCadenceThreshold() async throws {
    // Build a session (existing fixture helper), apply 1 verdict —
    // below the 25-decision cadence, so no automatic autosave fired.
    // ...fixture setup as in existing ReviewModelTests...
    model.setVerdict(.rejected, for: firstDecisionID)
    XCTAssertFalse(FileManager.default.fileExists(atPath: model.recoveryURL.path))
    model.autosaveNow()
    XCTAssertTrue(FileManager.default.fileExists(atPath: model.recoveryURL.path))
    // Reload and assert the verdict round-trips.
    let restored = ReviewModel(stateDirectory: stateDir)
    try restored.restoreFromRecovery()
    XCTAssertEqual(restored.verdicts[firstDecisionID], .rejected)
}
```

Plus a two-line `testTerminationFlushRunsRegisteredActions` (register a closure, `runAll()`, assert it ran); add an internal `_resetForTesting()` if cross-test registry state becomes a concern.

**Acceptance.**
- [ ] Model-level `autosaveNow` writes pending changes (plan 08 verbatim).
- [ ] `applicationShouldTerminate` runs registered flushes and returns `.terminateNow`.
- [ ] Manual: make 1 verdict, ⌘Q immediately, relaunch — recovery offer contains the verdict.

**Commit.** `GUI: flush review autosave on app termination (R2-2)`

### R2-3 — Overlapping rescans race

**Goal.** Only the most recently requested folder scan can publish results, and a scan failure shows the scanner's real error instead of a generic message.

**Files.**
- `Sources/CupricAspectApp/Features/Import/FolderImportModel.swift:72-92` (`chooseSource`/`chooseOutput`/`toggleRecursive` each fire `Task { await rescan() }`), `:119-169` (`rescan()`)

**Current behavior (verified 2026-07-08).** Every trigger spawns an independent uncancelled `Task`; two rapid triggers (e.g. pick source, then immediately toggle recursive) race, and whichever detached scan finishes last wins `assets`/`scanErrors` — possibly the stale one. Inside `rescan()`, scan failure is collapsed by `try?`:

```swift
// FolderImportModel.swift:128-131
let outcome: (records: [AssetRecord], issues: [ScanIssue])? = await Task.detached(priority: .userInitiated) {
    guard let inventory = try? ImageScanner().inventory(inputPath: inputPath, recursive: recursive) else {
        return nil
    }
```

and the fallback publishes a hard-coded `"Unable to scan the selected folder."` with code `"validation_failed"` (`:158-166`). `scanning` is also cleared by whichever scan finishes first (`defer` at `:122`).

**Change.**
1. Add a generation token; stamp each `rescan()` and publish only if still current:

```swift
private var scanGeneration = 0

func rescan() async {
    guard let sourceFolder else { return }
    scanGeneration += 1
    let generation = scanGeneration
    scanning = true
    defer { if generation == scanGeneration { scanning = false } }
    // ... detached scan unchanged ...
    guard generation == scanGeneration else { return } // stale scan: drop
    // publish assets/scanErrors
}
```

All mutations of `scanGeneration` happen on the MainActor (the model is `@MainActor`), so no locking is needed.
2. Replace `try?` with `do/catch` inside the detached closure; on error return the thrown `SidecarError`'s code and message (falling back to `error.localizedDescription`) so the published `ScanIssue` carries the real cause (e.g. "Input path does not exist: …" from `ImageScanner.discover`). Keep the closure's return type a small enum/`Result` instead of `Optional`.
3. For deterministic tests, add an internal test seam — the smallest change that respects invariant 13 (scanning itself stays Core's `ImageScanner`):

```swift
/// Test seam; production default is Core's scanner.
var inventoryProvider: @Sendable (String, Bool) throws -> ScanInventory = {
    try ImageScanner().inventory(inputPath: $0, recursive: $1)
}
```

**Tests.** New file `Tests/CupricAspectAppTests/FolderImportRescanTests.swift` (conventions per `FolderImportReopenTests.swift`: `@MainActor` class, temp folder + suite-scoped `UserDefaults` in `setUpWithError`).

```swift
@MainActor
func testStaleScanResultIsDropped() async throws {
    let model = FolderImportModel(defaults: defaults)
    model.inventoryProvider = { path, _ in
        if path.hasSuffix("slow") { usleep(200_000) } // first scan finishes last
        return try ImageScanner().inventory(inputPath: path, recursive: false)
    }
    // slowFolder has 2 images, fastFolder has 1 (create fixtures in setUp).
    model.sourceFolder = slowFolder
    async let first: Void = model.rescan()
    model.sourceFolder = fastFolder
    async let second: Void = model.rescan()
    _ = await (first, second)
    XCTAssertEqual(model.assets.count, 1, "stale slow-scan result must not overwrite the newer scan")
    XCTAssertFalse(model.scanning)
}

@MainActor
func testScanFailureSurfacesScannerErrorMessage() async {
    let model = FolderImportModel(defaults: defaults)
    model.chooseSource(folder.appendingPathComponent("does-not-exist"))
    await waitUntilNotScanning(model)
    XCTAssertEqual(model.assets, [])
    XCTAssertTrue(model.scanErrors.first?.message.contains("does not exist") == true,
                  "real scanner error, not the generic fallback")
}
```

**Acceptance.**
- [ ] Two interleaved fake scans — stale result dropped (plan 08 verbatim).
- [ ] `inventory` errors surface distinctly (plan 08 verbatim): message from the thrown error, not the generic string.
- [ ] `scanning` reflects the latest scan, not whichever finished first.

**Commit.** `GUI: drop stale folder rescans via generation token; surface scan errors (R2-3)`

### R2-4 — Progress >100% when the folder changed after import

**Goal.** The Step 4 progress bar and percent label never exceed 100%, even when the pipeline's own rescan finds more files than the import-time count.

**Files.**
- `Sources/CupricAspectApp/Features/Run/AnalysisRunModel.swift:95-97` (`progressFraction`), `:126-146` (`start` sets `total = expectedTotal` at `:131`; per-record loop at `:139-146`)
- `Sources/CupricAspectApp/Features/Run/Step4WorkingView.swift:60-63,73` (count label, percent label, bar width — all driven by `done`/`total`/`progressFraction`)

**Current behavior (verified 2026-07-08).** `start(...)` freezes `total` at the caller's `expectedTotal` (the Step 1 import count); `AnalyzePipeline.run` rescans the folder itself, so files added after import make `done` exceed `total`, the fraction exceed 1.0, and the label read ">100%".

```swift
// AnalysisRunModel.swift:95-97
var progressFraction: Double {
    total > 0 ? Double(done) / Double(total) : 0
}
```

**Discrepancy:** plan 08 says to "reconcile `total` from the run's own planned count when the first progress record arrives", but `ProgressRecord` (`Sources/AISidecarCore/Reporting/ProgressLog.swift:12-59`) carries no planned/total count — only per-file fields — so that reconciliation is not implementable as stated without a Core API change (out of R2's GUI scope). The GUI-side equivalent below achieves the same observable outcome.

**Change.**
1. Clamp the fraction: `min(1, Double(done) / Double(total))`.
2. Reconcile `total` as records arrive — in the record loop (`start`'s first `Task`, `:139-146`), after `done += 1`, add `if done > total { total = done }`. The bar then sits at 100% and the count label reads a consistent `N / N` instead of `N / M` with `N > M`.
3. Leave `expectedTotal` as the initial estimate; do not add a planned-count to Core in this item (if M11's 5k-asset work wants exact totals, thread a count through `AnalyzePipeline`'s progress hook there).

```swift
// AnalysisRunModel.swift
var progressFraction: Double {
    total > 0 ? min(1, Double(done) / Double(total)) : 0
}
```

**Tests.** `Tests/CupricAspectAppTests/AnalysisRunTests.swift`.

```swift
@MainActor
func testProgressFractionClampsToOne() {
    let model = AnalysisRunModel()
    // Use whatever internal seam start()/the record loop exposes; if none,
    // make done/total setting internal-testable rather than private(set)-only.
    model.applyProgressForTesting(done: 12, total: 10)
    XCTAssertEqual(model.progressFraction, 1.0)
    XCTAssertEqual(model.total, 12, "total reconciles upward so the label reads 12 / 12")
}
```

Plus `testProgressFractionZeroWhenTotalUnknown` (fresh model → fraction 0, no divide-by-zero).

(Add a small `internal func applyProgressForTesting(done:total:)` or route the test through the same code path the record loop uses; `done`/`total` are `private(set)` today at `:84-85`.)

**Acceptance.**
- [ ] Progress math clamp (plan 08 verbatim): fraction never exceeds 1.0.
- [ ] `done > total` reconciles `total` upward; percent label caps at 100%.

**Commit.** `GUI: clamp analysis progress at 100% and reconcile stale totals (R2-4)`

### R2-5 — Decode/IO polish batch

**Goal.** Four small robustness fixes land as one batch: undecodable thumbnails stop re-decoding on every scroll, unreadable sidecars say so in the preview, rescans stop fully parsing every `.ai.json`, and log rotation accounting survives a failed rotate.

**Files.**
- `Sources/CupricAspectApp/Features/Preview/ThumbnailStore.swift:36-57`
- `Sources/CupricAspectApp/Features/Preview/AssetPreview.swift:35-38` (+ display surface `AssetPreviewSheet.swift:105-113`)
- `Sources/CupricAspectApp/Features/Import/AssetQueue.swift:104-111` (`hasXMPExportBlock`)
- `Sources/CupricAspectApp/Support/GUILog.swift:52-55` (`FileLogSink.write` rotation block)

**Current behavior (verified 2026-07-08).**
(a) `ThumbnailStore.thumbnail(for:)` caches only successful decodes (`:49-55` `if let thumbnail { cache.setObject(...) }`), so an undecodable file is re-decoded on every grid appearance.
(b) `AssetPreviewDetails.load` swallows both an unreadable file and a malformed sidecar — `AssetPreview.swift:35-38` is `if let data = fileManager.contents(atPath: rawSidecarPath) { ... if let sidecar = try? decoder.decode(RawJSONSidecar.self, from: data) {`, so `details.sidecarErrors` stays empty and the preview looks like a never-analyzed asset.
(c) `hasXMPExportBlock` runs `JSONSerialization.jsonObject` over the whole sidecar — materializing the full object graph including multi-KB `raw_response_text` fields — once per asset per rescan (and rescans fire after every run/write, `WizardShellView.swift:104,117,130`):

```swift
// AssetQueue.swift:104-111
static func hasXMPExportBlock(rawSidecarPath: String, fileManager: FileManager = .default) -> Bool {
    guard let data = fileManager.contents(atPath: rawSidecarPath),
          let object = try? JSONSerialization.jsonObject(with: data),
          let dictionary = object as? [String: Any] else {
        return false
    }
    return dictionary["xmp_export"] != nil
}
```

(d) `FileLogSink.write` resets `currentSize = 0` even when the rotation `moveItem` failed (both rotation calls are `try?`), so subsequent size accounting is wrong and the file grows past the cap:

```swift
// GUILog.swift:52-55
if currentSize + data.count > sizeCapBytes {
    try? fileManager.removeItem(at: previousLogURL)
    try? fileManager.moveItem(at: logURL, to: previousLogURL)
    currentSize = 0
}
```

**Change.**
1. **Negative thumbnail cache.** Make `ThumbnailBox` hold `Thumbnail?`; on a nil decode, cache a sentinel box with a small fixed cost (e.g. 1 KB) so `NSCache` can still evict it. `cachedThumbnail(for:)` needs a tri-state answer (miss vs. cached-nil), e.g. `func cachedResult(for path: String) -> Thumbnail?? ` or a private lookup returning the box; `thumbnail(for:)` returns the cached nil without re-dispatching a decode.
2. **Sidecar unreadable surface.** In `AssetPreviewDetails.load`, distinguish three cases: file missing (current silent behavior is correct — asset not yet analyzed), file present but unreadable, and file readable but undecodable. For the latter two append to `details.sidecarErrors` (e.g. `"sidecar unreadable: <lastPathComponent>"` / `"sidecar malformed: <decode error>"`) — `AssetPreviewSheet.swift:105-113` already renders `sidecarErrors`, so no view change is needed. Use `fileManager.fileExists` to separate missing from unreadable, and `do/catch` around `decoder.decode` for the malformed case.
3. **Partial-decode probe.** Replace the `JSONSerialization` full parse with a minimal `Decodable` probe so only the one key is materialized:

```swift
private struct XMPExportProbe: Decodable {
    struct Present: Decodable {}
    let xmpExport: Present?
    enum CodingKeys: String, CodingKey { case xmpExport = "xmp_export" }
}

static func hasXMPExportBlock(rawSidecarPath: String, fileManager: FileManager = .default) -> Bool {
    guard let data = fileManager.contents(atPath: rawSidecarPath),
          let probe = try? JSONDecoder().decode(XMPExportProbe.self, from: data) else {
        return false
    }
    return probe.xmpExport != nil
}
```

(`Present` decodes from any keyed JSON object and ignores its contents.) Measure before/after at a 5k-sidecar fixture (generate synthetic `.ai.json` files with realistic `raw_response_text` padding in the scratchpad); record numbers in the commit message — this feeds M11's scale work.
4. **Rotation accounting.** Only reset `currentSize` when the move succeeded:

```swift
if currentSize + data.count > sizeCapBytes {
    try? fileManager.removeItem(at: previousLogURL)
    do {
        try fileManager.moveItem(at: logURL, to: previousLogURL)
        currentSize = 0
    } catch {
        // Rotation failed: keep appending to the oversized file with honest
        // accounting; retry on the next write.
    }
}
```

**Tests.** Spread across the owning test files.

```swift
// Tests/CupricAspectAppTests/AssetPreviewTests.swift
func testUndecodableThumbnailIsNegativelyCachedAndNotRedecoded() async { /* ThumbnailStore with a garbage .jpg; count decodes via an injected or subclassed decode hook, assert second call returns nil without a second decode */ }
func testLoadReportsUnreadableSidecar() { /* write garbage bytes to X.ai.json; load; assert sidecarErrors contains "malformed"/"unreadable" */ }
func testLoadStaysSilentWhenSidecarMissing() { /* no sidecar file; sidecarErrors empty */ }

// Tests/CupricAspectAppTests/AssetQueueDerivationTests.swift
func testHasXMPExportBlockViaPartialDecode() { /* sidecar JSON with xmp_export → true; without → false; garbage → false */ }
func testHasXMPExportBlockIgnoresKeyNestedInStrings() { /* "xmp_export" appearing only inside a string value → false */ }

// Tests/CupricAspectAppTests/GUILogTests.swift (conventions: real temp dir, small caps)
func testFailedRotationKeepsSizeAccounting() { /* make previousLogURL's parent read-only or point directory at a path where move fails; write past cap twice; assert currentSize not reset — observable as: file keeps growing and a later successful rotation still triggers */ }
```

**Acceptance.**
- [ ] `ThumbnailStore` negative cache for undecodable files (plan 08 verbatim).
- [ ] `AssetPreviewDetails.load` surfaces "sidecar unreadable" instead of `try?`-silent missing facts (plan 08 verbatim); missing file stays silent.
- [ ] `hasXMPExportBlock` no longer materializes the full sidecar; measured at 5k assets, numbers recorded (plan 08: "Measure at 5k assets (ties into M11)").
- [ ] `FileLogSink.write` doesn't reset `currentSize` when rotation's `moveItem` failed (plan 08 verbatim).

**Commit.** `GUI: decode/IO polish — negative thumb cache, sidecar errors, partial xmp_export probe, log rotation accounting (R2-5)`

### R2-6 — Delete or gate `NormalizationModel.writeNormalizedXMP`

**Goal.** No GUI code path can write XMP without passing the FR4-029 dry-run gate; the production-dead direct-write path is removed (or routed through `ExportModel`).

**Files.**
- `Sources/CupricAspectApp/Features/Normalize/NormalizationModel.swift:183-208` (`writeNormalizedXMP`), `:30-37` (`Phase` — `.writing`, `.written` exist only for this path)
- `Sources/CupricAspectApp/Shells/WizardShellView.swift:116-117` (`case .written:` handler; plan cites :115-117)
- `Tests/CupricAspectAppTests/NormalizationModelTests.swift:161-184` (`testWriteNormalizedXMPProducesSidecarsFromAcceptedSet` — the sole caller)
- `Tests/CupricAspectAppTests/ExportModelTests.swift` (retarget destination)
- `agent_docs/phase-4-gui-implementation-plan.md:103` ("Decisions required before M9" item 1 — record the outcome there)

**Current behavior (verified 2026-07-08).** `writeNormalizedXMP` is production-dead: the only call site in `Sources` or `Tests` outside its definition is `NormalizationModelTests.swift:170`. The Wizard's normalize flow instead routes through `startExport()` → `exportModel.plan(...)` (`WizardShellView.swift:266-293`), which sets `dryRun = true` first (FR4-029). `writeNormalizedXMP` sets `dryRun = false` directly, bypassing the gate:

```swift
// NormalizationModel.swift:194-197
var configuration = ResolvedApplySessionConfiguration.builtInDefaults
configuration.sourceRoot = sourceRoot
configuration.outputDir = outputDir
configuration.dryRun = false
```

Nothing in production sets `phase = .written`, so the shell's handler is unreachable outside tests:

```swift
// WizardShellView.swift:116-117
case .written:
    Task { await importModel.rescan() }
```

**Change.** Two options, per plan 08 (which presents both without choosing — **STOP: maintainer decision**; record the choice in `agent_docs/phase-4-gui-implementation-plan.md` "Decisions required before M9" item 1, which explicitly waits on this resolution because it affects the Studio "Write XMP" view's mapping onto `ExportModel`).

- **Option A — delete (recommended).** Remove `writeNormalizedXMP`, the now-unused `Phase.writing`/`Phase.written` cases, and the `case .written:` handler in `WizardShellView.onChange(of: normalizationModel.phase)`. Retarget the test: `ExportModelTests` already covers `plan` → `confirmWrite` (`testPlanThenWriteFlipsQueueDerivationToExported`), so replace `testWriteNormalizedXMPProducesSidecarsFromAcceptedSet` with a normalize-flavored `ExportModel` test — build the session via `NormalizationModel.run`, then `exportModel.plan(session:...)` + `confirmWrite()`, assert one `.xmp` written from the accepted set. Recommended because: the production flow already goes through `ExportModel`; keeping a second write path invites exactly the gate-bypass this item exists to close; and less code satisfies invariant 13's "one write path" spirit. Risk: if the M9 Studio "Write XMP" view wants a session-document-input write surface, it should still compose `ExportModel`, not resurrect this method — Option A does not foreclose anything.
- **Option B — gate.** Rewrite `writeNormalizedXMP` as a thin wrapper that forwards to an injected `ExportModel` (`exportModel.plan(session:sourceRoot:outputDir:)`) so every invocation hits the dry-run gate and the plan sheet. Keeps a named normalize-write entry point for M9 at the cost of `NormalizationModel` holding an `ExportModel` reference and duplicated phase bookkeeping.

Steps (Option A):
1. Delete `NormalizationModel.writeNormalizedXMP` and the `Phase.writing`/`.written` cases; fix the exhaustive `switch` in `WizardShellView.onChange(of: normalizationModel.phase)` by deleting `case .written:`.
2. Rewrite the test as described; keep its fixture and `waitUntil` helper.
3. Update `agent_docs/phase-4-gui-implementation-plan.md:103` — replace "delete or gate … that resolution affects this decision" with the recorded outcome ("deleted in R2-6; Studio Write XMP view must compose `ExportModel`").

**Tests.** `Tests/CupricAspectAppTests/ExportModelTests.swift` (Option A).

```swift
@MainActor
func testNormalizeSessionWritesAcceptedSetThroughDryRunGate() async throws {
    let (jsonRoot, sourceRoot) = try writeFixture(terms: ["bird", "tree"]) // port helper from NormalizationModelTests
    let normalization = NormalizationModel(stateDirectory: stateDir)
    normalization.run(jsonRoot: jsonRoot, sourceRoot: sourceRoot)
    try await waitUntil("normalization run") { normalization.phase == .ready }

    let export = ExportModel(stateDirectory: stateDir)
    export.plan(session: try XCTUnwrap(normalization.session), sourceRoot: sourceRoot, outputDir: xmpOut)
    try await waitUntil("dry-run plan") { export.phase == .planReady }
    XCTAssertEqual(export.writableTargets.count, 1, "gate produced a reviewable plan before any write")

    export.confirmWrite()
    try await waitUntil("write") { export.phase == .written }
    let xmpFiles = try FileManager.default.contentsOfDirectory(atPath: xmpOut).filter { $0.hasSuffix(".xmp") }
    XCTAssertEqual(xmpFiles.count, 1)
}
```

**Acceptance.**
- [ ] `writeNormalizedXMP` deleted (or routed through `ExportModel`) — no `dryRun = false` write reachable without a preceding `planReady` (plan 08 verbatim intent).
- [ ] Its test retargeted at `ExportModel`'s path; `swift test` green.
- [ ] `WizardShellView` `.written` dead branch removed (Option A).
- [ ] Decision recorded in `agent_docs/phase-4-gui-implementation-plan.md` "Decisions required before M9" item 1.

**Commit.** `GUI: remove ExportModel-bypassing writeNormalizedXMP dead path (R2-6)`

### R2-7 — Known-issues note: concurrent instances

**Goal.** README documents that running two app instances (or GUI + CLI) concurrently is unsupported-but-safe: atomic writers prevent corruption, but last-writer-wins losses are possible.

**Files.**
- `README.md:284` ("## Troubleshooting" — add a new bolded entry matching the existing format: `**heading**` + short paragraph)
- Shared paths to name in the note (verified): review recovery `~/Library/Application Support/CupricAspect/recovery/review-recovery.json` (`ReviewModel.swift:66-74`), diagnostic log `~/Library/Application Support/CupricAspect/logs/cupricaspect.log` (`GUILog.swift:90-95`), and the shared `config.json` read-modify-write from GUI Settings.

**Current behavior (verified 2026-07-08).** The Troubleshooting section has four entries (`E_MODEL_TAG_NOT_FOUND`, Ollama connection, memory pressure, XCTest) and nothing about concurrent instances. Nothing prevents two instances: the app is a plain SwiftPM binary/bundle with no single-instance lock.

**Change.** Documentation only — no code. Add after the existing entries:

```markdown
**Running two copies at once**

Running two CupricAspect instances — or the app and the `aisidecar` CLI —
against the same folders at the same time is not supported. All writers are
atomic, so nothing corrupts, but the instances share the review recovery
file, the diagnostic log, and `config.json`, and the last writer wins: one
instance's review autosave or settings change can silently replace the
other's. Quit one copy before working in the other. (A single-instance
lock is tracked as possible M11 scope.)
```

Keep plan 08's scope boundary: no lock, no `NSFileCoordinator` — plan 08 §"deliberately not doing" defers two-instance file coordination to M11 "if ever needed".

**Tests.** None (doc-only). Not applicable to `swift test`.

**Acceptance.**
- [ ] Documented as a beta known issue in README Troubleshooting (plan 08 verbatim).
- [ ] Note names the three shared surfaces (recovery file, log, config) and states the atomic-writes/no-corruption guarantee.
- [ ] No code change in this item.

**Commit.** `Docs: README known issue — concurrent instances are last-writer-wins (R2-7)`

### R2 exit gate

- `swift test` green (all new tests in `Tests/CupricAspectAppTests` pass offline).
- Manual GUI pass over the touched surfaces:
  1. Import a folder → Step 3 → set Existing: Redo → run a folder with existing sidecars → verify files re-analyze; force a failure (stop Ollama) → bounce to Step 3 → options unchanged.
  2. Make one review verdict → ⌘Q immediately → relaunch → recovery offer restores the verdict.
  3. Pick a source folder, then immediately toggle recursive twice — asset count settles on the final configuration; pick a nonexistent/permission-denied folder — the error banner shows the scanner's message.
  4. Start a run, add files to the folder mid-run — progress caps at 100% and the count label stays consistent.
  5. Preview an asset whose `.ai.json` is garbage — the sheet shows the sidecar-unreadable notice; grid-scroll past a corrupt image repeatedly — no per-scroll decode stall.
  6. Normalize flow end-to-end — write goes through the plan sheet (dry-run gate); no direct-write path remains.
  7. README renders the concurrent-instances note.
- Record the R2-6 decision in `agent_docs/phase-4-gui-implementation-plan.md` before starting M9 planning.

## Milestone R3 — CLI process-boundary hardening

R3 runs after R2. R3 and R4 are independent and may swap wholesale, but do not interleave them. Items run in order R3-1 → R3-11; R3-11's sub-items are each one small commit and may be reordered or individually deferred. Two items change observable behavior (R3-1 exit codes, R3-8 artifact names): both update `agent_docs/testing-and-verification.md`, the README, and golden tests deliberately, and say so in their commits. All source claims below re-verified against the working tree on 2026-07-08.

### R3-1 — Nonzero exit codes for failed/interrupted batches

**Goal.** Every batch command exits nonzero when any per-file failure or an interruption occurred, under one shared policy, so `analyze && write-xmp` scripting stops on bad runs.

**Files.**
- `Sources/AISidecarCLI/AnalyzeCommand.swift:68` — result discarded (`_ = try await pipeline.run(`)
- `Sources/AISidecarCLI/WriteXMPCommand.swift:246-252`, `NormalizeCommand.swift:333-339`, `ApplySessionCommand.swift:194-200` — print failure counts, exit 0
- `Sources/AISidecarCLI/CleanupCommand.swift:30-37` — throws `SidecarError` on failures (inconsistent outlier)
- New: `Sources/AISidecarCore/Support/BatchExitPolicy.swift` (Core so it is testable; CLI maps to `ExitCode`, invariant 13)

**Current behavior (verified 2026-07-08).** All four batch commands swallow the result or print a count and return normally; only `cleanup` throws. A 100%-failure `analyze` run exits 0.

```swift
// WriteXMPCommand.swift:246-252
private func writeEssentialSummary(_ report: XMPExportReport?) {
    guard let report else {
        return
    }
    let line = "XMP export complete: \(report.writtenCount) written, \(report.failedCount) failed."
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}
```

**Change.**
1. Add `BatchExitPolicy` to Core. Exit statuses are stable public behavior once shipped (treat like invariant 7; additive only): `0` success, `1` = one or more per-file failures, `130` (128+SIGINT) = interrupted. Interrupted wins over failures.

```swift
// Sources/AISidecarCore/Support/BatchExitPolicy.swift
/// Shared batch exit statuses. Values are stable once shipped: 0 success,
/// 1 per-file failures, 130 interrupted (128 + SIGINT). Add codes; never reuse.
public enum BatchExitPolicy {
    public static let failureStatus: Int32 = 1
    public static let interruptedStatus: Int32 = 130

    /// nil means exit 0.
    public static func exitStatus(failureCount: Int, interrupted: Bool) -> Int32? {
        if interrupted { return interruptedStatus }
        return failureCount > 0 ? failureStatus : nil
    }
}
```
2. `AnalyzeCommand.swift:68`: capture the result; `failureCount = result.records.filter { $0.status == .failed }.count`, `interrupted = result.interrupted`; after the summary line, `if let status = BatchExitPolicy.exitStatus(...) { throw ExitCode(status) }`.
3. `WriteXMPCommand` (both `run()` call sites at :138/:151), `NormalizeCommand` (:213/:221), `ApplySessionCommand` (:121): same, using `report.failedCount` (fall back to `report.errors.count` where the export report is nil, matching the existing summary math) plus the pipeline result's `interrupted` flag. Throw `ExitCode` *after* `writeEssentialSummary` so output is unchanged.
4. `CleanupCommand.swift:30-37`: keep the printed message, replace the thrown `SidecarError` with `throw ExitCode(BatchExitPolicy.failureStatus)` for consistency (observable exit code stays 1; the stderr error line disappears — mention in commit).
5. Document the codes in each command's `CommandConfiguration(discussion:)` and in README Troubleshooting; update `agent_docs/testing-and-verification.md`.

**Tests.** `Tests/AISidecarCoreTests/BatchExitPolicyTests.swift` (new file, one file per subject):

```swift
import XCTest
@testable import AISidecarCore

final class BatchExitPolicyTests: XCTestCase {
    func testSuccessExitsZero() {
        XCTAssertNil(BatchExitPolicy.exitStatus(failureCount: 0, interrupted: false))
    }

    func testAnyFailureExitsOne() {
        XCTAssertEqual(BatchExitPolicy.exitStatus(failureCount: 1, interrupted: false), 1)
    }

    func testInterruptionWinsOverFailures() {
        XCTAssertEqual(BatchExitPolicy.exitStatus(failureCount: 3, interrupted: true), 130)
        XCTAssertEqual(BatchExitPolicy.exitStatus(failureCount: 0, interrupted: true), 130)
    }
}
```

**Acceptance.**
- [x] Exit nonzero when any per-file failure or an interruption occurred (plan 08 verbatim)
- [x] Policy defined once and applied to all batch commands; documented in `--help` and README
- [x] `E_*` error codes untouched (invariant 7); exit codes documented as stable once shipped
- [ ] `echo $?` manual checks in the exit gate pass

**Commit.** `Exit nonzero for failed or interrupted batch runs via shared BatchExitPolicy`

### R3-2 — Make Ctrl+C responsive: check interruption between roles/attempts and cancel in-flight requests

**Goal.** Interruption is observed between roles and retry attempts and cancels the in-flight model request, and a repeated Ctrl+C can escalate to a real kill.

**Files.**
- `Sources/AISidecarCore/Pipeline/InterruptionMonitor.swift:30-53` — `signal(SIGINT, SIG_IGN)` + flag-only handler
- `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift:294-338` — flag checked only per file
- `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift:697-716` — sequential role loop, no check
- `Sources/AISidecarCore/ModelRuntime/OllamaVisionRunner.swift:345-357` — retry loop, no check

**Current behavior (verified 2026-07-08).** The monitor's flag is polled only in the per-file loop (`:295`, `:316`). `runModelRuns` iterates roles with no check, and `sendChatWithRetries` retries with no check, so a worst case of 2 roles × 3 attempts × 180 s runs to completion after Ctrl+C. SIGINT stays `SIG_IGN` forever, so repeated Ctrl+C never escalates.

```swift
// AnalyzePipeline.swift:704-706
// PW-015 requires exactly one model request in flight; keep this loop
// sequential even when render/isolation preparation has worked ahead.
for (role, derivative) in modelInputs(derivatives: derivatives, mode: configuration.mode) {
```

**Change.** (Do R3-4 first or together — cancellation propagation through the transport is shared.)
1. Plumb `interruptionMonitor` from `finishPrepared` into `runModelRuns`/`runModel`. At the top of the role loop, stop through an explicit internal interrupted outcome rather than returning partial model runs. The processing loop then writes no sidecar and emits no partial per-file progress record; the batch result and summary carry the interruption, matching the established between-files behavior. (The original plan assumed this fail-closed outcome already existed; `finishPrepared` previously wrote partial runs, so the explicit outcome is required.)
2. Runner gains a per-call interruption check: add `isInterrupted: (@Sendable () -> Bool)?` to the `analyze` signature (defaulted `nil` — mock runners unaffected). In `sendChatWithRetries`, check it (and `Task.isCancelled`, R3-4) at the top of each attempt and after each failure; when set, throw `SidecarError(code: .interrupted, stage: .model, ...)` instead of starting the next attempt.
3. Cancel in-flight requests: `AnalyzePipeline.runModel` wraps the `runner.analyze` call in a child `Task`; the pipeline registers a handler on the monitor that calls `task.cancel()`. Add to `InterruptionMonitor`:

```swift
/// Register a callback fired once when interruption is requested.
/// Fires immediately if already interrupted. Returns a removable lifetime token.
public func onInterruption(_ handler: @escaping @Sendable () -> Void) -> InterruptionRegistration
```
   (Store handlers under the existing lock; `requestInterruption()` drains them. Registrations must unregister completed requests so a long successful batch retains no historical tasks.) The transport-level task-only cancellation behavior is R3-4.
4. Escalation: in `installSignalHandlers`, when the SIGINT event handler sees `interrupted` already `true`, restore default disposition (`signal(SIGINT, SIG_DFL)`) so the *third* Ctrl+C genuinely kills the process. Second press = "cancel in-flight + arm escalation", third = kill. Account for `DispatchSourceSignal.data` so rapidly coalesced signals preserve the same sequence.

**Tests.** Extend `Tests/AISidecarCoreTests/ModelRuntimeTests.swift` (runner behavior) and `AnalyzePipelineTests.swift` (role-boundary stop):

```swift
// ModelRuntimeTests.swift
func testAnalyzeStopsRetryingWhenInterruptedBetweenAttempts() async throws {
    let transport = RecordingOllamaTransport([
        .failure(OllamaHTTPTransportError.unreachable("first")),
        .success(chatResponse(content: #"{"summary":"never reached"}"#))
    ])
    let runner = OllamaVisionRunner(transport: transport)
    let record = await runner.analyze(
        /* image/prompt/schema/runtime per existing helpers */
        options: ModelRunOptions(retryLimit: 2),
        isInterrupted: { monitor.isInterrupted }
    )
    XCTAssertEqual(record.error?.code, .interrupted)
    XCTAssertEqual(await transport.capturedRequests().count, 1)
}

// AnalyzePipelineTests.swift
func testInterruptionBetweenRolesSkipsSecondRoleAndFailsClosed() async throws {
    // mock runner flips monitor.requestInterruption() during the first role;
    // assert: one model call, no per-file record, summary interrupted, no sidecar.
}
```

**Acceptance.**
- [x] Monitor checked between roles and between retry attempts (plan 08 verbatim)
- [x] In-flight `URLSession` request cancelled on interruption (with R3-4)
- [x] Second SIGINT restores default disposition; third kills (plan 08 verbatim)
- [x] Files stay fail-closed at boundaries (existing behavior preserved)
- [ ] Manual: Ctrl+C during a batch stops within one attempt, exits 130 (R3-1)

**Commit.** `Check interruption between roles and attempts and cancel in-flight model requests`

### R3-3 — Retry classification + Ollama error bodies

**Goal.** Retry only timeouts, transport errors, and 5xx; fail fast on 4xx; surface Ollama's `{"error": ...}` body; classify malformed 200 bodies as a decode-class error retried once.

**Files.**
- `Sources/AISidecarCore/ModelRuntime/OllamaVisionRunner.swift:337-369` (`sendChatWithRetries`), `:284-291` (`requestJSON`), `:371-382` (`decodeChatResponse`)
- `Sources/AISidecarCore/ModelRuntime/OllamaHTTPTransport.swift:30-40` (`OllamaHTTPTransportError`)
- `Sources/AISidecarCore/Errors/SidecarError.swift:7-33` (additive code)

**Current behavior (verified 2026-07-08).** Any non-2xx becomes `.unreachable` and is blanket-retried, discarding the response body; malformed 200 bodies map to `E_MODEL_ENDPOINT_UNREACHABLE`.

```swift
// OllamaVisionRunner.swift:348-350
guard (200..<300).contains(response.statusCode) else {
    throw OllamaHTTPTransportError.unreachable("HTTP \(response.statusCode) from /api/chat.")
}
```

**Change.**
1. Add an additive transport case: `case clientError(Int, String)` on `OllamaHTTPTransportError` (not raw-valued; invariant 7 unaffected). Add additive `SidecarErrorCode` case `modelResponseInvalid = "E_MODEL_RESPONSE_INVALID"` — never repurpose existing values.
2. Add a body parser: `private static func ollamaErrorMessage(from data: Data) -> String?` decoding `{"error": String}`; append it to every non-2xx message (`"HTTP 400 from /api/chat: model requires more memory"`).
3. In `sendChatWithRetries`: on non-2xx, throw `.clientError(status, message)` for `400..<500` and `.unreachable` for 5xx. In the catch, `if case .clientError = error as? OllamaHTTPTransportError { throw endpointUnreachable(error) }` — i.e. fail fast, no further attempts (message carries the HTTP status + body). Timeouts/transport/5xx keep retrying as today.
4. Malformed 200: `decodeChatResponse` throws `SidecarError(code: .modelResponseInvalid, stage: .model, ...)`. In `chatResponse`, retry the request exactly once on that code (proxies truncate); second failure surfaces `E_MODEL_RESPONSE_INVALID`. Fix `requestJSON` (:290) the same way for preflight calls.
5. Add the new code to `ErrorTaxonomyTests` (stable-raw-values coverage) if that suite pins `CaseIterable` raw strings.

**Tests.** Extend `Tests/AISidecarCoreTests/ModelRuntimeTests.swift`, matching `RecordingOllamaTransport` conventions:

```swift
func testAnalyzeDoesNotRetryHTTP4xxAndIncludesOllamaErrorBody() async throws {
    let transport = RecordingOllamaTransport([
        .success(OllamaHTTPResponse(statusCode: 400,
            data: Data(#"{"error":"model requires more memory"}"#.utf8)))
    ])
    let runner = OllamaVisionRunner(transport: transport)
    let record = await runner.analyze(/* ...options: ModelRunOptions(retryLimit: 2)... */)
    XCTAssertEqual(record.error?.code, .modelEndpointUnreachable)
    XCTAssertTrue(record.error?.message.contains("model requires more memory") == true)
    let requests = await transport.capturedRequests()
    XCTAssertEqual(requests.count, 1) // the promise in testAnalyzeRetriesTimeoutsAndTransportErrorsOnly
}

func testAnalyzeRetriesHTTP5xxAndMalformed200Once() async throws {
    // 500 then success → 2 requests; malformed-200 then success → 2 requests;
    // malformed-200 twice → record.error?.code == .modelResponseInvalid
}
```

**Acceptance.**
- [x] Ollama error body included in thrown error messages (plan 08 verbatim)
- [x] Retry only timeouts, transport errors, and 5xx; fail fast on 4xx (plan 08 verbatim)
- [x] Malformed 200 → decode-class error, retried once, `E_MODEL_RESPONSE_INVALID` additive (plan 08 verbatim)
- [x] Existing `testAnalyzeRetriesTimeoutsAndTransportErrorsOnly` still green; 4xx non-retry now actually pinned

**Commit.** `Classify Ollama retries: fail fast on 4xx, surface error bodies, retry malformed 200 once`

### R3-4 — Respect task cancellation in the model runtime

**Goal.** A cancelled task stops retrying immediately and never writes a permanent failure sidecar claiming the endpoint was unreachable.

**Files.**
- `Sources/AISidecarCore/ModelRuntime/OllamaHTTPTransport.swift:66-72` — catch-all maps `CancellationError`/`URLError(.cancelled)` to `.unreachable`
- `Sources/AISidecarCore/ModelRuntime/OllamaVisionRunner.swift:345-357` — retry loop retries cancellation

**Current behavior (verified 2026-07-08).** The GUI cancel path (or any task cancellation) surfaces as `E_MODEL_ENDPOINT_UNREACHABLE`, is retried from a cancelled task, and pollutes `--existing skip` reruns with a false permanent failure sidecar.

```swift
// OllamaHTTPTransport.swift:68-72
} catch let error as URLError where error.code == .timedOut {
    throw OllamaHTTPTransportError.timeout(error.localizedDescription)
} catch {
    throw OllamaHTTPTransportError.unreachable(error.localizedDescription)
}
```

**Change.**
1. Transport: add before the catch-all — `catch is CancellationError { throw CancellationError() }` and `catch let error as URLError where error.code == .cancelled { throw CancellationError() }` — cancellation passes through unclassified.
2. Runner `sendChatWithRetries`: `try Task.checkCancellation()` at the top of each attempt; in the catch, `if error is CancellationError { throw error }` (no classification, no further attempts).
3. Runner `analyze` is non-throwing (returns `ModelRunRecord`); map cancellation to a record with `SidecarError(code: .interrupted, stage: .model, message: "Model request cancelled.", recoverable: true)` — `E_INTERRUPTED` already exists, no new raw value.
4. `AnalyzePipeline.finishPrepared`: when a run record's error code is `.interrupted`, treat the file exactly like the between-files interruption path — mark the run interrupted, do **not** write a failure sidecar (fail-closed, rerunnable).

**Tests.** Extend `Tests/AISidecarCoreTests/ModelRuntimeTests.swift` + `AnalyzePipelineTests.swift`:

```swift
func testAnalyzeMapsCancellationToInterruptedWithoutRetrying() async throws {
    let transport = RecordingOllamaTransport([
        .failure(CancellationError()),
        .success(chatResponse(content: #"{"summary":"never reached"}"#))
    ])
    let runner = OllamaVisionRunner(transport: transport)
    let record = await runner.analyze(/* ... ModelRunOptions(retryLimit: 2) ... */)
    XCTAssertEqual(record.error?.code, .interrupted)
    XCTAssertEqual(await transport.capturedRequests().count, 1)
}

// AnalyzePipelineTests.swift
func testCancelledModelRunWritesNoFailureSidecarAndRecordsInterruption() async throws {
    // mock runner returning an .interrupted record; assert no .ai.json on disk,
    // result.interrupted == true, no .failed record for that file.
}
```

**Acceptance.**
- [x] Cancellation rethrown without writing a failure sidecar; run records interruption (plan 08 verbatim)
- [x] `Task.isCancelled` checked in the retry loop (plan 08 verbatim)
- [x] Rerun with `--existing skip` after a GUI cancel re-attempts the file

**Commit.** `Propagate task cancellation through the model runtime instead of writing failure sidecars`

### R3-5 — Configurable model timeout/retry

**Goal.** `model_timeout_seconds` (and `model_retry_limit`) are configurable through the full precedence chain instead of hard-coded 180 s / 2 retries.

**Files.**
- `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift:725-727` — hard-coded `ModelRunOptions.default`
- Template chain: `Sources/AISidecarCore/Configuration/AppConfig.swift:11/65/237/317`, `ConfigurationResolver.swift:259` (`AISIDECAR_MODEL_KEEP_ALIVE`), `RunConfiguration.swift:56/170/197`, `Sources/AISidecarCLI/SharedOptions.swift:140-160`
- `aisidecar.config.example.jsonc`; GUI Settings sheet (M8a write-through pattern via `ConfigFileEditor`)

**Current behavior (verified 2026-07-08).**

```swift
// AnalyzePipeline.swift:725-727
var options = ModelRunOptions.default
options.keepAlive = configuration.modelKeepAlive
options.responseRepairAttempts = configuration.modelResponseRepairAttempts
```

**Discrepancy:** plan 08 says "only keep-alive plumbed"; `modelResponseRepairAttempts` is also plumbed (line 727). Also, keep-alive has **no CLI flag** in `SharedOptions` (config + env + overrides only), so `--model-timeout` adds a flag where the template has none — follow `--model-response-repair-attempts` (`SharedOptions.swift:134-135`) for the flag itself.

**Change.**
1. `AppConfig`: add `modelTimeoutSeconds: Double?` (`model_timeout_seconds`) and `modelRetryLimit: Int?` (`model_retry_limit`) — decode/encode-if-present like `modelKeepAlive` (:237/:317).
2. `ConfigurationResolver`: env keys `AISIDECAR_MODEL_TIMEOUT_SECONDS`, `AISIDECAR_MODEL_RETRY_LIMIT` beside :259; merge in the same CLI > env > file > default order (invariant 9); validate `timeout > 0`, `retryLimit >= 0` → `SidecarError.configInvalid` otherwise.
3. `RunConfigurationOverrides` + `ResolvedRunConfiguration`: new fields with defaults `ModelRunOptions.default.timeoutSeconds` / `.retryLimit`; snake_case coding keys (`model_timeout_seconds`, `model_retry_limit`).
4. `SharedOptions`: `@Option(help: "Model request timeout in seconds.") var modelTimeout: Double?` and `@Option(help: "Model request retry limit for retryable failures.") var modelRetryLimit: Int?`; wire into `overrides` in `SharedOptions.swift` and the duplicated analyze-mode builders in `WriteXMPCommand.swift` and `NormalizeCommand.swift`; add both fields to their invocation validators so model-free modes reject them.
5. `AnalyzePipeline.runModel` (:725-727): `options.timeoutSeconds = configuration.modelTimeoutSeconds; options.retryLimit = configuration.modelRetryLimit`.
6. Add both keys to `aisidecar.config.example.jsonc` with comments; add to the GUI Settings sheet per the M8a `ConfigFileEditor.merge` write-through pattern. Apply the configured timeout to Ollama preflight requests as well as `/api/chat`.

**Tests.** Extend `Tests/AISidecarCoreTests/ConfigResolutionTests.swift` per the existing keep-alive precedence pattern (asserted at :15/:85/:185/:338):

```swift
func testModelTimeoutAndRetryLimitResolutionPrecedence() throws {
    // built-in default: resolved.modelTimeoutSeconds == 180, modelRetryLimit == 2
    // config file value overrides default; AISIDECAR_MODEL_TIMEOUT_SECONDS overrides file;
    // CLI override wins over env (mirror the modelKeepAlive assertions).
}

func testModelTimeoutRejectsNonPositiveValues() throws {
    // "0" and "-5" via env → SidecarError code == .configInvalid
}
```

**Acceptance.**
- [x] Full chain: `AppConfig` + example JSONC, `AISIDECAR_*` env, `--model-timeout` flag, `ResolvedRunConfiguration`, GUI Settings (plan 08 verbatim)
- [x] Resolver precedence tests per the existing pattern (plan 08 verbatim; invariant 9)
- [x] `purge` still resolves without model config validity (invariant 9, second clause)

**Commit.** `Plumb model_timeout_seconds and model_retry_limit through the config chain`

### R3-6 — Recursive scans must record unreadable subdirectories

**Goal.** Permission-denied subtrees produce per-directory failure records instead of a silently successful run with a coverage gap.

**Files.**
- `Sources/AISidecarCore/FileScanning/ImageScanner.swift:133-137` — `enumerator(at:...)` without `errorHandler`
- `Sources/AISidecarCore/FileScanning/ImageScanner.swift:153-157` — non-recursive `contentsOfDirectory` throws raw `CocoaError` (R3-6b)
- `Sources/AISidecarCore/Sidecars/RawJSONSidecarInputResolver.swift:240-244` — same enumerator gap

**Current behavior (verified 2026-07-08).**

```swift
// ImageScanner.swift:133-137
guard let enumerator = fileManager.enumerator(
    at: root,
    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
    options: [.skipsPackageDescendants]
) else {
```

`FileManager` invokes a nil `errorHandler` as "continue silently" — unreadable subtrees vanish. The non-recursive branch (`:153-157`) throws the raw Cocoa error unwrapped, unlike the recursive branch's `validationError(...)`.

**Change.**
1. `ImageScanner.discoverDirectoryContents`: pass `errorHandler: { url, error in ... }` that appends `ScanErrorRecord(path: url.path, relativePath: relativePath(for: url, root: root), error: validationError("Unable to read directory during scan: \(url.path): \(error.localizedDescription)"))` to `errors` and returns `true` (continue). Capture `errors` via a local reference box if the `Sendable` checker complains (enumeration is synchronous).
2. R3-6b: wrap `:153-157` in do/catch and rethrow as `validationError("Unable to read input folder: \(root.path): ...")` to match the recursive branch (`E_VALIDATION_FAILED`; no new codes).
3. `RawJSONSidecarInputResolver.candidateSidecars`: same `errorHandler`, recording an input-failure record per failed directory (the resolver's existing failure record type) and continuing.

**Tests.** Extend `Tests/AISidecarCoreTests/ScannerTests.swift` and `RawJSONSidecarInputResolverTests.swift` (temp-dir helpers already exist; macOS-only, no `#if os` needed):

```swift
func testRecursiveScanRecordsUnreadableSubdirectoryAndContinues() throws {
    let root = try temporaryDirectory()
    _ = try writeFile("Top.NEF", data: Data("raw".utf8), in: root)
    let locked = root.appendingPathComponent("locked")
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    _ = try writeFile("Hidden.NEF", data: Data("raw".utf8), in: locked)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
    try XCTSkipIf(getuid() == 0, "chmod 000 is not enforced for root")

    let result = try ImageScanner().scan(inputPath: root.path, recursive: true, identityPolicy: .fast)
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.errors.contains { $0.path == locked.path && $0.error.code == .validationFailed })
}

func testNonRecursiveUnreadableFolderThrowsSidecarError() throws {
    // chmod 000 the root itself; XCTAssertThrowsError asserting SidecarError.code == .validationFailed
}
```

**Acceptance.**
- [x] `errorHandler` records a `ScanErrorRecord` (scanner) / input-failure record (resolver) per failed directory and continues (plan 08 verbatim)
- [x] R3-6b: non-recursive unreadable-folder throw wrapped as `validationError` (plan 08 verbatim)
- [x] chmod-000 fixture tests skip under root (plan 08 verbatim)

**Commit.** `Record unreadable subdirectories as scan failures instead of silently skipping them`

### R3-7 — Stop the pipeline's own artifacts from poisoning reruns

**Goal.** Rerunning `analyze` over a folder containing our own progress/summary/report artifacts must not produce `E_UNSUPPORTED_FORMAT` failure records.

**Files.**
- `Sources/AISidecarCore/FileScanning/ImageScanner.swift:280-299` — `shouldIgnore` covers only dot-files, `._*`, `.ai.json`, `.xmp`
- `Sources/AISidecarCore/Cleanup/ArtifactCleanup.swift:154-193` — `classify(fileName:)` already encodes every owned pattern
- `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift:206-208` — `clearDerivativeCacheAfterSuccess` gated on a fully successful run

**Current behavior (verified 2026-07-08).** `batch-progress-*.jsonl`, `batch-summary-*.json`, and all report/summary artifacts written into the scan root become permanent failed records on every rerun; `completedSuccessfully` then never fires, so the after-success cache clear (`:206-208`) is dead.

```swift
// ImageScanner.swift:292-298
let lowercasedName = fileName.lowercased()
return lowercasedName == ".ds_store"
    || lowercasedName.hasPrefix("._")
    || lowercasedName.hasSuffix(".ai.json")
    || lowercasedName.hasSuffix(".xmp")
```

**Change.**
1. Append to `shouldIgnore` (:298): `|| ArtifactCleanup.classify(fileName: fileName) != nil` — one recognizer, write side and ignore side cannot drift (same rationale as the `ArtifactNames` doc comment).
2. Also ignore the diagnostic export manifest (`model-input-export-*.json`, `ModelInputExportPipeline.swift:400`) — `classify` deliberately excludes it (cleanup must not delete diagnostics, invariant 6), so match it directly in `shouldIgnore` with the literal prefix + `.json` suffix, or add a non-deletable `ArtifactNames.modelInputExportManifestPrefix` constant used by both.
3. No change to `RawJSONSidecarInputResolver` needed — its `shouldIgnore` only feeds `.ai.json` selection; verify while there.

**Tests.** Extend `Tests/AISidecarCoreTests/ScannerTests.swift`:

```swift
func testScanIgnoresOwnedRunArtifacts() throws {
    let root = try temporaryDirectory()
    _ = try writeFile("Bird.NEF", data: Data("raw".utf8), in: root)
    // one filename per owned artifact kind, plus the session + export-manifest exceptions:
    // batch-progress-*.jsonl, batch-summary-*.json, xmp-export-{progress,report,summary}-*,
    // normalization-{progress,report,summary,session,apply-*}-*, model-input-export-*.json
    for name in ownedArtifactFixtureNames {
        _ = try writeFile(name, data: Data("{}".utf8), in: root)
    }
    let result = try ImageScanner().scan(inputPath: root.path, recursive: false, identityPolicy: .fast)
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.errors.isEmpty)
}
```

(Note `normalization-session-*` files: `classify` recognizes prefixes via `ArtifactNames` but has **no** `normalizationSessionPrefix` branch — sessions are deliberately not cleanup-deletable. The scanner must still ignore them; cover via a direct prefix check like the export manifest. **Discrepancy:** plan 08 implies `classify` covers all owned patterns; sessions and export manifests are exceptions.)

**Acceptance.**
- [x] Scan of a folder containing each owned artifact type → no failure records (plan 08 verbatim)
- [x] `clearDerivativeCacheAfterSuccess` fires again on a clean rerun over a previously-analyzed folder
- [x] `cleanup` scope unchanged (invariant 6) — ignoring ≠ deleting

**Commit.** `Ignore owned run artifacts during scans so reruns stop reporting them as failures`

### R3-8 — Filesystem-portable artifact timestamps

**Goal.** New artifact filenames use a colon-free timestamp (plus a de-collision suffix) so runs on exFAT/FAT32/SMB volumes don't abort at artifact creation; readers keep accepting old names.

**Files.**
- `Sources/AISidecarCore/Support/Timestamp.swift:11-15` — `internetDateTime` emits `2026-07-07T18:00:00Z` (colons)
- Filename call sites: `AnalyzePipeline.swift:106-113/787`, `AnalyzeShellPipeline.swift:92/220`, `XMPExportPipeline.swift:627/652`, `ModelInputExportPipeline.swift:400/697`
- `ArtifactNames.swift`, `ArtifactCleanup.swift:154-193` (readers)

**Current behavior (verified 2026-07-08).**

```swift
// Timestamp.swift:11-15
public static func internetDateTime(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
```

Every artifact filename embeds `:`; `ProgressLog`/`JSONLWriter` creation fails on filesystems that forbid colons, aborting the whole run. Same-second runs also collide (`AnalyzePipeline.swift:106-113` derives all names from one `runStartedAt`).

**Discrepancy:** plan 08 says to update `ArtifactNames` patterns and `ArtifactCleanup.classify` to accept both forms — in current source both match by *prefix + suffix only* and never parse the timestamp, so old and new names are recognized with **zero reader changes**. Only `Timestamp`, the four `timestampString` call sites, golden tests, and docs change. `shouldIgnore` (post-R3-7) is likewise prefix/suffix-based.

**Maintainer decision (2026-07-10): Option A** — new filename timestamp format:
- **Option A** `2026-07-07T180000Z` (drop colons only): visually closest to today's names, sorts correctly alongside old ones.
- **Option B** `20260707-180000` (compact basic): shortest, but sorts *before* all old names and reads worse.
- **Recommendation: Option A**, plus R3-8b suffix → `batch-progress-2026-07-07T180000Z-a3f2.jsonl`.

**Change.**
1. Add `Timestamp.filenameSafe(_ date: Date) -> String` implementing the chosen format (keep `internetDateTime` untouched — provenance fields *inside* artifacts stay ISO-8601; only filenames change).
2. Switch the four private `timestampString(for:)` helpers to `Timestamp.filenameSafe`.
3. R3-8b: append a 4-char lowercase-hex random suffix at name-construction time (one value per run, shared by that run's progress + summary names so they stay visually paired). Inject via the pipelines' existing `now`/seam pattern so tests stay deterministic (fixed generator in tests, invariant 12).
4. Golden/report tests asserting artifact names will diff: **golden diffs are deliberate — update fixtures explicitly and call it out in the PR** (repo test convention). Update `agent_docs/testing-and-verification.md` and README examples showing artifact names.

Implementation audit correction: normalization session/report/summary/progress paths and XMP backup names also used
colon-bearing timestamps even though the file list above omitted them. R3-8 covers those producers too; otherwise
normalization and backup-and-merge could still fail on the target filesystems. No serialized golden fixture contained
an artifact path, so focused report/path assertions were deliberately updated instead of changing unrelated fixtures.

**Tests.** `Tests/AISidecarCoreTests/TimestampTests.swift` (new) + touched golden suites:

```swift
import XCTest
@testable import AISidecarCore

final class TimestampTests: XCTestCase {
    func testFilenameSafeContainsNoReservedCharacters() {
        let value = Timestamp.filenameSafe(Date(timeIntervalSince1970: 1_782_000_000))
        XCTAssertFalse(value.contains(":"))
        XCTAssertTrue(value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "T" })
    }

    func testInternetDateTimeUnchangedForProvenanceFields() {
        XCTAssertEqual(
            Timestamp.internetDateTime(Date(timeIntervalSince1970: 0)),
            "1970-01-01T00:00:00Z"
        )
    }

    func testCleanupClassifiesBothOldAndNewArtifactNames() {
        XCTAssertEqual(ArtifactCleanup.classify(fileName: "batch-progress-2026-07-07T18:00:00Z.jsonl"), .analyzeProgressLog)
        XCTAssertEqual(ArtifactCleanup.classify(fileName: "batch-progress-2026-07-07T180000Z-a3f2.jsonl"), .analyzeProgressLog)
    }
}
```

**Acceptance.**
- [x] New files use the filesystem-safe form; readers keep recognizing old names (plan 08 verbatim)
- [x] Additive pattern change only; invariant 7 respected (plan 08 verbatim)
- [x] R3-8b: same-second runs fully de-collided by suffix (plan 08 verbatim)
- [x] Golden tests updated deliberately and called out in the PR

**Commit.** `Use filesystem-safe timestamps plus a run suffix in artifact filenames`

### R3-9 — Source-hash recheck must not vanish on before-hash failure

**Goal.** A source whose before-hash cannot be computed still gets an `XMPSourceHashCheck` record and fails verification, instead of silently losing its invariant-4 recheck.

**Files.**
- `Sources/AISidecarCore/Pipeline/XMPExportPipeline.swift:407-417` (`sourceHashesBeforeWrite`), `:419-462` (`sourceHashChecks` iterates `before.keys`)
- `Sources/AISidecarCore/Reporting/XMPExportReport.swift:4-9` — `XMPSourceHashCheck.beforeSHA256` already optional

**Current behavior (verified 2026-07-08).**

```swift
// XMPExportPipeline.swift:409-414
for path in selectedSourcePaths(for: plan) {
    hashes[path] = try? SourceIdentityCalculator.compute(
        for: URL(fileURLWithPath: path),
        policy: .sha256,
        fileManager: fileManager
    ).sha256
```

Assigning `nil` through a dictionary subscript **removes the key**, and `sourceHashChecks(afterWriteFor:)` iterates `before.keys` — the failed path gets no check and no error.

**Change.**
1. Change `sourceHashesBeforeWrite` to return `[String: String?]` and use `hashes.updateValue(try? ..., forKey: path)` so failed paths keep a `nil` entry (the type already models nil-before).
2. In `sourceHashChecks`, `let beforeHash = before[path] ?? nil`; when `beforeHash == nil`, append a check with `beforeSHA256: nil, unchanged: false` and a `validationFailed` error naming the path ("Unable to read source image before XMP export"), and append to `errors` so it is treated as a failed verification.
3. Policy: a nil-before check **fails the target** (conservative default, NFR "prefer safety") — the existing error-propagation path that already turns `sourceHashChecks` errors into a failed `targetReport` handles this once the error is emitted.

**Tests.** Extend the existing XMP export suite (`NoXMPRegressionTests` is the wrong subject; use the export pipeline tests — `Tests/AISidecarCoreTests/NormalizeAndWritePipelineTests.swift` or the write-xmp pipeline suite that already builds plans, matching its fixture helpers):

```swift
func testUnreadableSourceAtExportStartRecordsFailedHashCheckAndFailsTarget() throws {
    // build a plan whose selected source file is chmod-000 (restore in defer;
    // XCTSkipIf(getuid() == 0)); run the export;
    let check = try XCTUnwrap(report.targetReports.first?.sourceHashChecks.first)
    XCTAssertNil(check.beforeSHA256)
    XCTAssertFalse(check.unchanged)
    XCTAssertNotNil(check.error)
    XCTAssertEqual(report.targetReports.first?.status, .failed)
}
```

**Acceptance.**
- [x] Check entry recorded with nil `beforeSHA256` and the error (plan 08 verbatim)
- [x] Treated as failed verification for reporting; target fails (plan 08 verbatim, conservative default)
- [x] Invariant 4 guard chain unchanged otherwise

**Commit.** `Record failed before-hash computations as failed XMP source-hash checks`

### R3-10 — Crash-hardening `Dictionary(uniqueKeysWithValues:)` on user-editable inputs

**Goal.** Hand-edited or corrupt session/sidecar JSON with duplicate keys produces a structured error naming the offending key instead of `fatalError`.

**Files.**
- `Sources/AISidecarCore/Pipeline/ApplySessionPipeline.swift:248-251` — `groupsByTarget` / `storedByTarget` from session JSON
- `Sources/AISidecarCore/Metadata/XMPChangePlan.swift:286-288` — `extractionBySidecar`
- `Sources/AISidecarCore/Normalization/CandidateObservation.swift:202-209` — `assetIDBySidecarPath` / `groupIDByAssetID`

**Current behavior (verified 2026-07-08).**

```swift
// ApplySessionPipeline.swift:248-251
let groupsByTarget = Dictionary(uniqueKeysWithValues: groups.map { ($0.targetRelativePath, $0) })
let storedByTarget = Dictionary(uniqueKeysWithValues: storedWritePlans.map {
    ($0.xmpChangePlan.targetRelativePath, $0)
})
```

A duplicated `target_relative_path` in an edited session document crashes the process. Same trap at the other two sites.

**Change.**
1. Add one shared helper (e.g. in `Sources/AISidecarCore/Support/`):

```swift
/// Build a lookup, throwing a structured error on duplicate keys instead of trapping.
func uniqueLookup<K: Hashable, V>(
    _ pairs: [(K, V)],
    onDuplicate: (K) -> SidecarError
) throws -> [K: V] {
    var result: [K: V] = [:]
    result.reserveCapacity(pairs.count)
    for (key, value) in pairs {
        guard result.updateValue(value, forKey: key) == nil else {
            throw onDuplicate(key)
        }
    }
    return result
}
```
2. `ApplySessionPipeline`: both dictionaries via the helper throwing `SidecarError(code: .sessionStale, stage: .normalize, message: "Duplicate target in session document: \(key)", recoverable: false)`; `annotateWritePlans` becomes `throws` (single internal caller).
3. `CandidateObservationBuilder.build`: helper with `.validationFailed` naming the duplicate sidecar path / the asset ID present in two groups; `build` becomes `throws` (callers adapt — mechanical).
4. `XMPChangePlanner.plan` (`XMPChangePlan.swift:286`) is the batch-tolerant surface: rather than failing the whole plan, detect duplicates first and record an `XMPChangePlanInputFailure` (`validationFailed`, "Duplicate source sidecar in input batch") for the extras, keeping the first deterministically — matches the planner's existing per-input failure model at `:290-296`.

**Tests.** Extend `Tests/AISidecarCoreTests/ApplySessionPipelineTests.swift`, `NormalizedXMPChangePlanTests.swift` (or `XMPChangePlan`'s suite), and the observation-builder suite, each with a malformed fixture:

```swift
func testDuplicateSessionTargetThrowsSessionStaleNamingTheKey() throws {
    // session JSON fixture with two groups sharing target_relative_path "Birds/A.xmp"
    XCTAssertThrowsError(try pipeline.run(/* ... */)) { error in
        let sidecarError = error as? SidecarError
        XCTAssertEqual(sidecarError?.code, .sessionStale)
        XCTAssertTrue(sidecarError?.message.contains("Birds/A.xmp") == true)
    }
}
```

**Acceptance.**
- [ ] `Dictionary(_:uniquingKeysWith:)`-style explicit duplicate detection throwing `validationFailed`/`sessionStale` with the offending key named (plan 08 verbatim)
- [ ] Malformed session fixtures for each site (plan 08 verbatim)
- [ ] No new error codes; existing codes reused appropriately (invariant 7)

**Commit.** `Replace trapping uniqueKeysWithValues lookups with structured duplicate-key errors`

### R3-11 — Batch: remaining lows (one commit each, optional within R3)

**Goal.** Six independent low-severity fixes; each is one small commit, individually deferrable, listed with verified pointers.

**R3-11a — Pre-scan failure must not enable sidecar deletion.**
`AnalyzeAndXMPPipeline.swift:51-53` — `(try? plannedRawSidecarPaths(...)) ?? []` means a failed pre-scan yields an *empty* preexisting set, so `removeNewRawSidecars` (`:171-178`, `try? fileManager.removeItem` swallows failures too) can delete a pre-existing user `.ai.json` under `--existing overwrite`. Mirror: `AnalyzeAndNormalizePipeline.swift:69-71/217-224`. Fix: do/catch the pre-scan; on failure set a `preScanFailed` flag that skips `removeNewRawSidecars` entirely (fail toward keeping files) and log a warning; log each removal failure instead of `try?`. Test (`AnalyzeAndXMPPipelineTests.swift`): failing pre-scan seam → pre-existing `.ai.json` survives.
**Commit.** `Keep raw sidecars when the no-ai-json pre-scan fails`

**R3-11b — Symlink consistency.**
`ImageScanner.swift:181` (`guard isRegularFile(candidate) else { return false }`) silently drops symlinks during folder scans, while direct-file input (`:110-122`) processes the link and `:301-303`'s `resourceValues` stats the link itself — skewing the `fast` identity digest. Fix: folder scan emits a recoverable `ScanErrorRecord` (`validationFailed`, "Symbolic link skipped") for symlinks; direct-file input resolves `URL(fileURLWithPath:).resolvingSymlinksInPath()` before stat so `fast` identity reflects the target. Test (`ScannerTests.swift`): symlink in folder → error record; symlinked direct file → same identity as target.
**Commit.** `Record symlink skips in folder scans and stat symlink targets for direct input`

**R3-11c — Unicode-normalization collision folding.**
`SidecarNaming.swift:90` and `ModelInputExportPipeline.swift:762` group collision keys with `.lowercased()` only — NFC vs NFD spellings of the same name (common after copying between APFS/network volumes) escape collision detection. Fix: fold with `.precomposedStringWithCanonicalMapping.lowercased()` at both sites. Test (`SidecarNamingTests.swift`, `ModelInputExportPipelineTests.swift`): `"Café.NEF"` in NFC + NFD → classified as one collision.
**Commit.** `Fold Unicode NFC in sidecar and export collision keys`

**R3-11d — Distinguish unreadable-vs-absent config.**
`ConfigFileEditor.swift:22` — `fileManager.contents(atPath:)` returns nil for *both* absent and unreadable files, so an edit to an unreadable config silently rewrites it containing only the changed keys; a malformed-JSON parse error also propagates as a raw `NSError` instead of `E_CONFIG_INVALID`. Fix: if `fileExists` but `contents` is nil → throw `SidecarError.configInvalid("Config file exists but cannot be read: ...")`; wrap `JSONSerialization` parse throws in `.configInvalid` (keep the existing non-object guard's message; move it to `.configInvalid` too for consistency — note in commit that its code changes from `E_VALIDATION_FAILED`, an intentional correction, both codes pre-exist). Test (`ConfigFileEditorTests.swift`): chmod-000 config → throws, file unmodified; garbage JSON → `.configInvalid`.
**Commit.** `Fail config edits safely on unreadable or malformed config files`

**R3-11e — Probe errors vs. not-vision-capable.**
`OllamaVisionRunner.swift:262-276` — `try? await showModel(...)` folds probe *failures* into "not vision-capable", so the `modelTagNotFound` diagnostic (`:522-530`) can falsely claim "Installed vision-capable tags: none" during a flaky preflight. Fix: count probe failures separately inside the (deliberately serial — invariant 15) loop and append to the diagnostic: "N installed tag(s) could not be probed". No concurrency change. Test (`ModelRuntimeTests.swift`): tags response with one good vision tag + one `/api/show` failure → prepare error message mentions the unprobed count.
**Commit.** `Distinguish probe failures from non-vision tags in the model-tag diagnostic`

**R3-11f — Orphaned atomic-writer temps.**
`AtomicFileWriter` temps are `.<base>.<UUID>.tmp` / `.<base>.<UUID>.<ext>` siblings (verified `AtomicFileWriter.swift:61-70`); a crash strands them and `ArtifactCleanup.classify` (`:154-193`) never matches, so `cleanup`/`purge` can't remove them. Fix: additive kind `atomicWriterTemp = "atomic_writer_temp"`; `cleanupCandidates` currently uses `.skipsHiddenFiles` (`:201/:210`) so dot-prefixed temps are never even enumerated — drop that option and keep ignoring hidden files *except* names matching the temp regex (`^\..+\.[0-9A-Fa-f-]{36}\.[^.]+$`) whose modification date is older than 1 day (age gate; never remove young ones — in-flight). Test (`ArtifactCleanupTests.swift`): fresh temp untouched; 2-day-old temp classified and removed; `.DS_Store` and other hidden files untouched (invariant 6).
**Commit.** `Teach cleanup to remove day-old orphaned atomic-writer temp files`

**Acceptance (per sub-item).**
- [ ] Each lands as its own commit with its own focused test (invariant 16)
- [ ] a: pre-scan failure aborts the remove-new-sidecars cleanup; deletion failures logged (plan 08 verbatim)
- [ ] b: recoverable record for folder-scan symlinks; direct input stats the target (plan 08 verbatim)
- [ ] c: NFC folded in collision keys (plan 08 verbatim)
- [ ] d: unreadable-vs-absent distinguished; parse errors → `E_CONFIG_INVALID` (plan 08 verbatim)
- [ ] e: probe errors distinguished in the `modelTagNotFound` diagnostic (plan 08 verbatim)
- [ ] f: age-gated temp cleanup; young temps never removed (plan 08 verbatim)

### R3 exit gate

1. `swift test` green (all suites; new fixtures deterministic and offline — invariant 12); `swift build --product CupricAspect` (R3-5 Settings work compiles).
2. CLI help checks (all nine, per `agent_docs/testing-and-verification.md`): `swift run aisidecar --help`, plus `analyze`, `write-xmp`, `normalize`, `apply-session`, `explain-session`, `benchmark`, `purge`, `cleanup` `--help` — confirm exit-code documentation (R3-1) and `--model-timeout`/`--model-retry-limit` (R3-5) appear.
3. Offline smoke checks: `swift run aisidecar benchmark --self-test`; `swift run aisidecar benchmark --spec source-identity-fast --max-hash-copies 1 --output-dir <tmp>`; `swift run aisidecar analyze <folder> --recursive --dry-scan`; `swift run aisidecar cleanup <folder> --recursive --dry-run`.
4. R3-specific manual verification:
   - `swift run aisidecar analyze <folder-with-one-unsupported-file> --dry-scan; echo $?` → dry-scan unaffected; then a real failed batch (unreachable endpoint) → `echo $?` prints `1`.
   - Ctrl+C during a dry-run batch and during a live batch: prompt returns within one attempt, `echo $?` prints `130`; second Ctrl+C arms escalation, third kills.
   - Rerun `analyze` over a folder already containing `batch-progress-*` / `batch-summary-*` artifacts → summary shows zero failures (R3-7).
   - If an exFAT-formatted volume (SD card) is available: `analyze` with no `--output-dir` writes artifacts successfully with the new names (R3-8).
   - `AISIDECAR_MODEL_TIMEOUT_SECONDS=1 swift run aisidecar analyze <image> ...` against a live model → fast `E_MODEL_TIMEOUT` (R3-5).
5. Deliberate observable-behavior updates shipped alongside code: README Troubleshooting (exit codes), `agent_docs/testing-and-verification.md`, `aisidecar.config.example.jsonc` (R3-5 keys), golden fixtures (R3-8) — each called out in its commit/PR.

## Milestone R4 — Normalization and XMP semantic fixes

R4 covers plan 08 §5: semantic corrections in the Phase 3 normalization pipeline and the XMP export
seam (findings XMP M1–M4, XMP L2/L3/L4/L6, Core #17, CLI #6/#7). R4 runs after R3; the two are
independent and may swap wholesale, but must not interleave. Items run R4-1 → R4-6 in order.
R4-6 subsumes efficiency-plan items P2 and P3 (`agent_docs/05-efficiency-improvement-plan.md`) as
one `DerivativeCache` manifest redesign — do not schedule P2/P3 separately later. The normative
spec for normalization semantics is `agent_docs/03-cli-normalized-batch-tagger-requirements.md`.

### R4-1 — File-list entries outside the list directory collapse into one XMP group

**Goal.** Two same-base-name images from different directories in an absolute-path file list must
resolve to two normalization groups and two XMP targets, never one merged pair.

**Files.**
- `Sources/AISidecarCore/Normalization/NormalizationInputResolver.swift:532-543` (`relativePath(for:root:)`)
- `Sources/AISidecarCore/Normalization/NormalizationInputResolver.swift:412-418` (`groupKey(for:)`); grouping at `:374`; entry construction at `:474-483`

**Current behavior (verified 2026-07-08).** `parseFileList` records
`relativePath(for: url, root: baseURL)` where `baseURL` is the file-list's directory (FR3-CLI-008).
For an absolute entry outside that directory the fallback returns only the file name, so two
`IMG_0001.JPG` from different directories both get `sourceRelativePath = "IMG_0001.JPG"`;
`groupKey(for:)` derives `directory = ""` for both and `buildGroups` collapses them into one
RAW+JPEG-style group — keywords union into a single `.xmp` beside whichever member sorts first, the
other image gets nothing, and `--output-dir` targets collide on `IMG_0001.xmp`.

```swift
// NormalizationInputResolver.swift:538
guard path.hasPrefix(rootPath) else {
    return url.lastPathComponent          // <- out-of-root entries lose their directory
}
```

**Change.**
1. Replace the fallback with the full standardized absolute path: `return path`. `groupKey(for:)`
   splits on `/` omitting empties, so an out-of-root asset gets a unique non-empty directory
   component (e.g. `Users/ron/other-shoot`) — never the empty-string directory.
2. Verify downstream consumers: beside-source XMP targets come from the resolved source-image path
   (`NormalizedXMPChangePlanner.swift:271-281` uses `targetRelativePath` only as fallback), so XMP
   still lands beside each image; in `--output-dir` mode the mirrored subpath removes today's
   silent collision. `AssetAffinityInputExtractor` relative-directory evidence improves (same-real-
   directory out-of-root files now share directory evidence instead of all sharing `""`).
3. In-root entries, folder, and `--from-json` workflows are untouched.

Spec note: FR3-031 pins same-base-name grouping to Phase 2 semantics (same directory + basename);
merging cross-directory files was never specified — this is a bug fix, not a spec change. Sessions
will record the full path as `source_relative_path` for out-of-root entries; sessions already store
exact source paths (FR3-AFF-021 allows), so no new privacy surface.

**Tests.** `Tests/AISidecarCoreTests/FileListInputResolverTests.swift` (conventions:
`temporaryDirectory()`, `writeTestImage(_:in:)`):

```swift
func testAbsoluteFileListEntriesOutsideListDirectoryStayInSeparateGroups() throws {
    let root = try temporaryDirectory()
    let elsewhere = try temporaryDirectory()
    _ = try writeTestImage("IMG_0001.JPG", in: root)
    _ = try writeTestImage("IMG_0001.JPG", in: elsewhere)
    let list = root.appendingPathComponent("images.txt")
    try "IMG_0001.JPG\n\(elsewhere.appendingPathComponent("IMG_0001.JPG").path)\n"
        .write(to: list, atomically: true, encoding: .utf8)

    let batch = try NormalizationInputResolver().resolve(
        mode: .fileList(path: list.path), configuration: .builtInDefaults
    )

    XCTAssertEqual(batch.sameBaseNameGroups.count, 2)
    XCTAssertEqual(Set(batch.sameBaseNameGroups.map(\.targetRelativePath)).count, 2)
    XCTAssertEqual(batch.sameBaseNameGroups.map(\.memberAssetIDs.count), [1, 1])
}
```

**Acceptance.**
- [ ] `FileListInputResolverTests` gains an out-of-root absolute-path case asserting two separate groups/targets (plan 08 verbatim).
- [ ] Out-of-root RAW+JPEG in the *same* external directory still pairs.
- [ ] Existing file-list tests (relative paths, duplicates, comments) unchanged and green.

**Commit.** `Fix file-list grouping for entries outside the list directory`

### R4-2 — `user_only`/`withhold` session context blocked exactly where the model agreed

**Goal.** Explicit user session context must apply to an asset even when a withheld machine
decision for the same canonical path exists on that asset (FR3-003k, FR3-011b).

**Files.**
- `Sources/AISidecarCore/Normalization/BatchConsensusEngine.swift:243-289` (`applySessionContext`); skip at `:270`

**Current behavior (verified 2026-07-08).** The skip fires for *any* decision with the same
`(assetID, canonicalPath)`, regardless of status. A direct model observation of a `user_only` entry
produces a *withheld* decision (FR3-011b), which then blocks the accepted user-context decision —
`--session-event "Migration"` fails to apply precisely on assets where the model also said
"migration".

```swift
// BatchConsensusEngine.swift:270
if decisions.contains(where: { $0.assetID == assetID && $0.canonicalPath == canonicalPath }) {
    continue
}
```

**Change.**
1. Skip only when the existing decision already exports:

```swift
// A withheld/skipped machine decision (e.g. a direct user_only observation,
// FR3-011b) must not block explicit user session context (FR3-003k).
if decisions.contains(where: {
    $0.assetID == assetID && $0.canonicalPath == canonicalPath && $0.status == .accepted
}) {
    continue
}
```

2. Keep the withheld machine decision in the document as audit provenance; add the accepted
   user-context decision alongside (FR3-016/FR3-020: user-context provenance must be
   `user_session_context`, never an in-place upgrade of the model decision). `hasDirectConflict`
   runs first, unchanged.
3. Grep explainer/report code for assumptions that `(assetID, canonicalPath)` is unique across
   decisions; export planning filters on `.accepted` + export flags, so no double-export.

This restores specified behavior (FR3-011b: withheld **unless** supplied as explicit user session
context) — not a spec change. If any `governingRule`/policy strings change, add new strings; never
rename existing ones (invariant 7).

**Tests.** `Tests/AISidecarCoreTests/SessionContextPolicyTests.swift`; extend
`phase3DirectDecision` in `Phase3NormalizationTestSupport.swift` with
`status: NormalizationDecisionStatus = .accepted`:

```swift
func testWithheldDirectObservationDoesNotBlockExplicitUserContext() throws {
    let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
        canonicalization: phase3Canonicalization(
            sessionContext: [phase3SessionContext(.event, text: "Migration",
                canonicalPath: "Event|Migration", propagationAllowed: true)],
            decisions: [phase3DirectDecision(assetID: "asset-000001",
                canonicalPath: "Event|Migration", status: .withheld)]
        ),
        input: phase3InputBatch(["seq/IMG_0001.JPG"]),
        configuration: phase3Configuration()
    )
    let context = try XCTUnwrap(result.perAssetDecisions.first {
        $0.assetID == "asset-000001" && $0.stage == .userSessionContext
    })
    XCTAssertEqual(context.status, .accepted)
    XCTAssertEqual(result.sessionContext.first?.exportResult, "applied")
    XCTAssertTrue(result.perAssetDecisions.contains {   // audit trail survives
        $0.stage == .directModelObservation && $0.status == .withheld
    })
}

func testAcceptedDirectObservationStillSuppressesDuplicateUserContext() throws { /* unchanged skip */ }
```

**Acceptance.**
- [ ] `SessionContextPolicyTests` gains a case with a pre-existing withheld direct decision — context still applies (plan 08 verbatim).
- [ ] Determinism record updated if policy text changes (plan 08 verbatim).
- [ ] Accepted-duplicate skip and conflict counting unchanged.

**Commit.** `Apply user session context over withheld machine decisions`

### R4-3 — GPS coordinate-term guard: broaden the regex set

**Goal.** Extend `isCoordinateLikeTerm` so DMS, cardinal-prefixed, bare signed-pair, and UTM
strings can never reach `dc:subject` (invariant 3), without blocking legitimate terms.

**Files.**
- `Sources/AISidecarCore/Metadata/CandidateExtractor.swift:669-686` (`isCoordinateLikeTerm`); guard call at `:585`

**Current behavior (verified 2026-07-08).** The guard has keyword substrings (`gps`, `latitude`,
…), a decimal-pair regex, and a degree-cardinal regex. Verified misses: DMS
`40°26'46"N 79°58'56"W` (quotes/seconds break the pattern), cardinal-prefix `N 40.446 W 79.982`
(cardinal precedes the number), integer pairs `40, -79` (no decimal point), UTM
`UTM 17T 589500 4477000`. In observed-tags mode there is no vocabulary backstop, so a model echoing
prompt GPS context can reach `dc:subject`.

```swift
// CandidateExtractor.swift:678
let decimalPairPattern = #"(?<!\d)[+-]?\d{1,3}\.\d+\s*[,/ ]\s*[+-]?\d{1,3}\.\d+(?!\d)"#
```

**Change.**
1. Make the function `static` internal (drop `private`) so table-driven tests reach it via
   `@testable import`; keep one end-to-end extractor test.
2. Add four conservative patterns (each requires two coordinate-ish tokens or explicit N/S/E/W
   context, per plan 08):

```swift
// DMS with Unicode primes/quotes: 40°26'46"N 79°58'56"W
#"\d{1,3}\s*[°º]\s*\d{1,2}\s*['′’]\s*\d{1,2}(?:\.\d+)?\s*["″”]?\s*[NSEW]"#,
// Cardinal-prefixed decimal pair: N 40.446 W 79.982
#"\b[NS]\s*\d{1,3}(?:\.\d+)?\b.*\b[EW]\s*\d{1,3}(?:\.\d+)?\b"#,
// Bare numeric pair, second number explicitly signed: 40, -79
#"(?<!\d)[+-]?\d{1,3}(?:\.\d+)?\s*,\s*[+-]\d{1,3}(?:\.\d+)?(?!\d)"#,
// UTM zone reference: UTM 17T 589500 4477000
#"\butm\b\s*\d{1,2}\s*[a-z]?\b"#,
```

   evaluated case-insensitively alongside the existing two.
3. Negatives stay safe by construction: `"50mm f/1.8"` (single decimal), `"Apollo 11"`,
   `"Route 66"`, `"Room 404"` (no sign/cardinal pairing), `"5'10\" tall"` (no degree symbol),
   `"autumn"` (`utm` not a substring). The bare-pair pattern requires an explicit sign on the
   second number so `"1, 2"` passes — extend the guard conservatively, don't over-block.
4. Run every new regex against the positive/negative table before committing (plan 08 verified the
   misses by running the regexes; do the same for the fixes).

**Tests.** `Tests/AISidecarCoreTests/CandidateExtractorTests.swift` (existing:
`testCoordinateTermsAndGPSOnlyEvidenceAreNeverExported` at `:220`):

```swift
func testCoordinateLikeTermGuardCatchesDMSCardinalIntegerPairAndUTM() {
    let blocked = [
        #"40°26'46"N 79°58'56"W"#, "40°26′46″N 79°58′56″W",
        "N 40.446 W 79.982", "n40.446 w79.982",
        "40, -79", "-40.4, -79.9",
        "UTM 17T 589500 4477000", "utm 17",
        "40.446, -79.982", "40.446 N, 79.982 W",   // existing patterns still hit
    ]
    let allowed = ["50mm f/1.8", "35mm", "Apollo 11", "Route 66", "Room 404",
                   "5'10\" tall", "autumn migration", "ISO 6400, f/8"]
    for term in blocked { XCTAssertTrue(CandidateExtractor.isCoordinateLikeTerm(term), term) }
    for term in allowed { XCTAssertFalse(CandidateExtractor.isCoordinateLikeTerm(term), term) }
}

func testDMSCoordinateCandidateIsSkippedInObservedTagsMode() throws {
    // End-to-end: DMS tag ends in skippedCandidates with .coordinateLikeTerm, never flatKeywords.
}
```

**Acceptance.**
- [ ] Table-driven cases for each caught format plus non-coordinate negatives ("50mm f/1.8", "Apollo 11", "Room 404") (plan 08 verbatim).
- [ ] Existing coordinate/GPS-evidence test still green (guards extended, not replaced); `evidenceReliesOnGPS` untouched.

**Commit.** `Broaden coordinate-term guard to DMS, cardinal-prefix, signed pairs, and UTM`

### R4-4 — Vocabulary validation: duplicate/ambiguous flat keywords

**Goal.** Stop ambiguous flat-keyword/synonym aliases from silently resolving to the
lexicographically-first canonical path, and stop aliases from shadowing exact canonical-path
matches (invariant 10 seam).

**Files.**
- `Sources/AISidecarCore/Normalization/VocabularyValidator.swift:50-74` (`validateSynonyms`; no flat-keyword cross-check exists)
- `Sources/AISidecarCore/Normalization/VocabularyIndex.swift:117-125` (`insertLookup`), build loop `:22-38`, guarded separator variant `:127-139`

**Current behavior (verified 2026-07-08).** The validator checks synonym↔synonym and
synonym↔canonical collisions (FR3-003b) but never flat keywords. `insertLookup` is silently
first-wins:

```swift
// VocabularyIndex.swift:121
if canonicalPathByFoldedTerm[folded] == nil {
    canonicalPathByFoldedTerm[folded] = canonicalPath
}
```

Two entries sharing a folded `flat_keyword` (or a synonym of A equal to B's flat keyword) resolve
to whichever sorts first — the wrong `lr:hierarchicalSubject`, no warning — while the
separator-fold map *is* ambiguity-guarded (`insertSeparatorLookup`). **Additional verified
defect:** the build loop interleaves canonical/flat/synonym insertions per entry in canonical-path
sort order, so an earlier entry's flat keyword can claim the folded key of a later entry's
*canonical path* (e.g. entry `Animals` with `flat_keyword: "Birds"` shadows canonical `Birds`) — a
latent invariant-10 violation the validator does not catch (it rejects synonym↔canonical but not
flat↔canonical collisions).

**Change.**
1. **Tier the index build** (invariant 10, FR3-003d exact-first): pass 1 inserts every folded
   `canonicalPath`; pass 2 inserts flat keywords and synonyms through an ambiguity-guarded
   `insertAliasLookup` that never overwrites or ambiguates a canonical-tier key and mirrors
   `insertSeparatorLookup` for alias↔alias collisions:

```swift
private mutating func insertAliasLookup(_ value: String, canonicalPath: String) {
    let folded = VocabularyTextFolder.fold(value)
    guard !folded.isEmpty, !canonicalFoldedTerms.contains(folded),
          !ambiguousFoldedAliasTerms.contains(folded) else { return }
    if let existing = canonicalPathByFoldedTerm[folded], existing != canonicalPath {
        canonicalPathByFoldedTerm.removeValue(forKey: folded)
        ambiguousFoldedAliasTerms.insert(folded)
    } else {
        canonicalPathByFoldedTerm[folded] = canonicalPath
    }
}
```

   Apply the same two-pass tiering to the separator-fold map for consistency.
2. **Validator** — add `validateFlatKeywords(_:)` detecting, after `VocabularyTextFolder.fold`:
   flat↔flat duplicates across entries, synonym(A)↔flat(B) collisions, flat↔canonical-fold
   collisions, and fold-duplicate canonical paths; list all collisions in the message, matching
   `validateSynonyms` style.
3. **STOP: maintainer decision — error vs. warn.**
   - **Option A (error):** all collision classes fail loading with `E_VOCABULARY_INVALID`,
     symmetric with FR3-003b. This **changes specified behavior** — FR3-003b covers synonyms only,
     so erroring on flat collisions is a spec tightening (add an FR3-003b-1 line to doc 03,
     additive) and may reject vocabularies that load today.
   - **Option B (warn + runtime guard only):** no loader rejection; ambiguous aliases simply never
     match (consistent with the FR3-003d-1 fallback rule). Needs a warnings channel added to
     `VocabularyValidator.validate` (today it only throws or returns).
   - **Recommendation (per plan 08's parenthetical):** Option A for synonym↔flat, flat↔canonical,
     and canonical-fold duplicates (clear authoring mistakes) plus the step-1 runtime guard as
     defense-in-depth; guard-only for flat↔flat duplicates, which can be a deliberate export
     choice (two nodes sharing a display keyword). The step-1 guard lands unconditionally.
4. Confirm the bundled starter vocabulary passes (`StarterVocabularyTests`; FR3-001a routes it
   through the same validator).

**Tests.** `Tests/AISidecarCoreTests/VocabularyIndexTests.swift` (mirror `:84
testSeparatorInsensitiveFallbackDoesNotResolveAmbiguousAliases`) and `VocabularyValidatorTests.swift`:

```swift
func testExactFoldLookupDoesNotResolveAmbiguousFlatKeywordAliases() throws {
    // Two entries with fold-identical flat_keyword: entry(matching:) returns nil for the
    // alias; both canonical paths still resolve exactly.
}

func testFlatKeywordAliasNeverShadowsExactCanonicalPathMatch() throws {
    // "Subject|Animals" flatKeyword "Birds" + entry "Subject|Birds":
    // entry(matching: "Birds") returns "Subject|Birds" (invariant 10).
}

// VocabularyValidatorTests.swift
func testSynonymCollidingWithAnotherEntrysFlatKeywordFailsValidation() throws {
    XCTAssertThrowsError(try VocabularyValidator.validate(document)) // E_VOCABULARY_INVALID
}
```

**Acceptance.**
- [ ] Mirror `testSeparatorInsensitiveFallbackDoesNotResolveAmbiguousAliases` for exact-fold (plan 08 verbatim).
- [ ] Exact canonical-path folded matches can never be shadowed or ambiguated by aliases (invariant 10).
- [ ] Maintainer decision recorded; if Option A, doc 03 gains the new FR line (additive).
- [ ] Bundled starter vocabulary still loads (`StarterVocabularyTests` green).

**Commit.** `Guard exact-fold vocabulary lookups against ambiguous aliases and validate flat-keyword collisions`

### R4-5 — Session/edit hardening lows

**Goal.** Close five low-severity gaps: pipes in user edits, brittle forward-compat session decode,
stamp-path fallbacks, XMP merge-target selection, and export-stamp serialization drift.

**Files.**
- `Sources/AISidecarCore/Normalization/SessionReview.swift:36-47` (`applying` edit block); `Sources/CupricAspectApp/Features/Review/ReviewModel.swift:237-243` (`editKeyword`), `:247-260` (`editEverywhere`)
- `Sources/AISidecarCore/Normalization/NormalizationSessionDocument.swift:752-765` (`validateSchemaVersion` accepts 1.x); strict decision enums, e.g. `NormalizationDecisionStatus` at `:378`
- `Sources/AISidecarCore/Normalization/NormalizedXMPChangePlanner.swift:217` → `Sources/AISidecarCore/Pipeline/XMPExportPipeline.swift:582-604` (`stampSourceSidecars`)
- `Sources/AISidecarCore/Metadata/XMPDocumentParser.swift:162-181` (`locateOrCreateWritableDescription`)
- `Sources/AISidecarCore/Sidecars/RawSidecarExportStamp.swift:38-66` (`stamp`)

**Current behavior (verified 2026-07-08).**
(1) `SessionReview.applying` accepts any non-empty trimmed edit (`exportFlatKeyword = true`);
`ReviewModel.editKeyword` guards only emptiness — a literal `|` keyword bypasses the
`containsHierarchySeparator` guard (edits enter after canonicalization) and exports, violating
FR3-003g/h semantics. (2) `validateSchemaVersion` accepts any `ai-sidecar-normalization/1.x`, but
decision enums are strict `String, Codable` — one unknown raw value from a future 1.x writer fails
the whole document decode. (3) The planner emits a non-sidecar fallback:

```swift
// NormalizedXMPChangePlanner.swift:217
sourceSidecarPath: sidecar?.sidecarPath ?? sourcePath ?? asset.sourceRelativePath,
```

so with no `.ai.json` the *image path* reaches `stampSourceSidecars`, where
`try? RawSidecarExportStamp.stamp(...)` (`XMPExportPipeline.swift:599`) swallows the
JSON-object-guard error — the only protection for invariant 2. (4) **Discrepancy:** plan 08 says to
"prefer `rdf:about=""` … over `descriptions.first`", but `locateOrCreateWritableDescription`
(unchanged since commit `b79ecb0`) *already* prefers managed-field descriptions, then
`rdf:about == ""` (`:170-171`), before `descriptions.first`; the only remaining gap is the
source-matching-`about` preference plan 08 also names. (5) `RawSidecarExportStamp.stamp`
round-trips the whole sidecar through `JSONSerialization` (`:45`, `:61-64`) — escaped slashes and
float drift (`0.08 → 0.080000000000000002`), diverging from deterministic `JSONCoding` output.

**Change.**
1. Add `SessionReview.sanitizedEdit(_ text: String) -> String?` — `nil` when the trimmed text is
   empty or contains `"|"`. Use it in `applying` (invalid edit → decision left untouched) and in
   `ReviewModel.editKeyword`/`editEverywhere` (rejected before storing, surfaced via the model's
   existing status/announcement channel). Core-level, so CLI session edits are covered too.
2. Introduce a raw-value-preserving tolerant wrapper for the additive decision enums —
   `enum Tolerant<T: RawRepresentable & Codable>: Codable { case known(T); case unknown(String) }`
   — applied in `PerAssetNormalizationDecision`'s Codable layer for `status`, `candidateKind`, and
   `skipReasons` elements. Unknown values round-trip byte-stable on re-encode (invariant 8, both
   directions); the affected decision is treated as withheld/not-exportable; the document loads.
   Public enum API stays unchanged (decode privately, surface an `isForwardCompatUnknown` flag).
   Scope check: if Codable churn exceeds ~150 lines, land `skipReasons` tolerance only and record
   the rest as a known issue.
3. Make `SourceMemberPlan.sourceSidecarPath` optional (`XMPChangePlan.swift:16-43`; additive — old
   documents still decode) and emit `nil` at planner `:217` unless `sidecar?.sidecarPath` ends in
   `.ai.json`. `stampSourceSidecars` skips `nil` and records the skip via the pipeline's report
   notes/`Logger` instead of relying on the `try?`-swallowed guard.
4. In `locateOrCreateWritableDescription`, between the managed-field and `about == ""` preferences,
   try a description whose `rdfAboutValue` ends with the source file name; keep
   `descriptions.first` as the final existing-description fallback.
5. Rewrite `RawSidecarExportStamp.stamp` on the schema-evolution path: decode with
   `RawJSONSidecarDocument(data:)` (`RawJSONSidecarDocument.swift:20`), set the `xmp_export` object
   on the merged `JSONValue`, encode via `JSONCoding.documentEncoder(iso8601Dates: false)` — the
   same merge-preserving deterministic path `encodedData()` (`:46-51`) uses. No more
   `JSONSerialization` round-trip.

**Tests.** `Tests/AISidecarCoreTests/SessionReviewTests.swift`, `NormalizationSessionTests.swift`,
`NormalizedXMPChangePlanTests.swift`, `XMPExportPipelineTests.swift` (stamp test at `:176`):

```swift
func testEditContainingHierarchySeparatorIsRejected() throws {
    let reviewed = SessionReview.applying(verdicts: [:], edits: [id: "Great|Egret"], to: session)
    XCTAssertEqual(decision(in: reviewed, id: id).flatKeyword, originalFlatKeyword) // untouched
}

func testUnknownDecisionEnumValueFromNewerMinorVersionDoesNotFailDocumentDecode() throws {
    // Fixture with skip_reasons: ["some_future_reason"]: document loads, decision not
    // exportable, re-encode preserves "some_future_reason".
}

func testSourceSidecarPathIsNilWhenNoRawSidecarExists() throws { }
func testStampSkipsMembersWithoutRawSidecarAndNeverWritesToImagePaths() throws { }
func testStampRewritePreservesFloatAndSlashFormatting() throws {
    // Sidecar containing 0.08 and a "/path" string: bytes unchanged except xmp_export.
}
```

**Acceptance.**
- [ ] Reject/strip `|` in `SessionReview.applying` (Core-level) and surface the rejection in the GUI (plan 08 verbatim).
- [ ] Additive enums decode-tolerant; unknown case fails only the affected decision, not the document (plan 08 verbatim).
- [ ] Emit nil instead of a non-`.ai.json` path and skip stamping; log the skip (plan 08 verbatim).
- [ ] Merge target prefers a source-matching `rdf:about` before `descriptions.first` (adjusted per discrepancy above; `about=""` preference already present).
- [ ] Stamp rewrite routed through the merge-preserving `JSONCoding` path (plan 08 verbatim).
- [ ] Golden sidecar tests updated deliberately if stamp byte output changes.

**Commit.** `Session/edit hardening: pipe rejection, tolerant decode, stamp path and serialization, merge-target about` (split per bullet if any grows; each is independently committable)

### R4-6 — Derivative-cache cross-process safety (combined with efficiency P2/P3)

**Goal.** One `DerivativeCache` manifest redesign: cross-process-safe manifest read-modify-write
(R4-6), lock narrowed off the image encode with single hashing (P2), in-memory manifest caching
with write-through and a shared instance (P3), and working-set eviction protection (R4-6b).

**Files.**
- `Sources/AISidecarCore/Rendering/DerivativeCache.swift` (whole file; `NSLock` at `:24`, `store` `:96-147`, `loadManifest`/`saveManifest` `:235-254`, `evictIfNeeded` `:256-272`, `clear` `:179-216`)
- `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift:474-476` (per-image `DerivativeCache` construction inside `prepare`) — **Discrepancy:** plan 05 cites `:465-470`; drifted to `:474-476` (plan 05 predicts drift; the symbol reference holds)

**Current behavior (verified 2026-07-08).** The manifest (`derivative-cache-index.json`, schema
`aisidecar-derivative-cache/1.0`) is guarded only by `private static let manifestLock = NSLock()`
(`:24`) — in-process only, while GUI + CLI share `~/Library/Caches/aisidecar/derivatives` and
interleave load-modify-save: lost entries become orphaned artifacts that escape byte-cap
accounting, silently unenforcing FR1-018a. `store()` takes the lock *before*
`AtomicFileWriter.writeFile` (`:110-114`), serializing all render workers on the JPEG encode;
`sha256(of: url)` (`:117`) then re-reads the just-written file. Every operation re-reads and
re-writes the whole manifest, and `AnalyzePipeline` builds a fresh cache per prepared image, so
nothing amortizes. Eviction protects only the just-stored artifact:

```swift
// DerivativeCache.swift:261
let candidates = manifest.entries.values
    .filter { $0.fileName != protectedFileName }
    .sorted { $0.lastAccessedAt < $1.lastAccessedAt }
```

so with `stage_concurrency > 1` and a small user-set cap, prepared-ahead derivatives can be evicted
before the model loop reads them.

**STOP: maintainer decision — lock mechanism.**
- **Option A — `flock` file lock** (`derivative-cache-index.lock`, `flock(LOCK_EX)`): reliable on
  the always-local `~/Library/Caches` APFS volume; manifest schema untouched (invariant 8 — no
  migration); flock is also exclusive between fds within one process, so it *replaces* the static
  `NSLock` as the single mechanism. Mixed-version concurrency (old binary without flock beside a
  new one) stays unprotected — acceptable pre-beta; both executables ship together.
- **Option B — per-entry manifest files:** no shared-file contention, but LRU + FR1-018a byte
  accounting need a directory enumeration per store, every cache *hit* rewrites a file to touch
  `lastAccessedAt`, `clear()`/`ArtifactCleanup` ownership grows, and existing manifests need
  migration.
- **Recommendation: Option A** — "simple, sufficient" (plan 08's words), and it composes with P3's
  read cache. The design below assumes Option A.

**Change** (one design; four sub-commits, in order):
1. **(P2) Narrow `store()`.** Run `AtomicFileWriter.writeFile`, the attribute read, and hashing
   *before* any lock; lock only `loadManifest → insert → evictIfNeeded → saveManifest`. Add
   `sha256(of data: Data)` and hash encoded bytes where the render path holds them in memory; where
   the encoder writes straight to the temp URL, hash the temp file once inside the writer step —
   never re-read after rename. Comment the now-benign same-derivative race: atomic temp+rename
   means last rename wins, manifest updated under the lock (plan 05 P2 step 3).
2. **(R4-6) Cross-process flock.** New `Sources/AISidecarCore/Support/FileLock.swift`:

```swift
/// Cross-process advisory lock (flock) for shared cache metadata.
struct FileLock {
    let path: String
    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T
    // open(path, O_CREAT|O_RDWR) → flock(fd, LOCK_EX) → body() → flock(LOCK_UN) → close
}
```

   Route every manifest critical section (`cachedRecord`, `store`'s manifest phase, `clear`) through
   one private `withManifestLock(_:)` taking the flock; delete the static `NSLock`. Add the lock
   file's name to `cacheOwnedNames` in `clear()` (`:193`) and confirm `ArtifactCleanup` ignores it.
   Only on-disk change: the new `.lock` file.
3. **(P3) Manifest read cache + shared instance.** Convert to
   `final class DerivativeCache: @unchecked Sendable` with an instance `NSLock` guarding
   `cachedManifestState: (manifest: CacheManifest, mtime: Date, size: Int64)?`. `loadManifest()`
   under the flock stats the file; on mtime+size match it reuses the parsed manifest (no read/
   decode), else reads and caches. `saveManifest()` writes through (atomic write, refresh cached
   state) — plan 05 P3 constraint: keep write-through, never batch writes; the win is eliminating
   repeated *reads*, and `aisidecar purge` keeps working against a cache written by an analyze run.
   Route manifest reads through `fileManager.contents(atPath:)` for a counting-FileManager test
   seam. Then hoist construction out of `AnalyzePipeline.prepare` (`:474-476`): one cache built at
   pipeline setup, passed into `prepare` (verify strict-concurrency acceptance).
4. **(R4-6b) Working-set protection.** `evictIfNeeded(protecting: Set<String>)`; the cache keeps an
   in-process `retainedFileNames` set (instance state): `store()` and `cachedRecord()` hits
   register the artifact; a `releaseRetained()` hook called from pipeline teardown clears it.
   Eviction skips retained names — the cache may transiently exceed the cap by the working-set size
   (document as the FR1-018a floor; equivalent to plan 08's cap-floor alternative, without a config
   change).

**Migration/verification story (single).** No manifest migration; existing caches work unchanged.
Cross-process safety is testable in-process because flock contends between separate fds. Capture
plan 05's Verification Baseline before sub-commit 1 and after sub-commit 4 on the same inputs and
record both in the PR description.

**Tests.** `Tests/AISidecarCoreTests/DerivativeCacheTests.swift` (conventions: real temp dirs,
injected `now`) plus a new `FileLockTests.swift`:

```swift
// FileLockTests.swift
func testExclusiveLockSerializesTwoHandles() throws { /* handle B blocks until A releases */ }

// DerivativeCacheTests.swift
func testConcurrentStoresForDistinctDerivativesAllLandInManifest() throws {
    // concurrentPerform on one shared instance: all N entries present, byte accounting correct. (P2)
}
func testTwoCacheInstancesInterleavingStoresLoseNoManifestEntries() throws {
    // Two instances on one directory (stand-in for GUI+CLI; flock contends per fd). (R4-6)
}
func testRepeatedCachedRecordHitsDoNotRereadManifestFile() throws {
    // Counting FileManager: N hits after warm load => 1 manifest read. (P3)
}
func testEvictionSkipsRetainedWorkingSetUnderTinyCap() throws {
    // Cap below working set: retained artifacts survive; releaseRetained() re-enables eviction. (R4-6b)
}
```

Existing `testLRUEvictionRemovesOlderArtifactsUnderCap`, `testClearRemovesCacheOwnedArtifactsOnly`,
and `ArtifactCleanupTests` must pass unchanged.

**Acceptance.**
- [ ] Maintainer decision recorded: flock file lock vs. per-entry manifest files (plan 08 verbatim; recommendation Option A).
- [ ] Interleaved manifest read-modify-write across instances/processes loses no entries (R4-6).
- [ ] `evictIfNeeded` protects the current batch's planned artifacts or floors the cap at the working-set size (plan 08 verbatim; R4-6b).
- [ ] Concurrent `store()` calls for distinct derivatives succeed and the manifest contains both entries (plan 05 P2 verbatim).
- [ ] No behavioral change to manifest contents, eviction order, or `DerivativeRecord` fields (plan 05 P2 verbatim).
- [ ] Repeated `cachedRecord()` hits do not re-read the manifest file (plan 05 P3 verbatim).
- [ ] `DerivativeCacheTests` and `ArtifactCleanupTests` pass; purge still works against a cache written by an analyze run (plan 05 P3 verbatim).
- [ ] With `--stage-concurrency 4` on a batch, render stage wall time drops (baseline vs. after) (plan 05 P2 verbatim).

**Commit.** Four sub-commits, in order:
1. `Narrow derivative-cache store lock to manifest mutation and hash bytes once`
2. `Serialize derivative-cache manifest access across processes with a flock file lock`
3. `Cache derivative manifest in memory with write-through and share one cache across analyze workers`
4. `Protect the current run's derivative working set from byte-cap eviction`

### R4 exit gate

```bash
swift test
swift run aisidecar --help
swift build --product CupricAspect

# Normalization smoke (agent_docs/testing-and-verification.md):
swift run aisidecar normalize --from-json <json-folder> --recursive --source-root <image-root> --session-only --output-dir <tmp-output>
swift run aisidecar normalize --from-json <json-folder> --recursive --source-root <image-root> --dry-run --output-dir <tmp-output>
swift run aisidecar normalize --from-json <json-folder> --recursive --source-root <image-root> --output-dir <tmp-output>
swift run aisidecar normalize --file-list <image-list.txt> --session-only --output-dir <tmp-output>
swift run aisidecar normalize <image-or-folder> --mode both --output-dir <tmp-output>
```

For R4-6, plan 05's Verification Baseline before sub-commit 1 and after sub-commit 4, same inputs,
both recorded in the PR description (evaluate the non-model portion — render, hash, write, log):

```bash
swift run -c release aisidecar benchmark --self-test
swift run -c release aisidecar benchmark --spec source-identity-fast --max-hash-copies 1 --output-dir /tmp/aisidecar-bench
# End-to-end (needs Ollama + a test image folder of ~50-100 images):
time swift run -c release aisidecar analyze <folder> --recursive --mode both --output-dir /tmp/aisidecar-baseline
```

R4-1 additionally warrants one manual smoke: a file list mixing in-root relative paths and
out-of-root absolute paths with a shared basename must produce one `.xmp` per directory.

## Definition of done

The hardening waves are complete when:

1. Every R1–R4 item's acceptance checkboxes are checked, or the item is explicitly deferred by Ron with a note in plan 08 §6.
2. `swift test` is green with every new test from this plan present and meaningful (no skipped/commented assertions).
3. The three **STOP: maintainer decision** resolutions are recorded inline in this document (edit the item; one line: decision + date).
4. Plan 08 §8's traceability table rows for landed items are marked done (edit in place — that table is the finding-level ledger).
5. The `v0.1.0-beta.1` tag exists (after R1 + the manual release step), `agent_docs/release-checklist.md` exists, and release evidence for B0-5 is recorded under `agent_docs/release-evidence/`.
6. `agent_docs/08-post-review-hardening-plan.md` §1.1 step 7 (efficiency plan) is unblocked: R4-6 landed with P2/P3 inside it, and R1-3 landed ahead of P4.

After this plan closes, execution continues at plan 08 §1.1 step 7 (remaining efficiency items), then step 8 (M9–M11, per `agent_docs/phase-4-gui-implementation-plan.md` — note its "Decisions required before M9/M10a" sections), then step 9 (roadmap 09).
