# 0007 — Recorder state machine and overlay

- Status: Accepted
- Date: 2026-10-16
- Story: E1-S6

## Decision

- **States**: `idle → preparing → recording → stopping → processing →
  completed`, plus `cancelled` and `failed(AudioCaptureError)`.
  `RecorderStateMachine` (Domain, pure) lists every allowed transition and
  rejects the rest, so a second activation during a session, or an event that
  arrives late, cannot start a parallel recording.
- **Coordinator**: `RecordingCoordinator` (UI) is the only caller of
  `AudioCapturing`. Commands from the shortcut, menu, and overlay are queued and
  run strictly in order (a Push-to-Talk release during `preparing` stops right
  after capture starts). Every end of a session — completed, cancelled, failed —
  calls `onSessionEnded` so the shortcut interpreter re-arms.
- **Processing placeholder**: finished recordings go to a `RecordingConsumer`.
  Epic 1 uses `DiscardingRecordingConsumer`, which deletes the file; Epic 2
  replaces it with transcription and delivery to the captured target.
- **Overlay**: a borderless `.nonactivatingPanel` that overrides
  `canBecomeKey`/`canBecomeMain` to `false`, shown with `orderFrontRegardless`
  at the top centre of the pointer's screen, on all Spaces and over full-screen
  apps. It never takes focus from the target app. Stop and Cancel are clickable
  while recording; failures show the message plus one recovery action
  (Open Permissions, Audio Settings, or Try Again) and Dismiss.
- **Accessibility**: each state has distinct text, symbol, and colour; the
  recording pulse is the only animation and is off under Reduce Motion.
  VoiceOver announcements (high priority) for start, stop, cancel, and failure;
  the level bar is hidden from VoiceOver so levels are never read out.
- **Sounds**: optional start/stop sounds (Tink/Pop), off by default
  (Settings › General).
- **Quit**: `applicationShouldTerminate` cancels an active session (releasing
  the microphone and deleting audio) before the app exits. Sleep ends a session
  through the audio service's interruption handling.

## Consequences

- Completed/cancelled states stay on screen for 1.5 s, failures for 8 s or
  until dismissed.
- The menu's Start Test Recording uses the same coordinator, without a target.
