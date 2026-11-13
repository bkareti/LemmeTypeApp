# Android feasibility and device evidence

The record for the Phase 0 spikes (E14-S1 … E14-S5) and later device checks
([ADR 0035](../decisions/0035-android-app.md), [plan](../android/android-plan.md)).
An emulator is not evidence for microphone, keyboard, battery, or vendor behaviour: every
row in the device tables is filled in on a physical phone with **synthetic speech and test
text only**. No real messages, names, or recordings go in this file or in a pull request.

Status words: **Demonstrated** (done and recorded), **Not demonstrated** (not yet tried),
**Not supported** (tried; the platform or vendor does not allow it, with the evidence).

## Desk evidence (official documentation, 2026-11-13)

| Question | Answer | Source |
|---|---|---|
| What does a microphone foreground service need? | `FOREGROUND_SERVICE_MICROPHONE`, type `microphone`, the `RECORD_AUDIO` grant | Foreground service types |
| Can it be created from the background? | No, except listed cases: system component, widget, notification, a visible app's `PendingIntent` | Background start restrictions |
| Is the current input method exempt? | From the *background start* rule, yes. It is not in the *while-in-use* exemption list | Background start restrictions |
| How does a keyboard insert text? | `InputConnection.commitText` | Create an input method |
| Does a keyboard know the host app? | Yes, `EditorInfo.packageName` | EditorInfo |
| Is the default `SpeechRecognizer` local? | Not guaranteed: "likely to stream audio to remote servers" | SpeechRecognizer |
| What happens with the global microphone toggle off? | Apps get silent audio | Explain access to more sensitive information |
| Background audio focus on Android 17? | Needs a visible activity or a non-short foreground service | Background audio hardening |
| Native code page size | Must support 16 KB; updates blocked from 2027-02-01 otherwise | Support 16 KB page sizes |
| Asset pack size | Up to 1.5 GB per AI pack (compressed) | Play for On-device AI |

## Test devices

| Device | Android | RAM | Vendor skin | Tester | Date |
|---|---|---|---|---|---|
| _Pixel (9 or 10)_ | | | | | |
| _Samsung Galaxy A (6–8 GB)_ | | | | | |
| _Xiaomi / Redmi_ | | | | | |
| _4 GB low-end_ | | | | | |

## E14-S1 — whisper.cpp on Android

| Device | Model | 10 s utterance → text | Real-time factor | Peak memory above idle | Thermal after 10 runs | Result |
|---|---|---|---|---|---|---|
| | Tiny.en | | | | | Not demonstrated |
| | Base.en | | | | | Not demonstrated |
| | Small.en | | | | | Not demonstrated |

## E14-S2 — Microphone paths

| Path | Android 12 | Android 14 | Android 16/17 | Notes |
|---|---|---|---|---|
| Activity on screen records | Not demonstrated | | | Baseline |
| Activity starts `microphone` FGS, then user leaves the app; recording continues with notification | Not demonstrated | | | |
| Quick Settings tile → activity → FGS | Not demonstrated | | | |
| Quick Settings tile → FGS directly, no activity | Not demonstrated | | | Expected to fail while-in-use |
| Widget button → FGS | Not demonstrated | | | Listed exemption |
| Notification action Stop / Cancel | Not demonstrated | | | |
| Global microphone toggle off → silent input detected | Not demonstrated | | | |

## E14-S3 — Keyboard

| Question | Result | Evidence |
|---|---|---|
| IME records with `AudioRecord` while its window is shown | Not demonstrated | |
| IME starts a `microphone` FGS and records | Not demonstrated | |
| Microphone indicator visible during IME recording | Not demonstrated | |
| `commitText` inserts in WhatsApp, Google Messages, Samsung Messages, Gmail, Chrome textarea, Keep | Not demonstrated | |
| Password fields are detected by `inputType` in each host | Not demonstrated | |
| Host switches field during recording; guard prevents wrong insert | Not demonstrated | |
| Banking app / work profile rejects the keyboard; fallback shown | Not demonstrated | |
| Vendor battery manager kills the IME process mid-recording | Not demonstrated | |

## E14-S4 — Model delivery and network silence

| Question | Result | Evidence |
|---|---|---|
| Asset pack (fast-follow) delivers Base.en through internal testing | Not demonstrated | |
| App has no `INTERNET` permission and delivery still works | Not demonstrated | |
| Delivered file SHA-256 equals the catalog pin | Not demonstrated | |
| Airplane mode after install: dictation works | Not demonstrated | |
| A socket attempt from the app fails without `INTERNET` | Not demonstrated | |

## E14-S5 — Swift SDK for Android

| Measure | Result |
|---|---|
| `Domain` builds for `aarch64-unknown-linux-android` unchanged | Not demonstrated |
| APK size increase | |
| JNI call cost (cleanup of 200 words) | |
| Async/actor APIs callable from Kotlin | |

## Lifecycle and failure matrix (after Phase 2)

| Event | Expected | Result |
|---|---|---|
| Incoming call | Stop, delete partial, Try Again | Not demonstrated |
| Bluetooth headset connect/disconnect | Stop, delete partial, Try Again | Not demonstrated |
| Screen lock during an activity recording | Stop and process | Not demonstrated |
| Notification dismissed (Android 13+) | Recording stops | Not demonstrated |
| Permission revoked in Settings | Process killed; next launch purges audio, shows a notice | Not demonstrated |
| Force stop during processing, relaunch | No audio left | Not demonstrated |
| Low memory | Model refused with a reason, no crash | Not demonstrated |
| Five-minute limit | Stop and process; user told | Not demonstrated |
| Airplane mode | Works | Not demonstrated |

## Proposed thresholds (not approved)

| Metric | Flagship (8 GB+) | Mid-range (6–8 GB) | Low end (4 GB) |
|---|---|---|---|
| Stop to text, 10 s utterance | ≤ 4 s (Base.en) | ≤ 7 s (Base.en) | ≤ 6 s (Tiny.en) |
| Peak memory above idle | ≤ 650 MB | ≤ 650 MB | ≤ 400 MB |
| Battery, 10 dictations of 10 s | ≤ 2 % | ≤ 3 % | ≤ 3 % |
| Word error rate, English synthetic corpus | within 2 points of the Mac (same model) | same | Tiny's own Mac baseline |
| Keyboard tap to recording | ≤ 500 ms (95th percentile) | ≤ 700 ms | ≤ 900 ms |
