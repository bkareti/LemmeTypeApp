# LemmeType product brief

## Vision

LemmeType helps people write anywhere on macOS by speaking naturally. It turns
rough speech into text that is ready to send while keeping audio, dictated text,
and surrounding cursor context on the device.

## Positioning

> Apple Dictation types what you say. LemmeType turns what you mean into
> ready-to-send writing.

LemmeType is not positioned as a general assistant or a replacement for Siri.
It is a focused, keyboard-driven voice-writing tool.

## Primary workflow

1. The user places the cursor in an editable field.
2. The user activates a configurable global shortcut.
3. LemmeType records until the shortcut is released or pressed again.
4. A local speech engine produces a transcript.
5. The selected writing mode optionally cleans the transcript.
6. LemmeType inserts the result into the previously active application.
7. Temporary audio and context are deleted unless retention was explicitly enabled.

## MVP scope

- macOS menu-bar application.
- Push-to-talk and toggle shortcuts.
- English dictation.
- Apple Speech plus one optional downloadable local model.
- Exact Dictation and Clean Writing modes.
- Automatic capitalization, punctuation, filler removal, and basic self-correction.
- Accessibility-based insertion with clipboard fallback.
- Microphone and model selection.
- Clear local-processing status.
- History disabled by default.

## Later scope

- Context-aware formatting and reply drafting.
- Selected-text voice editing.
- Per-application modes and writing styles.
- Custom vocabulary, replacements, and snippets.
- More languages and language auto-detection.
- Advanced model management and performance profiles.
- iPhone and iPad companion experience.

## Non-goals for the first release

- Cloud accounts or mandatory cloud processing.
- Meeting recording and speaker diarization.
- Team workspaces and shared vocabulary.
- Continuous screen monitoring.
- Automatically sending generated messages.
- A complete Siri-style general assistant.

## Success measures

- A new user completes onboarding and their first dictation without support.
- A short dictation is delivered quickly enough to feel faster than typing.
- The app never uploads audio, transcript, or cursor context in Local mode.
- Insertion succeeds in the supported application test matrix or presents a safe fallback.
- Exact Dictation preserves meaning without hidden rewriting.
- A user can undo or recover from every insertion failure.
