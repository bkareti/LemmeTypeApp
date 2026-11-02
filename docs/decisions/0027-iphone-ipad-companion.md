# 0027 — iPhone and iPad companion

- Status: Accepted for the main-app baseline. The keyboard, Live Activity, and
  background-recording parts are **Proposed** until their device evidence is in
  `docs/testing/ios-feasibility.md`.
- Date: 2026-11-02
- Stories: E8-S1 … E8-S9 (issues #84, #85, #120–#126, epic #8)

## Context

Dictation on a phone is the common case, and the usual alternative sends speech to a
server. LemmeType's promise is that nothing leaves the device. iOS also does not allow
what the Mac does: there is no Accessibility insertion into other apps, a keyboard cannot
record, and a recording needs the app on screen.

## Decision

| Item | Choice |
|---|---|
| Platform | iOS and iPadOS 26.0, arm64, the same Xcode 27 and Swift 6 rules as ADR 0001 |
| Bundle identifier | `com.lemmetype.LemmeType.iOS` (changing it later resets permission grants) |
| Shape | One app target, `LemmeTypeiOS`, in the same project and package; no extension targets |
| Recording | Only while the app is on screen, with visible state, for at most five minutes (Proposed). Going to the background, an interruption, losing the headset, a critical memory warning, or revoked permission ends it. Leaving the screen stops and processes what was said; an interruption deletes the partial recording |
| Delivery | A review, then an explicit **Copy**. The item is local-only (no Universal Clipboard) and expires after 2 minutes (choices 1, 2, 10). Nothing is inserted into another app or sent |
| Starting | An App Intent (`StartQuickDictationIntent`) opens the app and leaves a one-time request that expires after 10 seconds; recording starts once the screen is showing. The device must be unlocked |
| Recognition | The Epic 2 engines unchanged: Apple Speech (on device only) and Whisper. Tiny and Base on devices with 6 GB or more; Small only on iPads with 8 GB or more (Proposed until measured) |
| Rewriting | Foundation Models where the device supports it; otherwise "unavailable" with the reason, never implied parity |
| Personalization | The Epic 4 library, local only. A Mac archive arrives through Files or AirDrop. No iCloud sync |
| History | Not offered on iOS |
| Guardrails | No entitlements, no background modes, no ATS exceptions, a privacy manifest that matches the code, all enforced by `make security-check` |

## Platform facts this rests on (Apple documentation, read 2026-11-02)

- A keyboard without Open Access has "no access to microphone and speaker", cannot write
  the containing app's shared container (it can read it), and has no network.
  Open Access adds network, a writable shared container, Location, and Contacts. **It does not add the microphone.**
  [Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- A keyboard runs in an isolated process, inserts text only through `textDocumentProxy`, has a
  device-dependent memory limit, and may outlive being dismissed. Nothing in the documentation
  lets it learn which app it is in.
  [Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard)
- `AudioRecordingIntent` (iOS 18 and later) requires a Live Activity for the whole recording, or
  the recording stops. [AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent)
- Not established, so not assumed: that an app can return the user to the app they came from, and that a shortcut
  can start a recording from a fully backgrounded app (a developer-forum report says it cannot; unofficial).

## The keyboard question

A keyboard cannot record, so any keyboard design needs the main app to record first. The most
promising design, because it needs neither the microphone nor Full Access: the main app
records and reviews, writes the text to a shared container (the app writes; Apple allows the
keyboard to read without Open Access), and the keyboard inserts it with `insertText`; the item
expires by time instead of being deleted by the keyboard. What is **unproven** is the round
trip: how the user gets from the draft to the app and back without a supported way to
identify or return to the host app. E8-S1 decides with device evidence. Until then **no
keyboard is built and no Full Access is requested.** The copy-and-paste baseline needs neither.

## Portability audit (E8-S3)

| Module | On iOS | How |
|---|---|---|
| `Domain`, `Support`, `ModelAssets`, `Editing` | Builds unchanged | Foundation, CryptoKit, os, Foundation Models only |
| `Audio` | Builds | Core Audio device selection and the sleep notification stay in `AVAudioEngineSource` (macOS); `AVAudioSessionSource` is the iOS source; the mono tap is shared |
| `Permissions` | Builds | Microphone through `AVAudioApplication`; Accessibility does not exist on iOS |
| `Recognition` | Builds | The whisper.cpp XCFramework already has iOS slices; only the Settings link differs |
| `Delivery` | Builds | Accessibility and `NSPasteboard` code is macOS-only; `UIPasteboardWriter` is the iOS copy |
| `Lifecycle` | Builds | The conditions monitor and launch sentinel are shared; login item and single instance are macOS-only |
| `UI` | Builds | AppKit windows, overlay, shortcut recorder, and Mac Settings are macOS-only; `UI/Mobile` holds the iPhone and iPad views |
| `Shortcuts` | Empty on iOS | Global hot keys are macOS-only |
| `Updates` | Not linked | The update check is a Mac feature |
| `TestSupport` | Builds | The libproc socket probe and the `say` benchmark are macOS-only |

`Domain` and `Support` contain no platform conditionals. No file is copied between platforms.

## Alternatives considered

- **A custom keyboard that records.** Not possible: no microphone for keyboards.
- **A Live Activity with `AudioRecordingIntent` for background dictation.** Needs device
  evidence and App Review judgement; kept as a Proposed follow-up.
- **Automatic paste.** iOS has no insertion API for other apps; a paste prompt is the system's.
- **A separate mobile module or package.** Rejected: five guards inside existing modules
  cost less than a second copy of the recognition and writing logic.
- **iCloud sync of personalization.** Out of scope; it would add a network path.

## Consequences

- The Mac gains no behaviour change: every new option defaults to the previous behaviour.
- `make build-ios` and `make test-ios` build and test on the iOS Simulator; CI runs them non-blocking at first.
- Shared strings use `DeviceWords` so the iPhone never says "this Mac".
- The pipeline's `reviewsEveryResult` option and `DictationIssue.reviewText` exist for platforms that cannot insert.

## Evidence still missing (manual, physical devices)

Microphone behaviour for calls, Siri, headsets, and lock; per-device memory, latency, and battery;
WhatsApp, Messages, Notes, and Safari paste behaviour; Action Button and Back Tap; whether a
keyboard round trip is workable. These are MA-66 to MA-72 in `docs/testing/manual-acceptance.md`
and are recorded in `docs/testing/ios-feasibility.md`.
