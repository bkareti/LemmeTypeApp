# 0014 — Writing modes: Exact Dictation and Clean Writing

- Status: Accepted
- Date: 2026-10-16
- Story: E2-S6

## Context

Users must be able to choose faithful transcription or conservative cleanup,
and LemmeType must never rewrite meaning behind their back. Cleanup runs on
dictated text, so it has to be local, deterministic, and explainable rule by
rule. A language model would be none of those.

## Decision

- **Where**: `TextCleaner` (Domain, Foundation only) is the `write` step of
  `TranscriptionPipeline` (ADR 0013). `AppComposition` passes
  `TextCleaner.write`; it is also the pipeline's default.
- **Exact Dictation** only normalises whitespace: trims the ends, collapses
  runs of spaces and tabs, keeps line breaks, and keeps at most one blank
  line. Words, punctuation, and case are never changed, so Exact cannot
  paraphrase, summarise, change tone, or drop words.
- **Clean Writing** runs the enabled `CleanupRule`s in a fixed order over word
  tokens: spoken punctuation → self-correction → filler words → repeated
  words → capitalisation → terminal punctuation. Same input and
  `CleanupConfiguration` always give the same output.
- **Protected text**: a token is protected when it contains a digit
  (number), is a URL, email address, dotted name, or path (address), is a code
  identifier (camelCase, snake_case, backticks), or sits inside double quotes
  (verbatim). No rule rewrites a protected token. Two documented exceptions,
  each covered by corpus tests:
  - self-correction may replace one number with another
    ("5 sorry 6" → "6");
  - terminal punctuation may add a period after an identifier
    (`retry_count.`), but never after a number, address, or quote, where the
    period could read as part of it.
- **Self-correction** removes `X <marker> Y` only when X and Y are single
  words of the same kind (weekday, month except "May"/"March", number) and
  the marker ("sorry", "I mean", "no wait") stands alone or is set off by
  dashes or commas. Anything else ("Sorry I'm late", "Tell Anna sorry Ben is
  out") is left unchanged.
- **"period"** is a spoken mark only as the last word, so "the period of
  time" survives.
- **Traceability**: every change is a `CleanupTransformation` (rule, before,
  after). It contains dictated text, so it stays in memory and is never
  logged or recorded in diagnostics.
- **Configuration**: `CleanupConfiguration` is a `Codable` set of enabled
  rules, all on by default, ready for a settings screen. It is not persisted
  yet; E2-S9 adds the UI.
- **Visibility**: `RecordingCoordinator.writingMode` (observable, backed by
  preferences, Exact by default) is shown in the status menu ("Writing Mode:
  …") and in the overlay while preparing and recording. Each
  `DictationSession` stores the mode when the recording ends.

## Consequences

- Rules are English-only for now; other languages get Exact behaviour
  unchanged plus whatever rules happen not to match.
- Adding a rule means a new `CleanupRule` case with a stable raw value, a
  position in the fixed order, and corpus cases naming it.
- The corpus in `TextCleanerTests` is the specification: change a rule, not
  an expectation, unless the story says otherwise.
