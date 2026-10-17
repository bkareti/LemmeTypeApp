# 0015 — Text delivery: Accessibility insertion and clipboard fallback

- Status: Accepted
- Date: 2026-10-17
- Stories: E2-S7, E2-S8

## Context

Final text must reach the field that had focus when dictation started,
exactly once, without reading other apps' text and without losing the user's
clipboard. Accessibility support differs widely between apps.

## Decision — Accessibility insertion (E2-S7)

- **Module** — `Delivery` holds the production `DictationTextDelivery`
  (`TextDelivering`). OS access goes through `AccessibilityDriving` (Domain,
  with an `Element` associated type) so the decision logic runs on CI against
  `FakeAccessibilityDriver` (TestSupport); `SystemAccessibilityDriver` is the
  only code that calls the AX API.
- **Target handle** — `FocusedElementReference` gains an opaque `handle`
  (the `AXUIElement` captured by `AccessibilityTargetCapturer`), so Delivery
  can resolve it without depending on `Shortcuts`.
- **Validation, in order** — no target → `noTarget`; not trusted →
  `permissionMissing`; the system-wide focused element must be in the same
  process *and* `CFEqual` to the captured element, otherwise `targetChanged`
  (nothing is typed into the new field; the user can Copy or return to the
  field and Retry Insert); role or subrole `AXSecureTextField` → `secureField`.
  The secure check runs before anything else is read from the element, and
  `IsSecureEventInputEnabled()` blocks insertion as a second guard.
- **Insertion** — one `AXUIElementSetAttributeValue(kAXSelectedText)` call,
  which replaces the current selection or inserts at the caret. If the user
  has not touched the field, that is the selection from activation; if they
  changed the selection in the same field, their new selection wins.
- **Verification without reading text** — compare `kAXNumberOfCharacters`
  before and after with the expected change (inserted UTF-16 length minus the
  selection length), re-reading once after 100 ms for apps that apply changes
  asynchronously:
  - changed → `inserted` (even if the call reported an error);
  - unchanged although a change was expected → *verified not inserted*
    (`unsupported` if the app claimed success — typical of Chromium/Electron —
    or `failed`); only this result may fall back to the clipboard;
  - an error that cannot be verified → *uncertain*: no retry and no automatic
    paste, so text is never inserted twice; Copy Text is offered.
- **Empty text** — text that is empty after the writing mode is never
  delivered (it would erase a selection); the session reports *No speech*.
- **Messaging timeout** — 0.5 s per AX call so a hung target cannot hang
  delivery.

## Consequences

- Electron apps (Slack, VS Code) and some Chromium pages rely on the
  clipboard fallback. Enabling `AXManualAccessibility` on them was rejected:
  it changes another app's state and its performance.
- The per-app results live in `docs/testing/insertion-matrix.md` (manual).
