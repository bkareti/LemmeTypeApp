# 0020 — Personalization data: vocabulary, replacements, and snippets

- Status: Accepted
- Date: 2026-10-18
- Stories: E4-S1, E4-S2, E4-S3 (and E4-S4, E4-S8, which manage it)

## Context

Epic 4 lets users teach LemmeType their own words. That is the first user
content LemmeType keeps between launches. The coding standards said "never
persist user vocabulary", and ADR 0014 said Exact Dictation never changes
words. Both rules need a precise, narrower form.

## Decision

- **Model** — `VocabularyEntry` (term + up to 5 "sounds like" spellings),
  `Replacement` (spoken phrase → written text), and `Snippet` (trigger →
  expansion) in Domain, held by a value-type `PersonalizationLibrary` whose
  every mutation normalizes and validates (lengths, counts, case-insensitive
  duplicates; `PersonalizationError` with stable identifiers). All types
  redact their `description`.
- **Storage** — one versioned JSON file (`PersonalizationArchive`, format
  `com.lemmetype.personalization`, version 1) at
  `~/Library/Application Support/LemmeType/Personalization/library.json`,
  0600 in a 0700 directory, replaced atomically by `FilePersonalizationStore`
  (Support). `UserDefaults` stays flags and identifiers only. A file that can't
  be decoded, or comes from a newer format, is renamed
  `library-unreadable-<time>.json` and reported, never overwritten. Delete All
  removes the library and those copies.
- **Privacy** — personalization text is never logged, never in diagnostics
  (counts, flags, and error identifiers only), and never in errors. It never
  leaves the Mac except in an export file the user explicitly saves (E4-S8).
- **Snapshot per session** — `PersonalizationModel` (UI) holds the library;
  `RecordingCoordinator` copies it into the `DictationSession` when recording
  starts, so edits apply from the next dictation.
- **Pipeline order** — recognition (vocabulary terms as hints) → snippet check
  (whole utterance) → writing mode → `Personalizer` → context formatting →
  delivery. Personalization runs after Clean Writing so the written forms are
  exactly what the user typed (Clean can't recapitalize "iPhone").
- **Matching** — whole words, case-insensitive, longest phrase first (a
  replacement before a vocabulary spelling of the same length), one
  left-to-right pass so replaced text is never matched again.
- **Exact Dictation** — vocabulary and replacements also apply in Exact. ADR
  0014's rule becomes: Exact never changes words *except by rules the user
  wrote*. A mode can switch personalization off (E4-S5).
- **Snippets** — expand only when the whole utterance is the trigger (case,
  whitespace, and edge punctuation ignored); the expansion is delivered
  exactly, with only context spacing applied. Never in voice-editing sessions.
- **Recognition hints** — the first 100 vocabulary terms go to Apple Speech
  `contextualStrings` and to Whisper as an initial prompt
  ("Glossary: A, B.", ≤ 400 characters). Both stay on device.

## Consequences

- The coding-standards privacy rule now reads "never log … user vocabulary";
  persisting it is allowed only through this store.
- Import/export (E4-S8) reuses `PersonalizationArchive`. Import is
  *replace* (everything from the file) or *merge* (`PersonalizationLibrary.merging`:
  imported items get new ids; duplicates by the validation keys and items over
  a limit are skipped; app rules follow their imported modes). Export uses the
  system save panel only, so files land only where the user chooses; modes and app rules
  (E4-S5, E4-S7) are added to the same file with optional keys, so version 1
  files stay readable.
- Matching cost is bounded by the limits (≤ 3,500 phrases, bucketed by first
  character); it is negligible next to recognition.
