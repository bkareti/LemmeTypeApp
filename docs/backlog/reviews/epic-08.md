# Readiness review — Epic 8 (iPhone and iPad companion)

Reviewed 2026-11-02 with the `story-review` skill against
`docs/backlog/epic-08-ios-companion.md`, issues #8, #84, and #85, the code on
`main` (all package modules), ADRs 0001–0026, and Apple's primary documentation
(sources below). A probe built each package module for the iOS Simulator with
iOS 26 added to the package platforms; the result is the basis for E8-S3.

## Summary

| Story | Verdict | Main points |
|---|---|---|
| E8-S1 Cross-app workflow spike and ADR | Ready as an investigation | Device evidence cannot be produced in CI or on a simulator; the ADR is split into an accepted baseline and proposed parts. |
| E8-S3 Shared modules for iOS | Ready | Four modules already build; five need `#if os(macOS)` guards. |
| E8-S4 iOS target, permission, audio session | Ready with notes | Real calls, Siri, and lock behaviour are manual. |
| E8-S5 Local recognition and models | Ready with notes | Memory limits (jetsam) must be measured on devices; thresholds are Proposed. |
| E8-S6 Quick Dictation | Ready | Reuses the recorder state machine and pipeline; delivery is an explicit copy. |
| E8-S7 Action Button, Back Tap, Shortcuts | Ready with notes | Whether a shortcut can start recording from a locked or backgrounded app is unproven; the story opens the app instead. |
| E8-S8 Modes and personalization | Ready | Shared library and archive; per-app rules are hidden on iOS. |
| E8-S9 Accessibility, privacy, iPad | Ready | Extends existing guardrail scripts to the iOS target. |
| E8-S2 Validation capstone | Ready with notes | Needs physical devices and threshold approval. |

No blockers for E8-S1, E8-S3 to E8-S9. Epic acceptance is blocked on the
real-device matrix and on threshold approval, both manual product-owner steps.

## Changes to the existing issues

- **#84 (E8-S1)** keeps its title and intent; its scope is restated and the
  Apple-documented facts are added.
- **#85 (E8-S2)** keeps its title. It was an outcome-tracking issue that "needs
  refinement into implementation stories of at most 8 points after the spike";
  that work is now E8-S3 to E8-S9, and E8-S2 is the validation capstone. Its
  number stays "S2" because the sync script matches issues by exact title.
- The GitHub body of #85 still describes the original, broader scope; the sync
  script never edits existing bodies. A comment on the issue records the split.

## Checklist (epic level)

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Speak on the phone, review, copy, paste anywhere, locally. |
| 2 | Size | Pass | Nine stories, none above 8 points. |
| 3 | Dependencies | Pass | Epics 1–7, 9, and 10 are merged. Closed status alone did not prove portability, so E8-S3 measured it. |
| 4 | Acceptance criteria | Concern | Latency, memory, and quality thresholds stay Proposed until approved. |
| 5 | CI testability | Concern | Logic runs on fakes and the iOS Simulator; microphone, interruptions, haptics, Action Button, and other apps need devices. |
| 6 | Privacy | Pass | Local only, retention off, local-only expiring clipboard item, snapshot cover, no history on iOS. |
| 7 | Permissions | Pass | Microphone only. No Accessibility, no Full Access, no background modes. |
| 8 | Feasibility | Concern | Main-app recording and copy are standard APIs. Cross-app keyboard dictation is not established; see below. |
| 9 | Out of scope | Pass | Keyboard, Live Activity, sync, Android, signing, and store submission are excluded. |
| 10 | Open decisions | Concern | See below. |

## Platform facts (Apple primary documentation)

| Fact | Source |
|---|---|
| Without Open Access a keyboard has "no access to microphone and speaker", cannot write the containing app's shared container (it can read it), and has no network. | [Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) |
| The Open Access capability list adds network, a writable shared container, Location, and Contacts. It does not add the microphone. Keystrokes become available to the developer. | same |
| A keyboard runs in an isolated process, inserts text only through `textDocumentProxy`, has a memory limit that varies by device, and may stay alive after it is dismissed. | [Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard) |
| `AudioRecordingIntent` is available from iOS 18; the app must start a Live Activity when recording begins and keep it for the whole recording, or the recording stops. | [AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent) |

Not established by Apple's documentation, and therefore not assumed: that a
keyboard can learn which app it is in, that an app can return the user to the
previous app, and that an Action Button shortcut can start a recording from a
fully backgrounded app (a developer-forum report says it cannot; unofficial).
Marketing claims from other products are not evidence of an architecture.

## Decisions to record (proposed defaults)

1. **Baseline** — iOS and iPadOS 26.0, arm64, matching the macOS 26 baseline
   (ADR 0001). That keeps Foundation Models and the Speech APIs available
   without fallbacks. Same Xcode 27 and Swift 6 strict-concurrency rules.
2. **Delivery** — explicit copy after review. No automatic paste (iOS has no
   Accessibility insertion) and no sending. The pasteboard item is local-only
   (no Universal Clipboard) and expires after 2 minutes (user choice 1, 2, or 10).
3. **Recording** — only while the app is in the foreground, with a visible
   state. Leaving the foreground ends the session and asks the user what to do
   with the partial recording. Maximum 5 minutes (Proposed).
4. **Shortcuts** — an App Intent that opens the app and starts recording once
   the scene is active; one-time, expiring launch request; device must be
   unlocked. Live Activity and `AudioRecordingIntent` are not adopted until the
   device evidence supports them.
5. **Keyboard** — not built in this epic. The most promising design to
   evaluate, because it needs neither the microphone nor Full Access: the main
   app records and writes the reviewed text to a shared container (the app
   writes, the keyboard only reads, which Apple allows without Open Access); the
   keyboard inserts it with `insertText`; the item expires instead of being
   deleted by the keyboard. Whether the user can return to the draft smoothly is
   unproven. E8-S1 decides.
6. **Models** — Tiny and Base on devices with 6 GB or more; Small only on iPads
   with 8 GB or more (Proposed; measured in E8-S5). Models are excluded from
   backup and verified before use. No new network path.
7. **Module reuse** — one package, `#if os(macOS)` guards inside five modules,
   no copied files, and no new module. Mobile-only types go in the existing
   module that owns their role. A new module would need its own ADR.
8. **Personalization** — local only. A Mac archive reaches the phone through
   Files or AirDrop. No iCloud sync in this epic.
9. **Bundle identifier** — `com.lemmetype.LemmeType.iOS` (to be recorded in ADR
   0027). Changing it later resets permission grants, as on the Mac.

## Risks

| Risk | Mitigation |
|---|---|
| The Whisper model exceeds the per-app memory limit on a small iPhone. | Check `os_proc_available_memory()` before loading; default to Tiny on 6 GB devices; unload on memory warning; measure in E8-S5. |
| Users expect keyboard dictation like other apps advertise. | Say plainly in the app and the ADR what is and is not supported; keep the copy and paste baseline. |
| Adding iOS to the package breaks the Mac build. | Guards only, no file moves; `make test-unit` test counts compared before and after (E8-S3). |
| CI simulator availability for the iOS job. | The job is non-blocking at first, like the UI tests. |

## AC → verification map

| Acceptance area | Verification |
|---|---|
| Baseline, Apple sources, keyboard decision | ADR 0027, `docs/testing/ios-feasibility.md` (manual, physical devices) |
| Shared modules build and test on iOS; Mac unchanged | `make build-ios`, `make test-ios`, `make test-unit`, `make lint` |
| Permission, interruptions, bounded session, cleanup | Audio-session and recorder tests with fakes; manual checklist for real calls and lock |
| Device fit, memory refusal, backup exclusion, verification | Device-profile and model-store tests (iOS Simulator) |
| Record, review, copy, feedback, failures | Quick Dictation view-model tests with a fake pasteboard; manual haptics and speech |
| Action Button, Back Tap, Shortcuts | Launch-request inbox tests; intent metadata checks; manual hardware steps |
| Modes, vocabulary, archive round trip | Shared corpus tests on iOS; archive round-trip test |
| Accessibility, iPad layout, privacy manifest, guardrails | UI tests on the iOS Simulator; screenshot checklist; `make network-check`, `make security-check`, `make l10n-check`, `make privacy-docs-check` |
| End to end, canaries, real-device matrix, thresholds | iOS end-to-end tests with fakes at the edges; manual matrix; approved thresholds |
