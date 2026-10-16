# 0008 — Privacy-safe diagnostics

- Status: Accepted
- Date: 2026-10-16
- Story: E1-S7

## Decision

- **Structured events** (`DiagnosticEvent`) in five categories: lifecycle,
  permissions, shortcut, audio, recorder. Recorded into an in-memory ring
  buffer (`DiagnosticsBuffer`, 500 events). Nothing is written to disk or sent.
- **Redaction by construction**: event names and attribute keys are
  `StaticString` literals; values are `identifier`, `count`, `flag`, or
  `seconds`. Identifiers must match `^[a-z0-9][a-z0-9._-]{0,63}$` and are
  re-validated when an event is created, so free text (device or app names,
  dictated or field text, clipboard values, file contents, vocabulary) is
  replaced with `redacted`. Audio levels are never recorded.
- **What is recorded**: permission status changes, shortcut registration
  results and mode, activation start/stop/cancel (mode and whether a focused
  element was captured), capture start (system default vs specific device,
  fallback), stop duration, cancel, failure identifiers, recorder state
  transitions, launch and quit requests.
- **Stable error identifiers** come from `LemmeTypeError.identifier`; each
  expected failure has a user-facing message and a recovery action (overlay
  action, "Choose Another…" for shortcuts, "Open Login Items Settings…").
- **Export** (Settings › Diagnostics): an explicit Preview shows the exact
  JSON (`DiagnosticsReport`: app version and build, macOS version, hardware
  model identifier, permission states, activation mode, events); Save writes
  that same content to a location the user chooses. There is no upload path.

## Consequences

- os_log output remains for local debugging with `.private` interpolation;
  the exportable report is built only from the buffer.
- Adding a field to `DiagnosticsReport` is a privacy decision and needs review.
- `DiagnosticsPrivacyTests` runs a full and a failing session with canary
  secrets in audio metadata, target app identity, field and clipboard text,
  and vocabulary, and asserts none reach the export.
