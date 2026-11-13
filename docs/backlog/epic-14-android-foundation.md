# Epic 14 — Android foundation and local Quick Dictation

## Epic issue body

### Objective

Prove what Android allows, then build a native Android app that records, transcribes
English on the device with whisper.cpp, and lets the user review and copy the result — with
no network permission at all. This covers Phases 0–3 of the
[Android plan](../android/android-plan.md) and [ADR 0035](../decisions/0035-android-app.md).

### Business value

Most LemmeType users who are not on iPhone are on Android, especially in India. A local,
network-silent dictation app is a clear difference from cloud dictation, and the same
models and rules as the Mac keep quality consistent.

### In scope

- Five time-boxed spikes with device evidence: whisper.cpp performance, microphone start
  paths, keyboard recording and insertion, model delivery without `INTERNET`, Swift SDK for Android.
- `android/` Gradle project, module rules, CI workflow, `make android-*` targets.
- `shared/fixtures/` JSON that Swift and Kotlin tests both read.
- Kotlin core: session, recorder state machine, engine contract, pipeline, Exact and Clean.
- Audio capture, a `microphone` foreground service with a visible notification, the whisper.cpp engine, model delivery and verification.
- Quick Dictation: record, stop, cancel, review, Copy, Share, Retry, Discard.
- Entry points: app shortcut, Quick Settings tile, home-screen widget, notification actions.
- Privacy and security checks from day one.

### Out of scope

- The keyboard build (Epic 15), modes and personalization UI, rewriting (Epic 16),
  languages other than English and cloud (Epic 17), Play release (Epic 18).
- Any change to Apple app behaviour. Apple-side work is limited to tests that read shared fixtures.
- Accessibility Service insertion, Android `SpeechRecognizer` in Local mode, analytics or crash SDKs.

### Epic acceptance criteria

- All child stories are accepted; spike results are in `docs/testing/android-feasibility.md`.
- A dictation works in airplane mode on two physical phones after the model is installed.
- The release manifest has no `INTERNET` permission, and `make android-check` fails if one is added.
- Exact and Clean pass the same shared fixture on Swift and Kotlin.
- No audio file remains after any ending (test).
- The Apple `make ci` is unchanged and green.

---

## E14-S1 — Prove whisper.cpp performance on Android phones

**Objective:** know whether local English Whisper is fast enough on the phones we target, before building on it.

**User story**

As the product owner, I want measured latency, memory, and heat for Whisper Tiny, Base, and
Small on real Android phones so that I can choose the default model and the minimum device.

**Scope**

- Throwaway spike app on a branch (not merged): whisper.cpp `v1.9.2` built from source with
  CMake and NDK r28+, `arm64-v8a`, release flags; JNI call that transcribes a WAV file.
- Same `ggml-*.en.bin` files as `ModelCatalog`, verified by SHA-256.
- Audio: synthetic sentences from `docs/testing/benchmark-corpus.json` rendered to 16 kHz WAV on the Mac.
- Measure per device class (section 11 of the plan): time to text for 5 s / 10 s / 30 s clips, real-time factor, peak memory, thread count sweep (2/4/6), temperature status after 10 runs.
- Check the `.so` is 16 KB aligned (`zipalign -c -P 16`, APK Analyzer).

**Acceptance criteria**

- Results for at least three phones (flagship, mid-range, 4 GB) are in the E14-S1 table.
- A recommended default model and thread count per class, with the numbers.
- 16 KB alignment check passes, and the app runs on the 16 KB emulator image.
- The plan's thresholds are confirmed or changed in the same PR.

**Dependencies:** none  
**Automated verification:** spike app's JNI smoke test on the emulator (x86_64 build); alignment script.  
**Physical-device verification:** the measurements above, recorded with device, Android version, date.  
**Estimate:** 5 points (Medium)

---

## E14-S2 — Prove the microphone start paths and endings

**Objective:** find which user actions can start a visible recording, and how each ending behaves.

**User story**

As an Android user, I want to start dictation from where I am (a tile, a widget, a shortcut)
and always see when the microphone is on, so that I trust the app.

**Scope**

- Spike app with: an activity that records; an activity that starts a `microphone`
  foreground service; a Quick Settings tile (activity path and direct-service path); a
  widget button; notification actions Stop and Cancel.
- Endings: call, Bluetooth headset change, screen lock, app swipe-away, notification
  dismissal, permission revoked, global microphone toggle off, Battery Saver, Android 17 audio hardening (`adb shell cmd audio set-enable-hardening throw`).
- Android 12, 14, and 16 or 17.

**Acceptance criteria**

- Each path and ending in the E14-S2 table is Demonstrated or Not supported, with the logcat line when refused (for example "Foreground service started from background can not have … microphone access").
- A recommended start design for E14-S11 and E14-S15.
- Silent-input detection (toggle off) is shown to work, with the threshold used.

**Dependencies:** none  
**Automated verification:** none required (spike).  
**Physical-device verification:** the table, on at least a Pixel and a Samsung.  
**Estimate:** 3 points (Small)

---

## E14-S3 — Prove keyboard recording and insertion

**Objective:** decide with evidence whether a LemmeType keyboard can record and insert on Android, because it is the best cross-app flow.

**User story**

As someone writing in WhatsApp, I want to tap a microphone key on my keyboard, speak, and
see the text in my draft so that I never switch apps.

**Scope**

- Spike `InputMethodService` with a mic key and a minimal typing row.
- Try: (a) `AudioRecord` inside the input method while its window is shown; (b) the input method starting a `microphone` foreground service.
- Insert a fixed synthetic sentence through `commitText` into WhatsApp, Google Messages,
  Samsung Messages, Gmail, Chrome (textarea and `contenteditable`), and Keep.
- Record `EditorInfo.packageName`, `inputType`, `imeOptions` in each; check password fields and `IME_FLAG_NO_PERSONALIZED_LEARNING`.
- Field switch during recording; keyboard hidden mid-recording; vendor battery kill.
- Read and record the Play policy position (Data safety, Accessibility not used, permissions).

**Acceptance criteria**

- Every row in the E14-S3 table has a result on at least two vendors.
- 20 dictations across 3 host apps: no text in the wrong field; the microphone indicator shows every time.
- ADR 0035's keyboard line moves to Accepted or Rejected, with the evidence.
- If rejected, Epic 15 is closed or rewritten before it starts.

**Dependencies:** none  
**Automated verification:** none required (spike).  
**Physical-device verification:** the table above; synthetic text only; nothing is sent.  
**Estimate:** 5 points (Medium)

---

## E14-S4 — Prove model delivery without the network permission

**Objective:** confirm beta 1 can have no `INTERNET` permission and still get its models.

**User story**

As a privacy-minded user, I want an app that cannot reach the network at all so that I do
not have to trust a promise.

**Scope**

- Spike app with no `INTERNET` permission; Base.en as a `fast-follow` asset pack, Tiny.en `on-demand`.
- Upload to an **internal testing** track (maintainer action); install from Play.
- Hash the delivered files against the catalog pins; then airplane mode; then a deliberate socket attempt.
- Fallback design if it fails: one allowlisted downloader with consent (ADR 0011 pattern).

**Acceptance criteria**

- The E14-S4 table is complete.
- The decision (asset packs, or downloader with `INTERNET`) is recorded in ADR 0035.
- If asset packs are used: local testing path for developers (`bundletool --local-testing`) is documented.

**Dependencies:** none; needs the maintainer's Play developer account (open decision D3)  
**Automated verification:** instrumentation test that a socket connect throws without `INTERNET`.  
**Physical-device verification:** install from internal testing on two phones; airplane-mode dictation.  
**Estimate:** 3 points (Small)

---

## E14-S5 — Measure the Swift SDK for Android for the shared domain

**Objective:** decide, with numbers, whether Swift `Domain` should run on Android instead of a Kotlin port.

**User story**

As a maintainer, I want to know the real cost of compiling the Swift domain for Android so
that we keep one copy of the rules only if it is cheap and safe.

**Scope**

- On a branch: build `Packages/LemmeTypeKit/Sources/Domain` with the Swift SDK for Android (Swift 6.4), no source changes.
- Call `TextCleaner` from Kotlin through a JNI bridge (swift-java or hand-written).
- Measure APK size increase, call cost, build time, CI setup, how async/actor APIs cross the bridge.

**Acceptance criteria**

- E14-S5 table complete.
- Pass rule: APK +≤ 15 MB, a 200-word cleanup call ≤ 5 ms, zero Apple source changes, Apple CI unchanged. Otherwise the Kotlin port stands.
- Result recorded as a note in ADR 0035 (adoption would need a new ADR).

**Dependencies:** none (not on the critical path)  
**Automated verification:** spike build on CI is optional.  
**Physical-device verification:** call-cost measurement on one phone.  
**Estimate:** 3 points (Small)

---

## E14-S6 — Create the Android project, module rules, and CI

**Objective:** a buildable, linted, tested Android project that cannot affect the Apple apps.

**User story**

As a developer, I want a clean Android project with enforced module rules so that every
later story lands in the right place.

**Scope**

- `android/` with Gradle Kotlin DSL, version catalog (`gradle/libs.versions.toml`, every version pinned), JDK 21, compile/target SDK 36, `minSdk` 31.
- Empty modules: `app`, `feature-dictation`, `feature-settings`, `core-domain`, `core-writing`, `core-diagnostics`, `core-testing`, `audio`, `speech-whisper`, `models`, `delivery`, `storage`, `system`.
- Module-graph check (core has no Android imports; features do not depend on adapters).
- ktlint, detekt, Android lint with warnings as errors.
- `make android-bootstrap`, `android-build`, `android-test`, `android-lint`, `android-check`.
- `.github/workflows/android.yml` (path-filtered), `ubuntu-latest`.
- `scripts/check-android-manifest.py` + `docs/security/android-permissions-allowlist.txt` (no `INTERNET`).
- Application id from decision D2. Release build minified (R8), debuggable false.

**Acceptance criteria**

- `make android-check` passes locally and in CI on an empty app that launches.
- Adding `INTERNET` to any manifest, or an exported component not allowlisted, fails the check (test of the script with fixtures).
- Adding an `android.*` import to a `core-*` module fails the build.
- Apple `make ci` unchanged.

**Dependencies:** E14-S1, E14-S4 (decides `INTERNET`)  
**Automated verification:** script fixture tests; CI run.  
**Physical-device verification:** app launches on one phone.  
**Estimate:** 5 points (Medium)

---

## E14-S7 — Share fixtures between Swift and Kotlin

**Objective:** stop the two implementations from drifting.

**User story**

As a maintainer, I want one set of test files both platforms must pass so that a rule change
on one side cannot silently differ on the other.

**Scope**

- `shared/fixtures/`: `cleanup-corpus.json` (from `TextCleanerTests` cases), `model-catalog.json`, `recorder-transitions.json`, `recognition-errors.json`. The mode, archive, and diagnostics-event fixtures move to the stories that use them (E16-S1, E16-S2, E14-S16).
- Swift: new tests only (in existing test targets) that assert each file equals what Swift produces. No Swift source changes.
- Kotlin: `core-testing` fixture loader.
- `README.md` in the folder: synthetic data only, how to regenerate, who reviews.

**Acceptance criteria**

- Swift `make test-unit` passes with the new tests; a deliberate edit to a fixture fails it.
- Kotlin loader reads every file.
- No real user text in any fixture (reviewed).

**Dependencies:** E14-S6  
**Automated verification:** both CIs.  
**Physical-device verification:** none.  
**Estimate:** 3 points (Small)

---

## E14-S8 — Port the core domain to Kotlin

**Objective:** the session, state machine, and engine contract that everything else uses.

**User story**

As a developer, I want the same recording and recognition rules as the Mac so that Android
behaves predictably and can be tested without a device.

**Scope**

- `core-domain`: `RecorderState`, `RecorderEvent`, `RecorderStateMachine` (from `recorder-transitions.json`), `DictationSession`, `DictationIssue` and actions, `RecordingLimits` (5 min), `SpeechEngine` contract, `RecognitionRunner` (never calls a not-ready engine; a cancelled session never succeeds), `TranscriptionPipeline` skeleton (engine → writing → result), `LanguageScope.englishOnly`, typed errors.
- `core-diagnostics`: event names from `diagnostics-events.json`, typed values, `id()` redaction.
- `core-testing`: `FakeSpeechEngine`, `SpeechEngineContract` (reusable checks), `FakeClock`.

**Acceptance criteria**

- Every allowed transition in the fixture passes; every other pair is rejected (test).
- `RecognitionRunner` contract tests mirror the Swift ones (not-ready, cancel, timeout).
- Diagnostics reject free text values (test).
- Coverage of `core-domain` ≥ 90 % lines.

**Dependencies:** E14-S7  
**Automated verification:** JVM tests in CI.  
**Physical-device verification:** none.  
**Estimate:** 5 points (Medium)

---

## E14-S9 — Port Exact and Clean writing to Kotlin

**Objective:** identical text output to the Mac for the same transcript.

**User story**

As a user, I want Clean Writing on Android to fix fillers and punctuation exactly as on my
Mac, and Exact to change nothing but spacing.

**Scope**

- `core-writing`: `TextCleaner` with Exact and Clean, ordered switchable `CleanupRule`s, protected spans (numbers, URLs, emails, identifiers, quotes), `CleanupTransformation` records naming the rule.
- `RepetitionLoop` (cut 4+ copies of a phrase, ADR 0028).

**Acceptance criteria**

- Every case in `cleanup-corpus.json` passes.
- Exact changes only whitespace (property test over random input).
- Protected spans never change (property test).

**Dependencies:** E14-S7, E14-S8  
**Automated verification:** JVM tests; fixture parity with Swift.  
**Physical-device verification:** none.  
**Estimate:** 5 points (Medium)

---

## E14-S10 — Capture audio safely

**Objective:** 16 kHz mono audio, on disk only while needed, with every interruption mapped.

**User story**

As a user, I want recording to stop cleanly when a call comes in or my headset changes, and
nothing of my voice left on the phone afterwards.

**Scope**

- `audio`: `AudioRecordSource` (`VOICE_RECOGNITION` source, 16 kHz mono; resample if the device refuses), Float32 conversion, level meter for the UI.
- `AudioCaptureService`: permission check, free-space check (≥ 100 MB as Apple), 0600 temp file in `noBackupFilesDir/sessions`, delete on every ending, purge at process start.
- Events: audio focus loss (call), route changes (`AudioDeviceCallback`), silent input (toggle off), max duration.
- Fake source for tests.

**Acceptance criteria**

- After stop, cancel, failure, interruption, and process restart, the sessions folder is empty (tests with the fake).
- Files are created owner-only (test).
- An all-zero first second ends with "microphone is off" (test).
- No audio buffer or file path appears in logs or diagnostics (canary test).

**Dependencies:** E14-S8, E14-S2  
**Automated verification:** JVM + Robolectric tests; emulator no-audio check.  
**Physical-device verification:** call, Bluetooth, toggle off on two phones (lifecycle table).  
**Estimate:** 5 points (Medium)

---

## E14-S11 — Keep recording visible with a foreground service

**Objective:** a recording that survives the user glancing at another app, always with a visible notification.

**User story**

As a user, I want to see a notification with Stop and Cancel whenever LemmeType is
listening, and I want the microphone off the moment I stop.

**Scope**

- `RecordingService`: type `microphone`, started only from a visible activity or an exempt user action (per E14-S2); not exported.
- Ongoing notification: elapsed time, mode name, Stop, Cancel. No transcript text ever.
- `POST_NOTIFICATIONS` asked with an explanation; without it the service still runs (Android shows it in the Task Manager) and the activity shows the state.
- Notification dismissed → stop and process (proposal from the threat model A-07).
- Service stops itself on every ending; `onTimeout` handled.

**Acceptance criteria**

- The service never records without its notification (instrumentation test).
- Stop from the notification ends capture within 300 ms (test with fake source).
- Starting from the background without an exemption shows an explanation instead of crashing (test).
- Manifest check allows exactly the needed FGS permissions.

**Dependencies:** E14-S10, E14-S2  
**Automated verification:** instrumentation tests on the emulator.  
**Physical-device verification:** notification Stop/Cancel, dismissal, lock screen on two phones.  
**Estimate:** 5 points (Medium)

---

## E14-S12 — Transcribe locally with whisper.cpp

**Objective:** the production Whisper engine behind the engine contract.

**User story**

As a user, I want my speech turned into text on the phone, offline, with the same model as
on my Mac.

**Scope**

- `speech-whisper`: CMake build of whisper.cpp `v1.9.2` fetched by tag and checked by SHA-256, NDK r28+, `arm64-v8a` (x86_64 for emulator tests only).
- JNI: load model from a verified path only, transcribe Float32 buffer, cancel, free.
- Decoding settings from ADR 0028 (non-speech tokens suppressed, fallback temperatures), `NoSpeechGate` threshold from the Swift value, thread count from E14-S1.
- `WhisperEngine` implements `SpeechEngine`; passes `SpeechEngineContract`.

**Acceptance criteria**

- Contract tests pass with a tiny test model on the emulator.
- A cancelled session never returns text (test).
- An unverified or modified model file is refused and deleted (test).
- Silence produces no text (test with a synthetic silent clip).
- 16 KB alignment passes for the release APK.

**Dependencies:** E14-S1, E14-S8  
**Automated verification:** instrumentation tests; alignment check.  
**Physical-device verification:** synthetic corpus run on two phones; numbers within E14-S1 thresholds.  
**Estimate:** 8 points (Large)

---

## E14-S13 — Deliver, verify, and remove models

**Objective:** models arrive safely and can be removed, without network code in beta 1.

**User story**

As a user, I want to see the model size before it downloads, know it is the genuine file,
and remove it to free space.

**Scope**

- `models`: catalog from `model-catalog.json`; asset-pack delivery (or the E14-S4 fallback); progress; Wi-Fi/cellular consent above 200 MB is the Play prompt.
- Verify SHA-256 before first use each launch; activate; remove; storage in `noBackupFilesDir/models`.
- Device fit by total RAM: Tiny ≥ 4 GB, Base ≥ 6 GB, Small ≥ 8 GB (Proposed, from E14-S1).
- Settings › Models screen (minimal).

**Acceptance criteria**

- A file whose hash does not match is deleted and reported (test).
- A model that does not fit is not offered, with the reason (test with fake memory).
- Remove frees the files (test).
- No network API in the module (network check).

**Dependencies:** E14-S4, E14-S12  
**Automated verification:** JVM + instrumentation tests; network check.  
**Physical-device verification:** install from internal testing; remove; reinstall.  
**Estimate:** 5 points (Medium)

---

## E14-S14 — Quick Dictation: record, review, Copy or Share

**Objective:** the first complete user flow.

**User story**

As a user, I want to tap Dictate, speak, check the text, and copy or share it into any app,
knowing nothing is sent for me.

**Scope**

- `feature-dictation` (Compose): first-run explanation, then the system microphone prompt; Start, Stop, Cancel; level meter and timer; review screen with Copy, Share, Retry (same audio), Discard.
- Mode choice: Exact or Clean (built-ins only in this story).
- Copy: `ClipData` with `EXTRA_IS_SENSITIVE`; confirmation text; clear the clip after the expiry (1, 2, or 10 minutes, default 2) only if it is still ours (device test for background clearing).
- Share: system chooser only; LemmeType never picks a target.
- Every `DictationIssue` from section 6.3 of the plan with its actions.

**Acceptance criteria**

- Each issue path has a view-model test with fakes; every failure leaves the clipboard unchanged and the sessions folder empty.
- Denied permission shows Open Settings and records nothing (test).
- Compose UI tests for the happy path and Cancel.
- TalkBack labels on every control (lint + manual).

**Dependencies:** E14-S9, E14-S11, E14-S12, E14-S13  
**Automated verification:** JVM view-model tests; Compose UI tests on the emulator.  
**Physical-device verification:** Copy then paste into WhatsApp, Messages, Gmail (not sent); clipboard clearing on Android 12 and 16.  
**Estimate:** 8 points (Large)

---

## E14-S15 — Start dictation from a tile, widget, and shortcut

**Objective:** fewer taps to start, using only paths E14-S2 proved.

**User story**

As a user, I want to start dictating from Quick Settings or my home screen so that I do not
hunt for the app.

**Scope**

- `DictationTileService` (`BIND_QUICK_SETTINGS_TILE`), using `TileServiceCompat.startActivityAndCollapse` with a `PendingIntent`.
- Home-screen widget (Glance) with one Dictate button.
- Static app shortcut "Dictate".
- A one-time launch request that expires after 10 seconds (like iOS `LaunchRequestInbox`), so a stale tap never starts a recording later.
- Requires an unlocked phone.

**Acceptance criteria**

- Each entry point starts a visible recording within 1 s on the reference phone (device test).
- An expired request does not start recording (test).
- From the lock screen, the user is asked to unlock first (device test).

**Dependencies:** E14-S14, E14-S2  
**Automated verification:** JVM tests for the request expiry; instrumentation test for the tile intent.  
**Physical-device verification:** each entry point on Pixel and Samsung; one vendor launcher.  
**Estimate:** 3 points (Small)

---

## E14-S16 — Enforce privacy and security from day one

**Objective:** the Android version of the Apple guardrails, in CI.

**User story**

As a user, I want proof — not a promise — that this app cannot send my voice or text
anywhere.

**Scope**

- `scripts/check-android-network.sh` + `docs/security/android-network-allowlist.txt` (empty in beta 1).
- `scripts/check-android-security.py` + `docs/security/android-dependencies-allowlist.txt` (reason per line; analytics/ads/crash group ids banned).
- Manifest check extended: backup off or excluded, no cleartext, no accessibility service, exported components allowlisted.
- Canary tests across capture, recognition (fake), writing, review, Copy.
- Socket test: full dictation with fakes opens no socket and `TrafficStats` for our uid is unchanged.
- `scripts/check-android-no-audio.sh` on the emulator.
- Android rows A-01 … A-15 drafted in `docs/security/threat-model.md` with real check names.

**Acceptance criteria**

- Each script has fixture tests that prove it fails on a bad input.
- All checks run in `make android-check` and the Android CI job.
- `make privacy-docs-check` passes with the Android rows.

**Dependencies:** E14-S6, E14-S14  
**Automated verification:** the scripts and tests themselves.  
**Physical-device verification:** none (privacy device checks are in E18-S1).  
**Estimate:** 5 points (Medium)

---

## Epic 14 story order

1. E14-S1
2. E14-S2
3. E14-S3
4. E14-S4
5. E14-S5
6. E14-S6
7. E14-S7
8. E14-S8
9. E14-S9
10. E14-S10
11. E14-S11
12. E14-S12
13. E14-S13
14. E14-S14
15. E14-S15
16. E14-S16
