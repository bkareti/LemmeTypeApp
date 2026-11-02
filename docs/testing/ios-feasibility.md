# iPhone and iPad feasibility and device evidence

The record for E8-S1 and E8-S2 (ADR 0027). A simulator is not evidence: every row in the
device tables is filled in on a physical iPhone or iPad with **synthetic speech and
test text only**. No real messages, names, or recordings go in this file or in a pull request.

Status words: **Demonstrated** (done and recorded), **Not demonstrated** (not yet tried),
**Not supported** (tried; the platform does not allow it, with the evidence).

## Desk evidence (Apple documentation, 2026-11-02)

| Question | Answer | Source |
|---|---|---|
| Can a keyboard use the microphone? | No, with or without Open Access | Configuring open access for a custom keyboard |
| What does Open Access add? | Network, a writable shared container, Location, Contacts | same |
| Can a keyboard read the app's shared container without Open Access? | Yes (read-only) | same |
| How does a keyboard insert text? | `textDocumentProxy.insertText` | Creating a custom keyboard |
| Can a keyboard identify its host app? | Not documented; assumed no | Creating a custom keyboard |
| Does `AudioRecordingIntent` need a Live Activity? | Yes, for the whole recording | AudioRecordingIntent |

## Test devices

| Device | OS | Memory | Tester | Date |
|---|---|---|---|---|
| _iPhone (6 GB class)_ | | | | |
| _iPhone (8 GB class)_ | | | | |
| _iPad_ | | | | |

## Workflow paths (E8-S1)

Record the **exact taps and app switches** for each path. Start from an empty draft in the host app.

| Path | Steps | Result | Notes |
|---|---|---|---|
| Main app: Dictate → Copy → switch to the host app → paste | | Not demonstrated | The baseline |
| Action Button runs *Start Dictating* (unlocked) | | Not demonstrated | |
| Back Tap runs *Start Dictating* | | Not demonstrated | |
| Siri phrase | | Not demonstrated | |
| Shortcut while locked | | Not demonstrated | Expected: asks to unlock |
| Shortcut with the app already in the background | | Not demonstrated | Does recording start only once the screen shows? |
| Keyboard reads text the app saved and inserts it | | Not demonstrated | Proposed; needs no Full Access |
| Returning from the app to the draft | | Not demonstrated | Which supported flow exists? |
| `AudioRecordingIntent` with a Live Activity | | Not demonstrated | Proposed |

## Host app and field matrix (E8-S2)

Paste the result into each; do not send.

| Host | Plain field | Secure field | Phone-pad field | Rejects custom keyboards | Notes |
|---|---|---|---|---|---|
| Messages | | | | | |
| WhatsApp | | | | | |
| Notes | | | | | |
| Safari | | | | | |

## Lifecycle and failure matrix

| Event | Expected | Result |
|---|---|---|
| Incoming call during recording | Recording stops; the partial recording is deleted; message offers Try Again | Not demonstrated |
| Siri or an alarm during recording | Same | Not demonstrated |
| Headset removed during recording | Same | Not demonstrated |
| Lock the screen during recording | Recording stops and what was said is processed when the app is next shown | Not demonstrated |
| Switch apps during recording | Recording stops and is processed | Not demonstrated |
| Reach the five-minute limit | Recording stops and is processed; the user is told | Not demonstrated |
| Microphone permission revoked while recording | Recording stops; Open Settings is offered | Not demonstrated |
| Force-quit during processing, then relaunch | No recording is left; the app starts clean | Not demonstrated |
| Low memory (many apps open) | A model that does not fit is refused with a reason; no crash | Not demonstrated |
| Airplane mode after models are installed | Dictation works | Not demonstrated |

## Local model feasibility (per device class)

Assess each separately; no silent server dependency.

| Capability | Model | iPhone 6 GB | iPhone 8 GB | iPad |
|---|---|---|---|---|
| Transcription (English) | Whisper Tiny / Base | | | |
| Transcription (Hindi, Telugu) | Whisper multilingual | | | |
| Speech to English | Whisper multilingual | | | |
| Tone and style | Foundation Models | | | |

## Proposed thresholds (not approved)

Approval is a product-owner action; Epic 8 acceptance needs it.

| Metric | Proposed |
|---|---|
| Capture stop to text on screen, a 10-second utterance, Base, 8 GB iPhone | ≤ 4 s |
| Peak memory while a Base model is loaded | ≤ 650 MB above idle |
| Battery, 10 dictations of 10 seconds | ≤ 2 % |
| Word error rate, English synthetic corpus, Base | within 2 points of the Mac result |
