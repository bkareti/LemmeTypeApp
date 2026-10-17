# 0021 — Dictation modes and per-app mode rules

- Status: Accepted
- Date: 2026-10-18
- Stories: E4-S5, E4-S6, E4-S7

## Context

Epic 2 offered two writing modes (Exact, Clean) and one global engine and
language. Epic 4 needs named modes that bundle transcription, cleanup, style,
and output, chosen manually or by the app being dictated into.

## Decision

- **Model** — `DictationMode` (Domain value type): name; engine and language
  (`nil` = Settings › Dictation); `WritingMode` plus the enabled
  `CleanupRule`s; style (vocabulary/replacements on/off, snippets on/off,
  `FinalPunctuation.keep/omit`); output (`OutputAction.insert/copy`, optional
  trailing space). `WritingMode` stays as the cleanup choice inside a mode.
- **Built-ins** — `exact` and `clean` reproduce Epic 2 exactly; `message` is
  Clean without a final period. They are code, can be duplicated, and can't be
  edited or deleted. Up to 20 custom modes (`custom-<uuid>` ids) and 100 app
  rules live in the personalization file (ADR 0020), so they export with it.
- **Default mode** — `AppPreferences.dictationMode` stores the identifier
  only. Without a stored value it is the built-in matching the Epic 2
  `writingMode` preference (migration with no data rewrite). The Dictation
  pane's Exact/Clean choice sets the matching built-in default.
- **Resolution** — `ModeResolver` (pure) runs once per activation from
  `ActivationTarget.bundleIdentifier`: app rule → default → Clean Writing. A
  rule whose mode was deleted falls back to the default; deleting a mode
  removes its rules, and deleting the default makes Clean the default.
- **Session** — `SessionSettings` (UI) captures the resolved mode, language,
  engine preference, and personalization when recording starts;
  `DictationSession.dictationMode`/`modeSource` carry them. Settings changes
  apply from the next session.
- **Pipeline** — snippet (if enabled) → writing mode with the mode's rules →
  final-period style → personalization (if enabled) → context → trailing
  space → output. Copy only uses `TextCopying` and never touches the target
  app (`DeliveryMethod.copied`). A trailing newline is not offered: it can
  send a message in chat apps (a product non-goal).
- **UI** — Settings › Dictation › Modes (default mode, custom modes, per-app
  rules) and the status menu's *Mode* picker. The settings window keeps its
  width, so modes are a segment of the Dictation tab, not a new tab. The
  overlay shows the mode name (and "for this app" for a rule) and VoiceOver
  announces it at start.
- **Diagnostics** — `dictationMode` is the built-in id or `custom`;
  `modeSource` is `default` or `app-rule`. Mode names and apps are never recorded.

## Consequences

- Engine choice can differ per mode; the fallback switch stays global.
- New mode settings must be optional in the file format (decodeIfPresent)
  or bump `PersonalizationArchive.currentFormatVersion`.
