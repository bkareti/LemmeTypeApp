# 0019 — Voice editing flow and context controls

- Status: Accepted
- Date: 2026-10-17
- Stories: E3-S5, E3-S6
- Builds on: 0013 (dictation sessions), 0017 (cursor context), 0018 (on-device rewriting)

## Context

Voice editing reuses the dictation machinery — shortcut, recorder, engines,
delivery — but its speech is an instruction, not text to insert, and it must
never change the user's text unless the rewrite succeeded and the same
selection is still there.

## Decision

- **Second shortcut** — `ActivationController` owns an optional
  voice-editing shortcut (default ⌥⇧Space; `nil` when voice editing is off)
  alongside the dictation shortcut. Both share one `ActivationInterpreter`,
  so push-to-talk/toggle and Escape behave the same, and only one session runs
  at a time: while one shortcut's session is active the other is ignored. It
  sends `ActivationCommand.startEditing(target)` with context captured for
  `.editing` (the selection).
- **Session purpose** — `DictationSession.purpose` is `.dictation` or
  `.editing`. For editing, the pipeline recognises the instruction (whitespace
  normalised, never cleaned into a sentence), runs `TextRewritingRunner`
  (`ProcessingPhase.rewriting`), and delivers the result through the normal
  `TextDelivering`.
- **Refuse before recording** — `DictationProcessing.editingIssue(for:language:)`
  checks the captured selection and model availability; the recorder goes
  `preparing → needsAttention` without starting the microphone, so the user
  never speaks for nothing. New issues: `editingUnavailable(reason)`,
  `rewriterUnavailable(availability)`, `rewriteFailed(error)`; their actions
  never include Copy (there is no result) and Discard always works without a
  recording.
- **Same selection or nothing** — `AccessibilityTextInserter` refuses an
  editing delivery (`targetChanged`) unless the focused element still has the
  exact selection range that was rewritten; the edited text stays available
  for Copy.
- **Controls** — Settings › Context (`ContextSettingsModel`): formatting
  context switch (off by default), voice editing switch (registers or removes
  the shortcut), shortcut recorder, on-device model status, built-in sensitive
  apps, and the user exclusion list (picked from running apps; bundle IDs are
  stored). The overlay shows "Editing selection" and a context line ("Using
  text near the cursor", "Context off for this app", …), also announced to
  VoiceOver; the status menu shows both shortcuts and the context switch.
- **Privacy** — diagnostics get `purpose`, durations (`rewriteSeconds`), and
  issue identifiers only; instruction, selection, and result never.

## Consequences

- Undo after a successful edit is the target app's own Undo (recorded per app
  in the insertion matrix).
- Apps that don't expose text ranges can't be voice-edited; the user sees
  "Select the text you want to change" and nothing is recorded.
