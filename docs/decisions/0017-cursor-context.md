# 0017 — Cursor context: what may be read, when, and from where

- Status: Accepted
- Date: 2026-10-17
- Stories: E3-S1, E3-S2
- Narrows: 0015 (text delivery never reads text)

## Context

Epic 3 fits dictation into the surrounding sentence and edits selected text by
voice. Both need some of the focused field's text. ADR 0015 said LemmeType
never reads other apps' text; that stays true for delivery, but Epic 3 needs a
narrow, explicit exception that users and reviewers can check.

## Decision

- **Only on a shortcut press.** Context is read inside the shortcut handler,
  right after the target is captured (`TargetCapturing.captureTarget(purpose:)`),
  and at no other time: not while recording, processing, idle, or in the
  background.
- **Bounded.** At most 240 UTF-16 code units before the selection and 40 after
  it. For voice editing only, the selected text up to 4,000 code units; a
  longer selection is refused (`selection-too-long`) rather than truncated so
  an edit never silently drops text. `CursorContext`'s initializer rejects
  values over the bounds, so an app that returns more than asked is ignored.
- **API.** `kAXSelectedTextRangeAttribute`, `kAXNumberOfCharactersAttribute`,
  and `kAXStringForRangeParameterizedAttribute` through
  `AccessibilityDriving.text(in:of:)`. No value attribute, no other element,
  no window titles, no screen content. Covered by the existing Accessibility
  permission; no new TCC permission.
- **Order of checks** (`CursorContextReader`, Domain, generic over the driver
  so CI tests it with `FakeAccessibilityDriver`): app policy (built-in
  sensitive apps → user exclusions → switch for the purpose) → Accessibility
  trust → focused element → password field (`AXSecureTextField`) → secure
  keyboard entry → selection → text. The first failure stops the read and
  becomes a typed `ContextBlockReason`.
- **Policy.** `ContextPolicy` (Domain): formatting context is **off** by
  default; voice editing is **on** by default (it reads only the selection
  and only when its shortcut is pressed). User exclusions block every purpose.
  Built-in sensitive apps (password managers, Keychain Access, Passwords) are
  not user-editable. Preferences store the two switches and bundle
  identifiers only, and the policy is read for every activation.
- **Lifetime and privacy.** The result rides on `ActivationTarget.context`
  and therefore on the `DictationSession`, and is released with it. It is
  never logged, persisted, exported, or put in diagnostics; diagnostics get
  the purpose and the outcome identifier only (`activation.start` →
  `context`), not lengths. `CursorContext.description` is redacted so string
  interpolation cannot leak it.
- **Main actor.** Reading happens synchronously in the shortcut handler with a
  0.25 s messaging timeout per call (≤ 4 calls), so a hung app can delay
  activation by about a second at worst; accepted.

## Consequences

- Apps that don't implement `AXStringForRange` (many Electron apps) get no
  context and behave exactly as in Epic 2; results go in the insertion matrix.
- Swift strings cannot be zeroed; "released" means no reference outlives the
  session. Context never touches disk.
- A future ADR is needed before any wider read (more text, other elements,
  continuous observation).
