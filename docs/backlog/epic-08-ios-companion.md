# Epic 8 — iPhone and iPad companion

## Epic issue body

### Objective

Let a user dictate on an iPhone or iPad with the same local processing and
writing modes as on the Mac, review the text, and copy it into any app —
without audio or text leaving the device.

### Business value

Most messages are written on a phone, where typing is slow and the usual
alternative, cloud dictation, sends speech to a server. A local Quick Dictation
flow, one press of the Action Button away, brings the Mac's privacy promise to
mobile without pretending that iOS allows what it does not.

### In scope

- A recorded decision, backed by real-device evidence, on which cross-app
  workflows iOS supports with public APIs (E8-S1).
- The shared Swift package building for iOS and iPadOS 26 while the macOS app
  is unchanged.
- An iPhone and iPad app target: microphone permission, a bounded audio
  session, local recognition (Apple Speech and Whisper), and model download and
  storage.
- Quick Dictation: record, stop, cancel, review, and copy with clear feedback.
  Nothing is ever sent.
- Action Button, Back Tap, and Shortcuts through App Intents, opening a visible
  recording.
- Modes, vocabulary, replacements, snippets, cleanup, language and output, and
  tone and style reused from the shared modules, and import of the Mac's
  personalization archive.
- Accessibility, privacy controls, iPad layout, and network and security
  guardrails for the iOS target.
- Validation on real devices and approved thresholds.

### Out of scope

- A custom keyboard extension, Full Access, a Live Activity, and any
  background recording. They are built only if E8-S1 proves them with public
  APIs; separate stories are then written.
- Android, watchOS, Mac Catalyst, a Control Center widget, a share extension,
  and iCloud or any other sync.
- Cloud or Private Cloud Compute processing, background always-listening,
  private APIs, and automatic sending of messages.
- Languages beyond the Epic 9 evaluation set.
- iOS signing, TestFlight, and App Store submission (a follow-up story once the
  thresholds are approved).

### Epic acceptance criteria

- All child stories are accepted.
- Quick Dictation records and processes locally in the iOS app, and works in
  airplane mode once its assets are installed.
- The result is copied only on request, with clear completion feedback; the
  clipboard item stays on the device and expires.
- Modes, vocabulary, cleanup, language and output, and style come from the same
  shared modules as the Mac; the macOS build, tests, and release checks still
  pass.
- The keyboard decision is recorded with evidence before Full Access is
  requested anywhere; no keyboard ships without it.
- Per-device quality, latency, and memory thresholds are approved and the
  real-device matrix is complete.

---

## E8-S1 — Prove a supported iOS cross-app voice-writing workflow

**User story**

As an iPhone user, I want an honest, supported way to dictate for WhatsApp and
Messages so that I understand the steps and limitations before enabling a
keyboard.

**Scope**

- A time-boxed feasibility spike and ADR 0027, not a promise of seamless
  dictation in every app. Evaluate main-app recording, Shortcuts and App
  Intents, and an optional custom keyboard, keeping main-app Quick Dictation
  with explicit copy and paste as the baseline.
- ADR 0027 records the platform baseline (iOS and iPadOS 26.0, arm64, physical
  test devices), the bundle identifier, the delivery baseline, and the
  keyboard decision, each with its Apple source.
- Desk evidence from Apple's primary documentation is kept apart from device
  evidence. Known so far: a keyboard without Open Access has no microphone or
  speaker and can only read the app's shared container; Open Access adds
  network and a writable shared container but not the microphone; a keyboard
  inserts text through `textDocumentProxy` and is not told which app it is in;
  `AudioRecordingIntent` (iOS 18 and later) requires a Live Activity for the
  whole recording.
- `docs/testing/ios-feasibility.md` is the device-evidence record: for each
  path it lists the exact taps and app switches and marks the result
  Demonstrated, Not demonstrated, or Not supported, with device, OS version,
  and date.
- Transcription, translation, and rewriting are assessed for on-device
  feasibility separately.

**Acceptance criteria**

- The ADR records the minimum iOS version, physical devices, API and
  entitlement requirements, Full Access requirements, and App Review
  constraints, each citing current Apple documentation.
- On physical hardware, starting from a WhatsApp or Messages draft, the record
  shows: start recording through a supported path, stop or cancel, return by a
  supported user flow, and insert or explicitly copy and paste the result
  without sending it.
- Every app switch and tap is documented; demonstrated behaviour is
  distinguished from proposals. Nothing assumes a keyboard can capture audio or
  identify and return to its host app.
- Secure fields, phone-pad fields, apps that reject custom keyboards,
  permission denial and revocation, app termination, device lock, audio
  interruptions, and keyboard dismissal are tested, with unavailable cases and
  their fallback documented.
- Visible recording state, a bounded session lifetime, cancellation and timeout
  cleanup, and prevention of a stale result appearing in another app or session
  are shown.
- The ADR states whether a keyboard can meet the workflow with public APIs and
  current App Review rules. If not, it records that and keeps explicit main-app
  delivery.
- The ADR is Accepted for the main-app baseline when it merges; the keyboard,
  Live Activity, and background-recording decisions stay Proposed until their
  device evidence is recorded.

**Verification:** the ADR and `docs/testing/ios-feasibility.md`. A simulator
alone is not evidence. Use synthetic speech and text only; no user messages in
diagnostics or committed files.

**Dependencies:** E2-S1 (domain contracts, audited for macOS-only dependencies)  
**Estimate:** 5 points

---

## E8-S3 — Build the shared modules for iPhone and iPad

**User story**

As a developer, I want the shared Swift modules to build and test for iOS
without forking them so that the iPhone app reuses the Mac's recognition,
writing, and personalization logic.

**Scope**

- `LemmeTypeKit` declares iOS 26 next to macOS 26. A probe on 2026-11-02 showed
  `Domain`, `Support`, `ModelAssets`, and `Editing` already build for the iOS
  Simulator unchanged.
- `Audio`, `Permissions`, `Recognition`, `UI`, and `TestSupport` keep their
  macOS-only code (Core Audio device selection, Accessibility, AppKit windows
  and panels, the libproc socket probe) behind `#if os(macOS)`, with an iOS
  counterpart only where shared code needs a symbol. No file is duplicated.
- `Delivery`, `Shortcuts`, `Lifecycle`, and `Updates` stay macOS-only and are
  not linked by the iOS app.
- `make build-ios` and `make test-ios` run on the iOS Simulator, and CI gets a
  non-blocking job for them. `make ci` is unchanged.
- ADR 0027 holds the portability audit (module, iOS status, reason). The module
  table in `CLAUDE.md` and the coding-standards skill is updated.

**Acceptance criteria**

- Every module the iOS app links builds for the iOS Simulator with warnings as
  errors (`make build-ios`).
- `make lint` and `make test-unit` on macOS pass with no test removed or
  skipped.
- The tests of `Domain`, `Support`, `ModelAssets`, and `Editing` run on the iOS
  Simulator and pass (`make test-ios`).
- `Domain` and `Support` contain no `#if os(` conditionals.
- The macOS app builds, and its hosted app tests pass, unchanged.
- No new third-party dependency and no new network code.

**Dependencies:** E8-S1  
**Estimate:** 5 points

---

## E8-S4 — Add the iOS app target, microphone permission, and a bounded audio session

**User story**

As an iPhone user, I want LemmeType to ask for the microphone only when I start
dictating and to record only while I can see it so that nothing listens in the
background.

**Scope**

- A `LemmeTypeiOS` app target (XcodeGen) with `IOSComposition` as its
  composition root. Info.plist has `NSMicrophoneUsageDescription` and no
  background modes.
- `AVAudioSessionSource` implements `AudioSource` for iOS: record category,
  interruptions and route changes mapped to `AudioSourceEvent`, and the session
  deactivated on stop. The 16 kHz mono float format and the free-space check
  are the existing ones.
- iOS implementations of the microphone permission protocols, with the denied
  and restricted states and an Open Settings action.
- `RecordingLimits`: a maximum duration (5 minutes, Proposed). Recording ends
  on cancel, timeout, interruption, route loss, the scene leaving the
  foreground, and a memory warning.
- A recording that ended for a reason the user did not choose is kept in the
  app's protected temporary directory only until they choose Process or Discard,
  and is removed at the next launch.

**Acceptance criteria**

- The first start shows an in-app explanation and then the system prompt. If
  permission is denied, nothing records and the message offers Open Settings.
  Permission revoked while recording stops the session (tests with a fake
  authorizer).
- Each ending above leaves the recorder in the documented state, including
  `needsAttention` for an unrequested stop (tests with a fake audio session
  and a manual clock).
- No session can exceed the maximum duration (test).
- The Info.plist declares the microphone string and no `UIBackgroundModes`,
  and a change to either fails `make security-check`.
- After every ending the temporary directory holds no audio (test), and
  recordings are excluded from backup.
- Real behaviour of calls, Siri, headset removal, and screen lock is listed in
  the manual acceptance checklist.

**Dependencies:** E8-S3, E1-S5, E1-S6  
**Estimate:** 5 points

---

## E8-S5 — Recognise speech locally and manage models on iPhone and iPad

**User story**

As an iPhone user, I want dictation to run on my device with a model that suits
it so that speech never leaves the phone and the app does not run out of
memory.

**Scope**

- Apple Speech (on device only) and the Whisper engine run on iOS from the
  shared code; the engine contract tests run on the iOS Simulator.
- A device profile for iOS (memory class, thermal state, Low Power Mode, and
  available memory from `os_proc_available_memory()`) feeds the existing
  `PerformancePlan` and `ModelFit`. Proposed: Tiny and Base on devices with 6 GB
  or more, Small only on iPads with 8 GB or more.
- A model is not loaded when the available memory is below its estimate plus a
  margin; the user sees why and what to do.
- Model files live in Application Support, excluded from backup, verified by
  SHA-256 exactly as on the Mac. Downloads use the one allowlisted downloader,
  only in the foreground, with consent and the size shown; on a constrained or
  expensive network the user is asked again.
- Idle unload and memory-warning unload use the existing residency controller.
- Settings › Models lists size, fit for this device, and install and remove.

**Acceptance criteria**

- Fit and the default model are correct for each device class (table-driven
  tests with injected profiles).
- A load with too little available memory is refused and loads nothing (test).
- A modified model file is deleted and not used; a new download needs consent
  (reused store tests, run on iOS).
- A memory warning unloads an idle model and does not interrupt a session in
  progress (test).
- Backup exclusion is asserted for the model and temporary directories.
- English, and Hindi and Telugu when a multilingual model is installed, show
  the same readiness reasons as on the Mac (reused `LanguageReadiness` tests).
- Transcription in airplane mode after install is in the manual checklist.

**Dependencies:** E8-S3, E8-S4, E5-S1, E5-S4, E9-S2  
**Estimate:** 8 points

---

## E8-S6 — Quick Dictation: record, review, and copy

**User story**

As an iPhone user, I want to tap, speak, review the text, and copy it with a
clear confirmation so that I can paste it into any app myself.

**Scope**

- A Quick Dictation screen: Record, Stop, Cancel, a level meter, elapsed time,
  the processing stage, then the result with Copy, Dictate Again, and Discard.
  It shows the mode, language, and output in use and, when something cannot run,
  the reason (`LanguageReadiness`, rewriter availability).
- The shared recorder state machine, session, and transcription pipeline are
  used as they are. Delivery on iOS is an explicit copy: a pasteboard
  implementation of `TextDelivering` that never inserts into another app and
  never sends. There is no target capture on iOS.
- Copy writes a local-only item that expires (2 minutes, Proposed; choices of 1,
  2, and 10 minutes) and confirms with a visible state, a haptic, and a
  VoiceOver announcement that names the expiry.
- Translated and restyled results always open in review with the original one
  tap away (the Epic 9 and 10 review behaviour).
- The result is hidden in the app-switcher snapshot and cleared on Discard,
  after Copy and Done, on timeout, and on the next session.

**Acceptance criteria**

- Record, stop, cancel, and every failure path reach the right screen state
  (view-model tests over the shared state machine).
- Copy writes exactly the reviewed text once, with the local-only and
  expiration options (test with a fake pasteboard); a failed copy says so.
- The completion feedback has a visible, a haptic, and a spoken form (tests of
  the feedback model; haptic and speech in the manual checklist).
- An unavailable combination is refused before recording starts, with the reason.
- A cancelled or failed session writes nothing to the pasteboard.
- The result is not logged, not in diagnostics, and not in the snapshot (canary
  tests).

**Dependencies:** E8-S4, E8-S5, E2-S7, E9-S5, E10-S4  
**Estimate:** 8 points

---

## E8-S7 — Start dictation from the Action Button, Back Tap, and Shortcuts

**User story**

As an iPhone user, I want to start dictating with the Action Button, a Back Tap,
or Siri so that I can begin without finding the app.

**Scope**

- An App Intent, `StartQuickDictationIntent`, and an `AppShortcutsProvider`
  with spoken phrases. The intent opens the app in the foreground and
  requires the device to be unlocked.
- The intent leaves a one-time launch request that expires after a few
  seconds. The app consumes it when its scene becomes active, and starts
  recording only if the microphone is authorized and the chosen combination can
  run. Otherwise it shows the ready screen with the reason.
- A short in-app guide to assigning the shortcut to the Action Button and to
  Back Tap (both run a Shortcut; neither calls LemmeType directly).
- No Live Activity, no `AudioRecordingIntent`, and no background recording
  unless E8-S1 proves them.

**Acceptance criteria**

- A launch request is consumed once, and an expired request starts nothing
  (inbox tests with a manual clock).
- With the microphone denied, or a model missing, the request shows the reason
  and does not record (tests).
- The intent requires an unlocked device and opens the app; its metadata and
  shortcut phrases are validated by tests and by `make security-check`.
- Recording started this way shows the same visible state as a tap on Record.
- Action Button, Back Tap, Siri, the Shortcuts app, and a locked device are in
  the manual checklist.

**Dependencies:** E8-S6  
**Estimate:** 5 points

---

## E8-S8 — Use modes, vocabulary, and cleanup on iPhone and iPad

**User story**

As an iPhone user, I want my modes, vocabulary, replacements, and snippets to
apply to dictation on my phone so that it writes my words the way the Mac does.

**Scope**

- The shared `PersonalizationLibrary`, its file store, and the mode resolver run
  on iOS. The default mode is chosen in Settings; the built-in Exact, Clean, and
  Message modes work, and custom modes keep their language, output, and style.
- Screens to view, add, edit, and delete vocabulary, replacements, and snippets,
  using the existing validation.
- Import of a personalization archive exported from the Mac (Files or AirDrop),
  with the existing merge preview; Export and Delete All on the phone.
- Per-app mode rules do not apply on iOS, where the host app is unknown. They
  are hidden and preserved untouched by import and export.

**Acceptance criteria**

- Vocabulary, replacements, snippets, and the Clean rules change the output
  exactly as on the Mac (the shared corpus tests run on iOS).
- A Mac archive imports on iOS and exports back unchanged, including mode rules
  (round-trip test).
- Invalid entries are rejected with the existing messages.
- Delete All removes the library file and leaves no copy (test).
- Personalization is never logged or put in diagnostics (canary test).

**Dependencies:** E8-S6, E4-S4, E4-S6, E4-S8  
**Estimate:** 5 points

---

## E8-S9 — Make the companion accessible, private, and iPad-ready

**User story**

As a user of VoiceOver, large text, or an iPad, I want the same dictation flow
to work for me, and as any user I want the app to show exactly what it keeps.

**Scope**

- VoiceOver labels and announcements for every recording state and result;
  Dynamic Type including the accessibility sizes; Reduce Motion; Increase
  Contrast. No state is communicated by colour or animation alone.
- An adaptive iPad layout (split navigation, resizable windows, Stage Manager)
  using the same view models.
- Privacy overview with the plain-language permission text, Delete All Local
  Data, and a statement that history is not kept on iOS.
- A privacy manifest (`PrivacyInfo.xcprivacy`) that declares no tracking and no
  collected data, and the required-reason APIs the code uses.
- `make network-check`, `make security-check`, `make l10n-check`, and
  `make privacy-docs-check` cover the iOS target: network use, Info.plist keys,
  entitlements, dependencies, string catalog, and the threat model.

**Acceptance criteria**

- Every control has a label and an identifier; recording, processing, result,
  and failure are announced (view-model and UI tests on the iOS Simulator).
- The layout is usable at the largest accessibility text size and at iPad
  compact and regular widths (screenshot checklist).
- Delete All Local Data removes models, the library, and settings, and the app
  returns to first run (test).
- The privacy manifest matches the code: the checker fails on an undeclared
  required-reason API (script test).
- A network API in an iOS file outside the allowlist, an unreviewed Info.plist
  key, or an unlocalized string fails the matching `make` check.
- The threat model and privacy checklist describe the iOS data flows.

**Dependencies:** E8-S6, E8-S8, E6-S2, E6-S5, E6-S7, E6-S8, E7-S6, E7-S7  
**Estimate:** 5 points

---

## E8-S2 — Deliver and validate the approved iPhone voice-writing flow

**User story**

As an iPhone user, I want to speak, optionally translate to English and adjust
tone, then place reviewed text in a WhatsApp or Messages draft without sending
it automatically.

**Scope**

- This is the validation capstone of the epic. The implementation work first
  described in this issue is split into E8-S3 to E8-S9; this story proves that
  they work together on real devices and fixes the thresholds. Issue #85 keeps
  its number and title.
- End-to-end tests with fakes at the iOS edges (audio session, permission,
  pasteboard, scene phase): Quick Dictation with each built-in mode, a
  translation with review, a styled result with review, a launch request from
  the Action Button, a missing model, a revoked permission, an interruption,
  a memory warning, and cancellation.
- A network-silence check for the iOS flow and privacy canary tests across
  recording, recognition, translation, styling, review, and copy.
- A real-device matrix: copy and paste into WhatsApp, Messages, Notes, and
  Safari; secure fields; unsupported hosts; revoked permissions; offline use
  after install; interruptions; low memory; and recovery.
- Per-device quality, capture-stop-to-result latency, peak memory, and battery
  thresholds, Proposed until the product owner approves them.

**Acceptance criteria**

- Each scenario above has an end-to-end test; every failure leaves the
  pasteboard unchanged and deletes temporary audio.
- Canary tests show no audio, transcript, translation, or clipboard content in
  logs, diagnostics, errors, or the snapshot.
- Translation and tone and style are selectable only where the device supports
  them; otherwise the screen shows "unavailable" with the reason and implies no
  parity.
- The device matrix is completed on at least one iPhone and one iPad and the
  results are recorded in `docs/testing/ios-feasibility.md`.
- Thresholds exist per device class and are marked Proposed. Acceptance of
  Epic 8 needs them approved.
- The macOS build, tests, and release checks still pass.

**Dependencies:** E8-S1, E8-S3 through E8-S9, E9-S6, E10-S5  
**Estimate:** 5 points

## Epic 8 story order

1. E8-S1
2. E8-S3
3. E8-S4
4. E8-S5
5. E8-S6
6. E8-S7
7. E8-S8
8. E8-S9
9. E8-S2
