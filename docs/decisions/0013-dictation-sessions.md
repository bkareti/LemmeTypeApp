# 0013 — Dictation sessions and processing

- Status: Accepted
- Date: 2026-10-16
- Story: E2-S5

## Decision

- **Session**: each finished recording becomes one `DictationSession` (Domain)
  with its own ID, the activation target, the audio file, the writing mode and
  language read at that moment (since E2-S9: when recording *starts*, with the
  engine preference — ADR 0016), and the engine (fixed when processing first
  picks it). Settings changes therefore only affect later sessions.
- **Owner**: `RecordingCoordinator` (UI) owns the current session. Processing
  runs in its own task, outside the serial command queue, so Cancel works
  during recognition. Outcomes and progress are applied only while their
  session is still the current one; a late result from a cancelled or replaced
  session is dropped.
- **Processing**: `DictationProcessing` (Domain) replaces Epic 1's
  `RecordingConsumer`. The production `TranscriptionPipeline` (Domain — it
  orchestrates Domain protocols only and is fully testable without OS
  frameworks) selects the engine with `EngineSelector`, recognises through
  `RecognitionRunner`, applies the writing mode, and delivers through
  `TextDelivering`.
- **Engine choice**: Automatic uses the first ready engine in recommendation
  order. A user-chosen engine that is not ready is never swapped silently: the
  session stops with `engineUnavailable` and offers the ready alternatives.
- **Needs attention**: a new terminal recorder state
  `needsAttention(DictationIssue)` holds the recording (and any transcript, in
  memory) until the user picks an action: Retry (same engine), Use <other
  engine>, Allow Speech Recognition, Choose Engine…, Save Audio…, Copy Text,
  Retry Insert, Open Permissions, or Discard. It stays on screen for up to two
  minutes; dismissing it, starting a new recording, or quitting deletes the
  recording.
- **Audio lifecycle** (history is off in the MVP): deleted after successful
  delivery, on cancel, on failure, on discard, when replaced by a new
  recording, on quit, and at next launch. Save Audio… copies the file to a
  location the user picks; that copy is theirs.
- **Crash/quit/sleep**: no session state is persisted, so nothing can remain
  "recording" after a crash; quit cancels any active or waiting session;
  sleep interrupts capture (ADR 0007).
- **Metrics**: `session.delivered`, `session.needs-attention`,
  `session.cancelled` with outcome, engine, issue identifier, audio and
  processing durations — never audio or text.
- **Interim delivery**: until E2-S7/E2-S8, the new `Delivery` module copies the
  final text to the clipboard (`CopyingTextDelivery`) and reports `.copied`.
  *Replaced by `DictationTextDelivery` — see ADR 0015.*
- **Default writing mode** is Exact; the user switches to Clean in Settings (E2-S9).
