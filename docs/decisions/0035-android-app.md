# 0035 — Android app: native Kotlin, shared contracts, local first

- Status: **Proposed.** The maintainer approves it before any Android code is merged.
  Items marked *spike* stay Proposed until their device evidence is in
  [`docs/testing/android-feasibility.md`](../testing/android-feasibility.md).
- Date: 2026-11-13
- Plan: [`docs/android/android-plan.md`](../android/android-plan.md)
- Stories: Epics 14–18 (`docs/backlog/epic-14-android-foundation.md` … `epic-18-android-beta-release.md`)
- Related: ADR 0027 (iPhone baseline), 0029 (English-only beta), 0030 (shared transcription
  foundation, Proposed), 0031 and 0033 (cloud speech and gateway), 0032 (iOS keyboard), 0034 (StoreKit)

## Context

LemmeType runs on the Mac and on iPhone and iPad from one Swift package
(`Packages/LemmeTypeKit`). Android users are the next audience, especially in India, where
Telugu and Hindi matter. Android allows things iOS does not (a keyboard can use the
microphone; a keyboard is told which app it is in) and forbids or restricts others
(no microphone from the background; the default speech recognizer may use a server).

## Decision

| Item | Choice |
|---|---|
| Technology | Native Android: Kotlin, Jetpack Compose, Coroutines and Flow, platform APIs. No Flutter, React Native, or Kotlin Multiplatform |
| Code sharing with Apple | **Contracts, not code.** Shared JSON fixtures and schemas (cleanup corpus, model catalog pins, mode and archive formats, corpus manifests, diagnostics event names, gateway OpenAPI). Both sides test against the same files. Apple code is not changed to make this work |
| Swift on Android | Not adopted now. The Swift SDK for Android is official (Swift 6.3+), so a time-boxed spike (E14-S5) measures compiling `Domain` for Android. It can only be adopted by a later ADR |
| Speech (Local) | whisper.cpp through the NDK (JNI), the same `ggml-*.en.bin` files and SHA-256 pins as `ModelCatalog`. English Base is the default |
| System recognizer | Not used in Local mode. Android documents that `SpeechRecognizer` "is likely to stream audio to remote servers"; the on-device variant runs in another app whose network use LemmeType cannot verify |
| Rewriting | Optional, through ML Kit GenAI (Gemini Nano) where the device supports it; otherwise "unavailable" with the reason. Never needed for Exact or Clean |
| Repository | `android/` in this repository, its own Gradle build and CI workflow. `make ci` for Apple is unchanged |
| SDK levels | `minSdk 31` (Android 12), `targetSdk 36` (Play requirement from 2026-08-31), tested on Android 17. arm64-v8a only for release |
| Network, beta 1 | **No `INTERNET` permission.** English models come through Play asset delivery and are hashed against the catalog pins (*spike* E14-S4). If the spike fails, a single allowlisted downloader file with user consent, as on Apple |
| Recording | Visible at all times: an activity on screen or a `microphone` foreground service with an ongoing notification (Stop, Cancel). Started only from a user action |
| Delivery | Review then Copy (marked sensitive), Share, or — from the LemmeType keyboard — one `commitText` into the field that was focused when recording started |
| Keyboard | A LemmeType input method with a microphone key, **only if** E14-S3 proves recording and insertion on devices. No Accessibility Service for insertion |
| Cloud | Not in beta 1. Later, opt-in through the existing gateway (ADR 0033) with its own consent, a Play Billing proof, and a separate allowlisted network module |
| Languages | English only in beta (ADR 0029 `LanguageScope.englishOnly`). Indian languages after measurement |

## Platform facts this rests on (official sources, read 2026-11-13)

- A `microphone` foreground service needs `FOREGROUND_SERVICE_MICROPHONE` and the
  `RECORD_AUDIO` grant, and cannot be created from the background except in listed cases
  (notification, widget, system component). [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types),
  [Background start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- Being the current input method exempts an app from the *background start* rule, but it is
  not listed among the *while-in-use* exemptions, so microphone access from a keyboard
  needs a device test. [Background start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- An input method commits text through `InputConnection.commitText` and reads the field type
  from `EditorInfo.inputType`; `EditorInfo.packageName` names the app that owns the field;
  `IME_FLAG_NO_PERSONALIZED_LEARNING` asks the keyboard not to learn.
  [Create an input method](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method),
  [EditorInfo](https://developer.android.com/reference/android/view/inputmethod/EditorInfo)
- Android 17 requires a visible activity or a non-short foreground service for background
  audio focus and playback. [Background audio hardening](https://developer.android.com/about/versions/17/changes/bg-audio)
- Play allows `isAccessibilityTool` only for disability tools; other uses need disclosure,
  a declaration, and must not work around security controls.
  [Use of the AccessibilityService API](https://support.google.com/googleplay/android-developer/answer/10964491)
- Native code must support 16 KB pages; updates without it are blocked from 2027-02-01.
  NDK r28+ aligns by default. [Support 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes)

## Alternatives considered

| Option | Why not (now) |
|---|---|
| Kotlin Multiplatform for the domain | The domain already exists in Swift. KMP would mean rewriting it once more for Apple or keeping two copies anyway. No Apple gain |
| Flutter or React Native | A second UI stack and a bridge for every platform service the app is made of (audio, foreground service, keyboard, JNI) |
| Swift `Domain` compiled for Android | Real reuse of ~7,000 tested lines, but adds the Swift runtime and Foundation to the APK, a JNI bridge for async APIs, and ties Apple CI to Android. Measured in spike E14-S5 |
| Accessibility Service insertion (like the Mac) | Play restricts it; LemmeType is not a disability tool; a keyboard is the supported way to insert |
| Android `SpeechRecognizer` as the Local engine | May use a server; its network use cannot be tested by LemmeType |

## Consequences

- Pure logic (cleanup, personalization, snippets, modes, the recorder state machine, the
  repetition and no-speech guards) exists twice: Swift and Kotlin. Shared golden fixtures
  are the guard against drift; a fixture change needs both sides green.
- The Android beta can claim network silence by construction (no `INTERNET` permission),
  which a CI check enforces. Adding cloud speech later removes that and needs the same
  code-confinement checks as Apple.
- Android work never blocks an Apple release: separate workflow, separate `make android-*` targets.
