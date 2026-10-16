# Readiness review — Epic 1 (macOS foundation, permissions, audio capture)

Reviewed 2026-10-16 with the `story-review` skill against `docs/backlog/epic-01-macos-foundation.md`.

## Summary

| Story | Verdict | Main points |
|---|---|---|
| E1-S1 Scaffold | Ready | Baseline decisions proposed below; recorded in ADR 0001/0002. |
| E1-S2 Menu bar | Ready with notes | "Start Test Recording" depends on E1-S5/E1-S6. |
| E1-S3 Permissions | Ready with notes | Accessibility has no Denied/Restricted states; App Sandbox decision. |
| E1-S4 Shortcut | Ready with notes | Hot-key mechanism must avoid Input Monitoring; debounce vs state machine overlap with E1-S6. |
| E1-S5 Audio | Ready with notes | Audio format and on-disk storage need a decision. |
| E1-S6 Overlay | Ready | — |
| E1-S7 Diagnostics | Ready with notes | Logging/redaction foundation is needed from E1-S1, not at the end. |
| E1-S8 CI | Ready with notes | CI runner availability for Xcode 27; CI should start earlier. |

No blockers. The cross-cutting decisions below are proposed defaults; E1-S1
records the platform ones as ADRs.

## Cross-cutting decisions (proposed defaults)

1. **Distribution and sandbox** — App Sandbox off, Hardened Runtime on for
   Release, Developer ID direct distribution assumed until Epic 7 decides.
   Reason: sandboxed apps cannot use Accessibility to control other apps, which
   E2-S7 insertion and E1-S4 target capture require. Recorded in ADR 0001.
2. **Deployment target** — macOS 26.0, Apple Silicon (arm64) only. Gives
   on-device `SpeechAnalyzer` (Epic 2) and Foundation Models (Epic 3) without
   availability branching. Recorded in ADR 0001.
3. **Project generation** — XcodeGen `project.yml` plus a local Swift package;
   the `.xcodeproj` is generated, not committed. Recorded in ADR 0002.
4. **Tests** — Swift Testing for unit tests, XCUITest for UI tests.
5. **Logging** — a `Support.Log` wrapper over `os.Logger` and a
   `LemmeTypeError` protocol with stable identifiers land in E1-S1 so every
   later story uses them; E1-S7 adds redaction tests, the event buffer, and export.

## Story notes

### E1-S1 — Scaffold the native macOS project and architecture — Ready

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Developer-facing foundation. |
| 2 | Size | Pass | 3 points. |
| 3 | Dependencies | Pass | None. |
| 4 | Acceptance criteria | Pass | All observable. |
| 5 | CI testability | Concern | macOS UI tests need an unlocked GUI session with automation enabled; fine locally and on hosted macOS runners. |
| 6 | Privacy | Pass | No user data. |
| 7 | Permissions | Pass | None requested. Reading status must not prompt. |
| 8 | Feasibility | Pass | — |
| 9 | Out of scope | Pass | No speech/LLM dependency. |
| 10 | Open decisions | Concern | Decisions 1–4 above. |

**AC → verification map**

| Acceptance criterion | Verification |
|---|---|
| Clean checkout builds with documented command | `make build` on a clean clone (manual checklist MA-1) |
| Unit and UI test targets discovered and pass | `make test` runs package tests, `LemmeTypeTests`, `LemmeTypeUITests` |
| Concrete services composed in one location | `App/LemmeType/AppComposition.swift`; `AppCompositionTests` |
| Audio/permission dependency replaceable without OS service | `AppCompositionTests.uiTestingCompositionUsesFakes`, `LaunchUITests.testLaunchShowsInjectedPermissionStatus`, view-model tests using fakes |
| Platform baseline ADR committed | `docs/decisions/0001-platform-baseline.md` |

### E1-S2 — Menu bar lifecycle — Ready with notes
- "Start Test Recording" needs E1-S5/E1-S6. Proposed: show it disabled with
  "Available after audio setup" until E1-S6, or move it to E1-S6.
- Use `LSUIElement` (no Dock icon), `MenuBarExtra`, a SwiftUI `Settings`
  scene, and `SMAppService.mainApp` for Launch at Login; `.requiresApproval`
  must be surfaced as its own state.
- Single instance: on launch, detect another running instance with the same
  bundle id, activate it, and terminate.

### E1-S3 — Permission onboarding — Ready with notes
- Accessibility (`AXIsProcessTrusted`) reports only trusted / not trusted; it
  cannot distinguish Not Requested from Denied and has no Restricted state.
  Suggest the AC say Accessibility shows **Granted / Not granted** only — this
  is what "no claim the OS cannot guarantee" implies.
- No change notification exists for Accessibility trust; rechecking on app
  activation (already in scope) plus a short poll while onboarding is visible is
  the practical approach.
- Ad-hoc–signed Debug builds lose Accessibility trust on every rebuild because
  the code signature changes; developers should use a team-signed build
  (`Config/Signing.local.xcconfig`) for this story.

### E1-S4 — Global shortcut — Ready with notes
- Use Carbon `RegisterEventHotKey`: it delivers key-down and key-up (needed for
  Push to Talk) without Input Monitoring. Modifier-only or Fn shortcuts would
  need an event tap and Input Monitoring — mark them out of scope.
- "No overlapping sessions" overlaps E1-S6's state machine. Proposed: E1-S4
  owns event de-duplication (one start per press), E1-S6 owns rejecting
  invalid recorder transitions.
- Cancel: register Escape as a hot key only while recording, so it is not
  swallowed from other apps the rest of the time.
- Target capture: frontmost app PID plus the focused `AXUIElement`, in memory
  only, never read for text.

### E1-S5 — Audio capture — Ready with notes
- Proposed format: 16 kHz, mono, 32-bit float PCM (accepted by Apple Speech and
  Whisper-class models); convert from the device format with `AVAudioConverter`.
- Decide whether audio is written to disk at all. Proposed: keep buffers in
  memory and write a temp file only if an engine requires one; temp files go in
  an app-private directory with 0600 permissions and are purged on launch.
- Per-device selection with `AVAudioEngine` requires setting the input unit's
  current device through Core Audio; budget for it inside the 8 points.

### E1-S6 — State machine and overlay — Ready
- Overlay as a non-activating `NSPanel`; VoiceOver announcements via
  `NSAccessibility` announcement notifications.

### E1-S7 — Diagnostics — Ready with notes
- `OSLogStore` only reads the current process's logs; proposed: keep an
  in-app ring buffer of structured, non-sensitive events for export.
- "Hardware class" = model identifier (e.g. `Mac15,6`), not serial number.
- Logging wrapper and error-identifier protocol are pulled into E1-S1 (see above).

### E1-S8 — CI — Ready with notes
- GitHub-hosted macOS runners must offer Xcode 27 / macOS 26 SDK; verify the
  runner image before relying on it, otherwise a self-hosted runner is needed.
- Suggest adding a minimal build-and-unit-test workflow early (after E1-S1)
  rather than last, so S2–S7 are protected; E1-S8 then completes it.
