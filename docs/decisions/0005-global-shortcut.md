# 0005 — Global shortcut and activation target

- Status: Accepted
- Date: 2026-10-16
- Story: E1-S4

## Decision

- **Carbon hot keys** (`RegisterEventHotKey`) for the dictation shortcut. They
  report press and release (needed for Push to Talk), fire while any app is
  frontmost without activating LemmeType, and need no Input Monitoring.
  `CGEventTap`/`NSEvent` global monitors were rejected: both require Input
  Monitoring, and global monitors cannot report events from secure input.
- **Shortcut rules** (`ShortcutValidation`): one non-modifier key plus at least
  one of ⌘ ⌥ ⌃; Escape is reserved for cancel; common macOS shortcuts are
  rejected. Modifier-only and Fn shortcuts are out of scope (they need an event tap).
- **Default** ⌥Space, Push to Talk. Both are stored in `AppPreferences`.
- **No overlapping sessions**: `ActivationInterpreter` (Domain, pure) ignores
  key auto-repeat, presses within 150 ms of the last accepted press, and
  presses while a Push-to-Talk session is active. The recorder state machine
  (E1-S6) adds its own transition guard.
- **Cancel**: Escape is registered as a hot key only while a session is
  active, so it is never taken from other apps otherwise.
- **Activation target**: on start, `AccessibilityTargetCapturer` records the
  frontmost app's PID, bundle id, name, and (with Accessibility trust) an
  `AXUIElement` for the focused element, with a 250 ms messaging timeout. It
  never reads the element's value or text. The target lives in memory for one
  session only.
- **Changing the shortcut**: the current one is released while recording (so
  pressing it records rather than fires); a failed registration restores the
  previous shortcut and shows a recoverable error. A shortcut unavailable at
  launch is shown in the menu with "Choose Another…".

## Consequences

- Shortcut recording uses a local `NSEvent` monitor, which only sees keys sent
  to LemmeType's own window.
- Key labels come from the user's layout at recording time; the default uses "Space".
- UI tests exercise real Carbon registration (no permission is involved) with
  a fake activation target.
