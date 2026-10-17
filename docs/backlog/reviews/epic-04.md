# Readiness review — Epic 4 (personalization, modes, vocabulary, and snippets)

Reviewed 2026-10-18 with the `story-review` skill against
`docs/backlog/epic-04-personalization.md`, the Epic 3 code on `main`,
ADRs 0001–0019, and the product brief.

## Summary

| Story | Verdict | Main points |
|---|---|---|
| E4-S1 Library and store | Ready with notes | First persisted user content → ADR 0020 narrows the "never persist vocabulary" rule. |
| E4-S2 Vocabulary and replacements | Ready with notes | Runs in Exact too (user-authored, not silent) → recorded in ADR 0020. |
| E4-S3 Snippets | Ready | Whole-utterance only, so nothing expands by accident. |
| E4-S4 Personalization pane | Ready | — |
| E4-S5 Modes | Ready with notes | Session carries a resolved mode; built-in Exact/Clean keep Epic 2 output. |
| E4-S6 Mode management | Ready | Status menu mode picker replaces Exact/Clean. |
| E4-S7 Per-app modes | Ready | Uses the bundle identifier already captured at activation. |
| E4-S8 Export/import/delete | Ready with notes | Save/open panels are manual-only; the codec is unit-tested. |
| E4-S9 Validation | Ready | — |

No blockers.

## Cross-cutting decisions (proposed defaults)

1. **Storage** — one versioned JSON file,
   `~/Library/Application Support/LemmeType/Personalization/library.json`,
   0600 in a 0700 directory, atomic replace. Not `UserDefaults`, which stays
   flags and identifiers only. A file that can't be read (corrupt or newer
   version) is renamed aside, never overwritten. ADR 0020.
2. **Privacy** — personalization text is user content: never logged, never in
   diagnostics (counts and outcome identifiers only), never in errors. Every
   personalization type redacts its `description`.
3. **Order in the pipeline** — recognition (with vocabulary hints) → snippet
   check (whole utterance) → writing mode → vocabulary/replacements → mode style
   (final period) → context formatting → output. Running replacements after
   Clean Writing keeps written forms exactly as the user typed them.
4. **Exact Dictation** — vocabulary and replacements apply in Exact because the
   user wrote those rules; a mode can switch them off. ADR 0014's "Exact never
   changes words" is narrowed to "never changes words except by the user's own
   rules" in ADR 0020.
5. **Matching** — whole words, case-insensitive, longest phrase first,
   left-to-right, one pass. Phrases are matched on word boundaries so
   punctuation next to a phrase is kept.
6. **Recognition hints** — the first 100 vocabulary terms (and their spellings)
   go to Apple Speech `contextualStrings` and to Whisper's initial prompt
   (capped at 400 characters). Hints never leave the Mac.
7. **Modes** — `DictationMode` is a value type; built-ins `exact`, `clean`,
   `message` are code, custom modes live in the library. The active mode id
   is a preference (identifier only). `WritingMode` stays as the cleanup
   choice inside a mode. ADR 0021.
8. **Output** — Insert (existing delivery) or Copy only (clipboard, no target
   app contact). A trailing space is optional. A trailing newline is not
   offered: it can send a message in chat apps, which is a product non-goal.
9. **Per-app rules** — bundle identifier → mode id, evaluated at activation from
   `ActivationTarget.bundleIdentifier`; no new permission.

## Story notes

- **E4-S1** — Limits keep the file small (well under 3 MB) and the matcher fast.
- **E4-S2** — Real-engine hint effect is manual (MA). The hint plumbing is
  unit-tested through the Apple Speech backend fake and the Whisper runtime fake.
- **E4-S3** — Trailing punctuation the engine adds ("Sign off.") is ignored when
  matching.
- **E4-S5** — Engine choice inside a mode replaces the global engine setting
  for that session; the Dictation pane's engine choice becomes the default
  for built-in modes.
- **E4-S8** — Import "replace" keeps nothing from the old library; "merge"
  skips duplicates by the same keys validation uses.

## AC → verification map

| Acceptance criterion | Verification |
|---|---|
| S1 limits, duplicates, identifiers | `PersonalizationLibraryTests` |
| S1 round trip, permissions, atomic, unreadable file kept | `FilePersonalizationStoreTests` |
| S1 redaction / no UserDefaults | `PersonalizationLibraryTests.descriptionsAreRedacted`, code review |
| S2 vocabulary, replacement, whole words, longest match | `PersonalizerTests` |
| S2 Exact and Clean | `PersonalizationPipelineTests` |
| S2 hints | `PersonalizationPipelineTests.vocabularyTermsAreRecognitionHints`, `AppleSpeechEngineTests`, `WhisperEngineTests` |
| S3 snippets | `SnippetMatcherTests`, `PersonalizationPipelineTests` |
| S4 pane (Settings › Dictation segments) | `PersonalizationModelTests`, `PersonalizationDraftTests`, UI `PersonalizationUITests` + manual MA-39 |
| S5 modes | `DictationModeTests`, `ModePipelineTests`, `DictationModePreferencesTests` |
| S6 mode management | `ModesSettingsModelTests` + manual MA-40 |
| S7 per-app | `DictationModeTests.resolverPrefersTheAppRuleThenTheDefault`, `ModesSettingsModelTests` + manual MA-41 |
| S8 export/import/delete | `PersonalizationArchiveTests`, `PersonalizationDataTests` + manual MA-42 |
| S9 end-to-end and canaries | `PersonalizationEndToEndTests` (incl. `personalizationNeverReachesDiagnostics`) |
