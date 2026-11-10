# 0032. Action Button dictation and the LemmeType keyboard

- Status: Proposed, for maintainer device testing. It changes ADR 0027 and the 2026-11-02 seamless-writing review.

## Context

Copy and Paste forces a trip through LemmeType for every message. A keyboard extension has no microphone on
iOS. iOS also has no public way to switch to a third-party keyboard automatically. Device tests on an iPhone 18
Pro Max (iOS 27.0.1, 2026-11-10, `spike/keyboard-mic-session`) found:

- With Full Access off, a keyboard can read the App Group but cannot write to it or send a Darwin notification.
- A keyboard-started session that keeps the microphone open works, but needs Full Access. Stopping the audio
  engine and restarting it from the background failed.
- `AudioRecordingIntent` started recording from the background repeatedly with the microphone fully off between
  dictations. Without `LiveActivityIntent` too, `Activity.request` fails with `visibility` and iOS ends the app.
- A keyboard with Full Access off inserted the result in Messages and WhatsApp.

## Decision

- The Action Button runs `DictateAnywhereIntent`: one press starts, the next stops. It is declared only in the
  app, because the Action Button picker failed when the widget declared the same intent.
- A status-only Live Activity shows the recording. It never carries text.
- `ActionDictationController` uses the existing recorder and pipeline, so modes, cloud speech, and translation
  are unchanged. The finished text goes to `KeyboardHandoff` instead of waiting for Copy.
- The keyboard stays active, has typing keys, and swaps them for a recording view. It requests no Full Access,
  and `make security-check` enforces that.
- A translation is inserted without the earlier review step (ADR 0023). It lands in the draft and is never sent,
  so the user reads it there.

## Security and privacy

- New capabilities: one App Group, the `audio` background mode, and Live Activities.
- The microphone is on only between the two presses.
- The shared file holds one result, is excluded from backups, is erased after 25 seconds or when background time
  ends, and is ignored by the keyboard once stale. Text also stays in memory in the Quick Dictation review.

## Consequences

- Typing is less capable than Apple's keyboard: no autocorrect or suggestions.
- Inserting needs the LemmeType keyboard to be active. Otherwise the text is in Quick Dictation for Copy.
- Background time after Stop is limited, so a very long cloud upload may not finish.
- Whisper uses the CPU in the background, which is slower.

## Before release

Maintainer testing and feedback; App Review's view of the background audio mode; an in-app setup guide; manual
acceptance steps; the threat model and privacy text; Telugu needs the cloud launch gates in ADR 0031.
